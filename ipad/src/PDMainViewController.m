#import "PDMainViewController.h"
#import "PDTrackpadView.h"
#import "PDKeyboardView.h"
#import "PDDeck.h"
#import "PDSlotEditor.h"
#import "PDSettingsViewController.h"
#import "PDConnection.h"
#import "PDKeys.h"
#import "PDSettings.h"
#import "PDTheme.h"

#pragma mark - iOS keyboard sink

/// Invisible responder that forwards the iOS keyboard (accents, emoji, dictation) to the Mac.
@interface PDTextSink : UIView <UIKeyInput>
@property (nonatomic) UITextAutocorrectionType autocorrectionType;
@property (nonatomic) UITextAutocapitalizationType autocapitalizationType;
@property (nonatomic) UITextSpellCheckingType spellCheckingType;
@property (nonatomic) UIKeyboardAppearance keyboardAppearance;
@end

@implementation PDTextSink
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _autocorrectionType = UITextAutocorrectionTypeNo;
        _autocapitalizationType = UITextAutocapitalizationTypeNone;
        _spellCheckingType = UITextSpellCheckingTypeNo;
        _keyboardAppearance = UIKeyboardAppearanceDark;
    }
    return self;
}
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)hasText { return YES; }   // keeps backspace working
- (void)insertText:(NSString *)text { [[PDConnection shared] sendText:text]; }
- (void)deleteBackward { [[PDConnection shared] sendKey:PDKeyDelete mods:0 action:2]; }
@end

#pragma mark - Main

@interface PDMainViewController () <PDKeyboardViewDelegate, PDDeckViewDelegate>
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UIView *dot;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UIButton *keyboardButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIButton *disconnectButton;
@property (nonatomic, strong) PDTrackpadView *trackpad;
@property (nonatomic, strong) PDKeyboardView *keyboard;
@property (nonatomic, strong) PDDeckView *deck;
@property (nonatomic, strong) PDTextSink *sink;
@property (nonatomic) BOOL leaving;
@end

@implementation PDMainViewController

- (UIButton *)barButton:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16];
    b.tintColor = PDColorAccent();
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self.bar addSubview:b];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PDColorBackground();

    self.bar = [[UIView alloc] init];
    self.bar.backgroundColor = PDColorBar();
    [self.view addSubview:self.bar];

    self.dot = [[UIView alloc] initWithFrame:CGRectMake(16, 21, 10, 10)];
    self.dot.layer.cornerRadius = 5;
    [self.bar addSubview:self.dot];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.textColor = [UIColor colorWithWhite:1 alpha:0.75];
    self.statusLabel.font = [UIFont systemFontOfSize:15];
    [self.bar addSubview:self.statusLabel];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Trackpad e teclado", @"Atalhos"]];
    self.modeControl.tintColor = PDColorAccent();
    self.modeControl.selectedSegmentIndex = 0;
    [self.modeControl addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [self.bar addSubview:self.modeControl];

    self.keyboardButton = [self barButton:@"Teclado" action:@selector(toggleKeyboard)];
    self.settingsButton = [self barButton:@"Ajustes" action:@selector(openSettings)];
    self.disconnectButton = [self barButton:@"Trocar Mac" action:@selector(disconnect)];

    self.trackpad = [[PDTrackpadView alloc] init];
    [self.view addSubview:self.trackpad];

    self.keyboard = [[PDKeyboardView alloc] init];
    self.keyboard.delegate = self;
    [self.view addSubview:self.keyboard];

    self.deck = [[PDDeckView alloc] init];
    self.deck.delegate = self;
    self.deck.hidden = YES;
    [self.view addSubview:self.deck];

    self.sink = [[PDTextSink alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.sink];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionChanged)
                                                 name:PDConnectionChangedNotification object:nil];
    [self connectionChanged];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)prefersStatusBarHidden { return YES; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyKeepAwake];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}

- (void)applyKeepAwake {
    BOOL keep = [[NSUserDefaults standardUserDefaults] boolForKey:PDPrefKeepAwake];
    [UIApplication sharedApplication].idleTimerDisabled = keep;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat barH = 52, pad = 10;
    self.bar.frame = CGRectMake(0, 0, b.size.width, barH);
    self.statusLabel.frame = CGRectMake(34, 0, 280, barH);
    self.modeControl.frame = CGRectMake((b.size.width - 320) / 2, 10, 320, 32);
    CGFloat x = b.size.width - 12;
    for (UIButton *btn in @[self.disconnectButton, self.settingsButton, self.keyboardButton]) {
        CGFloat w = [btn sizeThatFits:CGSizeMake(200, barH)].width + 16;
        x -= w;
        btn.frame = CGRectMake(x, 0, w, barH);
    }

    CGRect content = CGRectMake(pad, barH + pad, b.size.width - pad * 2, b.size.height - barH - pad * 2);
    self.deck.frame = content;

    BOOL showKb = [[NSUserDefaults standardUserDefaults] boolForKey:PDPrefShowKeyboard];
    CGFloat kbH = showKb ? floor(content.size.height * 0.52) : 0;
    self.keyboard.hidden = !showKb || !self.deck.hidden;
    self.keyboard.frame = CGRectMake(content.origin.x, CGRectGetMaxY(content) - kbH, content.size.width, kbH);
    self.trackpad.frame = CGRectMake(content.origin.x, content.origin.y, content.size.width,
                                     content.size.height - kbH - (showKb ? pad : 0));
}

#pragma mark - Actions

- (void)modeChanged {
    BOOL deck = self.modeControl.selectedSegmentIndex == 1;
    self.deck.hidden = !deck;
    self.trackpad.hidden = deck;
    self.keyboardButton.hidden = deck;
    [self.sink resignFirstResponder];
    [self.view setNeedsLayout];
}

- (void)toggleKeyboard {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:PDPrefShowKeyboard] forKey:PDPrefShowKeyboard];
    [UIView animateWithDuration:0.2 animations:^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }];
}

- (void)openSettings {
    PDSettingsViewController *s = [[PDSettingsViewController alloc] init];
    __weak PDMainViewController *weakSelf = self;
    s.onClose = ^{
        [weakSelf applyKeepAwake];
        [weakSelf.deck reload];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:s];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)leave {
    if (self.leaving) return;
    self.leaving = YES;
    [self.sink resignFirstResponder];
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)disconnect {
    [[PDConnection shared] disconnect];
    [self leave];
}

- (void)connectionChanged {
    PDConnection *c = [PDConnection shared];
    switch (c.state) {
        case PDStateConnected:
            self.dot.backgroundColor = PDColorOK();
            self.statusLabel.text = c.viaUSB ? [NSString stringWithFormat:@"%@ · cabo", c.macName] : c.macName;
            break;
        case PDStateConnecting:
            self.dot.backgroundColor = PDColorWarn();
            self.statusLabel.text = @"Reconectando…";
            break;
        default:
            self.dot.backgroundColor = PDColorOff();
            self.statusLabel.text = @"Desconectado";
            // PIN changed on the Mac or similar: go back to the connect screen.
            if (self.presentingViewController && !self.presentedViewController && self.view.window) {
                [self leave];
            }
            break;
    }
}

#pragma mark - Delegates

- (void)keyboardViewWantsSystemKeyboard:(PDKeyboardView *)view {
    if ([self.sink isFirstResponder]) [self.sink resignFirstResponder];
    else [self.sink becomeFirstResponder];
}

- (void)deckView:(PDDeckView *)view editSlotAtIndex:(NSUInteger)index {
    PDSlotEditor *e = [[PDSlotEditor alloc] initWithSlot:[[PDDeck shared] slotAtIndex:index]];
    __weak PDMainViewController *weakSelf = self;
    e.onDone = ^(NSDictionary *slot) {
        if (!slot) return;
        [[PDDeck shared] setSlot:slot atIndex:index];
        [weakSelf.deck reload];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:e];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

@end
