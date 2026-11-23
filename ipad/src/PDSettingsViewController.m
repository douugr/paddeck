#import "PDSettingsViewController.h"
#import "PDSettings.h"
#import "PDDeck.h"
#import "PDTheme.h"

typedef NS_ENUM(NSInteger, PDRow) {
    RowPointer, RowScroll, RowNatural, RowInertia, RowTapClick, RowTapDrag,   // section 0
    RowKeepAwake, RowKeyClick, RowKeyboardOnTop,                                   // section 1
    RowResetDeck,                                                 // section 2
    RowAbout,                                                     // section 3
};

@implementation PDSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ajustes";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.tableView.backgroundColor = PDColorBar();
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.tableView.rowHeight = 56;
}

- (void)done {
    void (^close)(void) = self.onClose;
    [self dismissViewControllerAnimated:YES completion:^{ if (close) close(); }];
}

- (NSArray *)sections {
    return @[ @[@(RowPointer), @(RowScroll), @(RowNatural), @(RowInertia), @(RowTapClick), @(RowTapDrag)],
              @[@(RowKeyboardOnTop), @(RowKeyClick), @(RowKeepAwake)],
              @[@(RowResetDeck)],
              @[@(RowAbout)] ];
}

- (PDRow)rowAt:(NSIndexPath *)ip {
    return (PDRow)[[self sections][(NSUInteger)ip.section][(NSUInteger)ip.row] integerValue];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)[self sections].count; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)[[self sections][(NSUInteger)s] count];
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"Trackpad", @"Geral", @"Atalhos", @"Sobre"][(NSUInteger)s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"Rolagem com inércia: deslize dois dedos rápido e solte para a página continuar rolando; "
                       @"encoste no trackpad para parar.\n\n"
                       @"Toque duplo e arraste: toque uma vez e, logo em seguida, encoste e arraste para "
                       @"segurar o clique. Com ele ligado, o clique simples espera um instante.";
    if (s == 2) return @"Para editar um botão, segure-o na tela de atalhos.";
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)view forSection:(NSInteger)s {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]])
        ((UITableViewHeaderFooterView *)view).textLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
}

- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)s {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]])
        ((UITableViewHeaderFooterView *)view).textLabel.textColor = [UIColor colorWithWhite:1 alpha:0.4];
}

- (UISlider *)sliderFor:(NSString *)key {
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 240, 34)];
    s.minimumValue = 0.5;
    s.maximumValue = 4;
    s.value = [[NSUserDefaults standardUserDefaults] floatForKey:key];
    s.minimumTrackTintColor = PDColorAccent();
    s.accessibilityIdentifier = key;
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    return s;
}

- (UISwitch *)switchFor:(NSString *)key {
    UISwitch *s = [[UISwitch alloc] init];
    s.on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
    s.onTintColor = PDColorOK();
    s.accessibilityIdentifier = key;
    [s addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return s;
}

- (void)sliderChanged:(UISlider *)s {
    [[NSUserDefaults standardUserDefaults] setFloat:s.value forKey:s.accessibilityIdentifier];
}

- (void)switchChanged:(UISwitch *)s {
    [[NSUserDefaults standardUserDefaults] setBool:s.on forKey:s.accessibilityIdentifier];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    c.backgroundColor = PDColorSurface();
    c.textLabel.textColor = [UIColor whiteColor];
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.45];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    switch ([self rowAt:ip]) {
        case RowPointer:
            c.textLabel.text = @"Velocidade do cursor";
            c.accessoryView = [self sliderFor:PDPrefPointerSpeed];
            break;
        case RowScroll:
            c.textLabel.text = @"Velocidade da rolagem";
            c.accessoryView = [self sliderFor:PDPrefScrollSpeed];
            break;
        case RowInertia:
            c.textLabel.text = @"Rolagem com inércia";
            c.accessoryView = [self switchFor:PDPrefInertialScroll];
            break;
        case RowNatural:
            c.textLabel.text = @"Rolagem natural";
            c.accessoryView = [self switchFor:PDPrefNaturalScroll];
            break;
        case RowTapClick:
            c.textLabel.text = @"Tocar para clicar";
            c.accessoryView = [self switchFor:PDPrefTapToClick];
            break;
        case RowTapDrag:
            c.textLabel.text = @"Toque duplo e arraste";
            c.accessoryView = [self switchFor:PDPrefTapToDrag];
            break;
        case RowKeyboardOnTop:
            c.textLabel.text = @"Teclado em cima do trackpad";
            c.accessoryView = [self switchFor:PDPrefKeyboardOnTop];
            break;
        case RowKeyClick:
            c.textLabel.text = @"Som ao tocar nas teclas";
            c.accessoryView = [self switchFor:PDPrefKeyClick];
            break;
        case RowKeepAwake:
            c.textLabel.text = @"Manter a tela do iPad acesa";
            c.accessoryView = [self switchFor:PDPrefKeepAwake];
            break;
        case RowResetDeck:
            c.textLabel.text = @"Restaurar atalhos padrão";
            c.textLabel.textColor = PDColorOff();
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        case RowAbout: {
            NSString *v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            c.textLabel.text = @"PadDeck";
            c.detailTextLabel.text = [NSString stringWithFormat:@"versão %@ · agente do Mac: github.com/douugr/paddeck", v];
            break;
        }
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if ([self rowAt:ip] != RowResetDeck) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Restaurar atalhos?"
        message:@"Todos os botões voltam ao padrão. Os botões que você criou serão apagados."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Restaurar" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[PDDeck shared] resetToDefaults];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
