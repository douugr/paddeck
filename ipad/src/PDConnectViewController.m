#import "PDConnectViewController.h"
#import "PDMainViewController.h"
#import "PDConnection.h"
#import "PDSettings.h"
#import "PDTheme.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>

@interface PDConnectViewController () <UITableViewDataSource, UITableViewDelegate,
                                        NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property (nonatomic, strong) NSNetServiceBrowser *browser;
@property (nonatomic, strong) NSMutableArray *services;
@property (nonatomic, strong) NSNetService *resolving;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *manualButton;
@property (nonatomic, copy) NSString *pendingHost;
@property (nonatomic, copy) NSString *pendingName;
@property (nonatomic) BOOL triedAuto;
@end

@implementation PDConnectViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PDColorBackground();
    self.services = [NSMutableArray array];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"PadDeck";
    title.textColor = [UIColor whiteColor];
    title.font = PDFont(44, PDWeightBold);
    title.textAlignment = NSTextAlignmentCenter;
    title.frame = CGRectMake(0, 70, self.view.bounds.size.width, 54);
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:title];

    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"Teclado, trackpad e atalhos para o seu Mac";
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    sub.font = [UIFont systemFontOfSize:18];
    sub.textAlignment = NSTextAlignmentCenter;
    sub.frame = CGRectMake(0, 126, self.view.bounds.size.width, 26);
    sub.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:sub];

    CGFloat w = 520;
    self.table = [[UITableView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - w) / 2, 200, w, 330)
                                              style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    self.table.backgroundColor = PDColorSurface();
    self.table.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.table.layer.cornerRadius = 14;
    self.table.rowHeight = 64;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.tableFooterView = [[UIView alloc] init];
    [self.view addSubview:self.table];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.frame = CGRectMake(CGRectGetMinX(self.table.frame), 548, 20, 20);
    self.spinner.autoresizingMask = self.table.autoresizingMask;
    [self.spinner startAnimating];
    [self.view addSubview:self.spinner];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMinX(self.table.frame) + 30, 544, w - 30, 28)];
    self.statusLabel.autoresizingMask = self.table.autoresizingMask;
    self.statusLabel.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    self.statusLabel.font = [UIFont systemFontOfSize:15];
    [self.view addSubview:self.statusLabel];

    self.manualButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.manualButton setTitle:@"Conectar por IP…" forState:UIControlStateNormal];
    self.manualButton.titleLabel.font = [UIFont systemFontOfSize:17];
    self.manualButton.frame = CGRectMake((self.view.bounds.size.width - 240) / 2, 600, 240, 44);
    self.manualButton.autoresizingMask = self.table.autoresizingMask;
    [self.manualButton addTarget:self action:@selector(manual) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.manualButton];

    UILabel *help = [[UILabel alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 60, self.view.bounds.size.width, 40)];
    help.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    help.text = @"Abra o PadDeck no Mac (o PIN aparece no menu dele). Pelo cabo USB, conecta sozinho, sem PIN.";
    help.textColor = [UIColor colorWithWhite:1 alpha:0.35];
    help.font = [UIFont systemFontOfSize:14];
    help.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:help];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionChanged)
                                                 name:PDConnectionChangedNotification object:nil];
    [self updateStatus];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startBrowsing];
    if (!self.triedAuto) {
        self.triedAuto = YES;
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSString *host = [d stringForKey:PDPrefLastHost];
        NSString *pin = [d dictionaryForKey:PDPrefPins][host];
        if (host.length && pin.length) {
            [[PDConnection shared] connectToHost:host name:[d stringForKey:PDPrefLastName] pin:pin];
        }
    }
    PDConnection *c = [PDConnection shared];
    if (c.state == PDStateIdle && c.lastDenyReason == 1) {
        // Came back from the main screen because the PIN changed on the Mac.
        self.pendingHost = c.host;
        self.pendingName = c.macName;
        [self askPIN:@"O PIN mudou no Mac. Digite o novo PIN."];
    }
    [self updateStatus];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.browser stop];
    self.browser = nil;
}

#pragma mark - Bonjour

- (void)startBrowsing {
    if (self.browser) return;
    [self.services removeAllObjects];
    [self.table reloadData];
    self.browser = [[NSNetServiceBrowser alloc] init];
    self.browser.delegate = self;
    [self.browser searchForServicesOfType:@"_paddeck._tcp." inDomain:@"local."];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)b didFindService:(NSNetService *)s moreComing:(BOOL)more {
    [self.services addObject:s];
    if (!more) [self.table reloadData];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)b didRemoveService:(NSNetService *)s moreComing:(BOOL)more {
    [self.services removeObject:s];
    if (!more) [self.table reloadData];
}

- (void)netService:(NSNetService *)s didNotResolve:(NSDictionary *)err {
    self.resolving = nil;
    [self alert:@"Não foi possível encontrar o endereço desse Mac." title:s.name];
}

- (void)netServiceDidResolveAddress:(NSNetService *)s {
    NSString *ip = nil;
    for (NSData *a in s.addresses) {
        const struct sockaddr *sa = a.bytes;
        if (sa->sa_family == AF_INET) {
            char buf[INET_ADDRSTRLEN];
            const struct sockaddr_in *in = (const struct sockaddr_in *)sa;
            if (inet_ntop(AF_INET, &in->sin_addr, buf, sizeof buf)) { ip = [NSString stringWithUTF8String:buf]; break; }
        }
    }
    [s stop];
    self.resolving = nil;
    if (!ip) {
        [self alert:@"Esse Mac não tem um endereço IPv4 na rede." title:s.name];
        return;
    }
    [self connectHost:ip name:s.name];
}

#pragma mark - Connecting

- (void)connectHost:(NSString *)host name:(NSString *)name {
    self.pendingHost = host;
    self.pendingName = name;
    NSDictionary *pins = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PDPrefPins];
    NSString *pin = pins[name] ?: pins[host];
    if (pin.length) {
        [[PDConnection shared] connectToHost:host name:name pin:pin];
    } else {
        [self askPIN:nil];
    }
}

- (void)askPIN:(NSString *)message {
    NSString *name = self.pendingName ?: self.pendingHost;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"PIN de %@", name]
        message:message ?: @"Digite o PIN mostrado no menu do PadDeck no Mac."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.placeholder = @"0000";
        tf.textAlignment = NSTextAlignmentCenter;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Conectar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *pin = wa.textFields.firstObject.text ?: @"";
        [[PDConnection shared] connectToHost:self.pendingHost name:self.pendingName pin:pin];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)manual {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Conectar por IP"
        message:@"Endereço do Mac na rede (Ajustes do Sistema › Wi-Fi › Detalhes)."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.placeholder = @"192.168.0.10";
        tf.text = [[NSUserDefaults standardUserDefaults] stringForKey:PDPrefLastHost];
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Continuar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *ip = [wa.textFields.firstObject.text stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
        if (ip.length) [self connectHost:ip name:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)connectionChanged {
    PDConnection *c = [PDConnection shared];
    [self updateStatus];
    if (c.state == PDStateConnected && !self.presentedViewController) {
        PDMainViewController *main = [[PDMainViewController alloc] init];
        [self presentViewController:main animated:YES completion:nil];
    } else if (c.state == PDStateIdle && c.lastDenyReason == 1 && self.isViewLoaded && self.view.window
               && !self.presentedViewController) {
        if (!self.pendingHost) {
            self.pendingHost = c.host;
            self.pendingName = c.macName;
        }
        [self askPIN:@"PIN incorreto. Confira no menu do PadDeck no Mac."];
    } else if (c.state == PDStateIdle && c.lastDenyReason > 1 && !self.presentedViewController) {
        [self alert:c.lastError title:@"Não conectado"];
    }
}

- (void)updateStatus {
    PDConnection *c = [PDConnection shared];
    switch (c.state) {
        case PDStateConnecting:
            self.statusLabel.text = c.lastError
                ? [NSString stringWithFormat:@"%@ — tentando %@ de novo…", c.lastError, c.macName ?: c.host]
                : [NSString stringWithFormat:@"Conectando a %@…", c.macName ?: c.host];
            break;
        case PDStateConnected:
            self.statusLabel.text = [NSString stringWithFormat:@"Conectado a %@", c.macName];
            break;
        default:
            self.statusLabel.text = self.services.count ? @"Toque no Mac para conectar"
                                                        : @"Procurando Macs na rede…";
            break;
    }
}

- (void)alert:(NSString *)msg title:(NSString *)title {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.services.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"mac"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mac"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = PDFont(20, PDWeightMedium);
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.45];
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = PDColorSurfaceActive();
        cell.selectedBackgroundView = sel;
    }
    NSNetService *s = self.services[(NSUInteger)ip.row];
    cell.textLabel.text = s.name;
    NSDictionary *pins = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PDPrefPins];
    cell.detailTextLabel.text = pins[s.name] ? @"PIN salvo" : @"Toque para conectar";
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSNetService *s = self.services[(NSUInteger)ip.row];
    [self.resolving stop];
    self.resolving = s;
    s.delegate = self;
    [s resolveWithTimeout:5];
}

@end
