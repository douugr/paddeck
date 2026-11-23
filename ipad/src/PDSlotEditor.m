#import "PDSlotEditor.h"
#import "PDDeck.h"
#import "PDKeys.h"
#import "PDTheme.h"

@interface PDSlotEditor () <UITextFieldDelegate>
@property (nonatomic, strong) NSDictionary *slot;
@property (nonatomic, strong) UITextField *titleField;
@property (nonatomic, strong) UISegmentedControl *typeControl;
@property (nonatomic, strong) UITextField *valueField;
@property (nonatomic, strong) UISegmentedControl *mediaControl;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) NSArray *colorButtons;
@property (nonatomic) NSInteger colorIndex;
@end

@implementation PDSlotEditor

- (instancetype)initWithSlot:(NSDictionary *)slot {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _slot = slot ?: @{};
        _colorIndex = [_slot[PDSlotColor] integerValue];
    }
    return self;
}

- (UILabel *)caption:(NSString *)text y:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(24, y, 400, 20)];
    l.text = text;
    l.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    l.font = PDFont(13, PDWeightMedium);
    [self.view addSubview:l];
    return l;
}

- (UITextField *)field:(CGFloat)y placeholder:(NSString *)ph {
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(24, y, 492, 44)];
    f.backgroundColor = PDColorSurface();
    f.textColor = [UIColor whiteColor];
    f.layer.cornerRadius = 8;
    f.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 44)];
    f.leftViewMode = UITextFieldViewModeAlways;
    f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:ph attributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.3] }];
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.keyboardAppearance = UIKeyboardAppearanceDark;
    f.delegate = self;
    [self.view addSubview:f];
    return f;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PDColorBar();
    self.title = [PDDeck typeOf:self.slot] == PDActionNone ? @"Novo botão" : @"Editar botão";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancelar"
        style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Salvar"
        style:UIBarButtonItemStyleDone target:self action:@selector(save)];

    CGFloat y = 84;
    [self caption:@"NOME" y:y];
    self.titleField = [self field:y + 24 placeholder:@"Ex.: Captura de tela"];
    self.titleField.text = self.slot[PDSlotTitle];
    y += 88;

    [self caption:@"AÇÃO" y:y];
    self.typeControl = [[UISegmentedControl alloc] initWithItems:@[@"Atalho", @"Texto", @"Abrir app", @"Mídia"]];
    self.typeControl.frame = CGRectMake(24, y + 24, 492, 36);
    self.typeControl.tintColor = PDColorAccent();
    NSInteger t = [self.slot[PDSlotType] integerValue];
    self.typeControl.selectedSegmentIndex = (self.slot[PDSlotType] && t >= 0) ? t : 0;
    [self.typeControl addTarget:self action:@selector(typeChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.typeControl];
    y += 80;

    [self caption:@"VALOR" y:y];
    self.valueField = [self field:y + 24 placeholder:@""];
    self.valueField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.valueField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.valueField addTarget:self action:@selector(validate) forControlEvents:UIControlEventEditingChanged];

    self.mediaControl = [[UISegmentedControl alloc] initWithItems:[PDKeys mediaLabels]];
    self.mediaControl.frame = CGRectMake(24, y + 28, 492, 36);
    self.mediaControl.tintColor = PDColorAccent();
    [self.mediaControl setTitleTextAttributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:12] }
                                     forState:UIControlStateNormal];
    [self.view addSubview:self.mediaControl];

    NSString *value = self.slot[PDSlotValue] ?: @"";
    if (self.typeControl.selectedSegmentIndex == PDActionMedia) {
        NSUInteger i = [[PDKeys mediaNames] indexOfObject:value];
        self.mediaControl.selectedSegmentIndex = i == NSNotFound ? 0 : (NSInteger)i;
    } else {
        self.valueField.text = value;
        self.mediaControl.selectedSegmentIndex = 0;
    }

    self.hint = [[UILabel alloc] initWithFrame:CGRectMake(24, y + 72, 492, 40)];
    self.hint.numberOfLines = 2;
    self.hint.font = [UIFont systemFontOfSize:13];
    [self.view addSubview:self.hint];
    y += 124;

    [self caption:@"COR" y:y];
    NSMutableArray *cbs = [NSMutableArray array];
    NSArray *colors = PDDeckColors();
    for (NSUInteger i = 0; i < colors.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(24 + i * 84, y + 26, 72, 44);
        b.backgroundColor = colors[i];
        b.layer.cornerRadius = 10;
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(colorTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:b];
        [cbs addObject:b];
    }
    self.colorButtons = cbs;
    y += 100;

    UIButton *test = [UIButton buttonWithType:UIButtonTypeSystem];
    test.frame = CGRectMake(24, y, 236, 48);
    [test setTitle:@"Testar no Mac" forState:UIControlStateNormal];
    test.backgroundColor = PDColorSurface();
    test.layer.cornerRadius = 10;
    test.tintColor = PDColorAccent();
    [test addTarget:self action:@selector(test) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:test];

    UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
    del.frame = CGRectMake(280, y, 236, 48);
    [del setTitle:@"Apagar botão" forState:UIControlStateNormal];
    del.backgroundColor = PDColorSurface();
    del.layer.cornerRadius = 10;
    del.tintColor = PDColorOff();
    [del addTarget:self action:@selector(remove) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:del];

    [self refreshColors];
    [self typeChanged];
}

- (void)typeChanged {
    PDActionType t = (PDActionType)self.typeControl.selectedSegmentIndex;
    BOOL media = t == PDActionMedia;
    self.valueField.hidden = media;
    self.mediaControl.hidden = !media;
    NSArray *ph = @[@"cmd+shift+4", @"Texto que será digitado", @"Safari, com.apple.Music ou https://…", @""];
    self.valueField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:ph[t] attributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.3] }];
    [self validate];
}

- (BOOL)validate {
    PDActionType t = (PDActionType)self.typeControl.selectedSegmentIndex;
    NSString *v = self.valueField.text ?: @"";
    UIColor *ok = [UIColor colorWithWhite:1 alpha:0.45];
    switch (t) {
        case PDActionShortcut: {
            if (v.length == 0) {
                self.hint.text = @"Modificadores: cmd, shift, ctrl, opt, fn. Teclas: letras, números, "
                                  "space, tab, return, esc, delete, up/down/left/right, f1–f12.";
                self.hint.textColor = ok;
                return NO;
            }
            int code; uint8_t mods;
            if ([PDKeys parseShortcut:v code:&code mods:&mods]) {
                self.hint.text = [NSString stringWithFormat:@"Envia %@", [PDKeys prettyShortcut:v]];
                self.hint.textColor = PDColorOK();
                return YES;
            }
            self.hint.text = @"Atalho não reconhecido. Ex.: cmd+shift+4, ctrl+up, f11";
            self.hint.textColor = PDColorOff();
            return NO;
        }
        case PDActionText:
            self.hint.text = @"Digitado no Mac como texto (acentos funcionam). Use o teclado do iOS para quebras de linha.";
            self.hint.textColor = ok;
            return v.length > 0;
        case PDActionOpen:
            self.hint.text = @"Nome do app (como aparece em Aplicativos), bundle id, caminho ou endereço web.";
            self.hint.textColor = ok;
            return v.length > 0;
        default:
            self.hint.text = @"Teclas de mídia do Mac.";
            self.hint.textColor = ok;
            return YES;
    }
}

- (void)colorTapped:(UIButton *)b {
    self.colorIndex = b.tag;
    [self refreshColors];
}

- (void)refreshColors {
    for (UIButton *b in self.colorButtons) {
        BOOL sel = b.tag == self.colorIndex;
        b.layer.borderWidth = sel ? 3 : 0;
        b.layer.borderColor = [UIColor whiteColor].CGColor;
    }
}

- (NSDictionary *)currentSlot {
    PDActionType t = (PDActionType)self.typeControl.selectedSegmentIndex;
    NSString *value = t == PDActionMedia
        ? [PDKeys mediaNames][(NSUInteger)MAX(0, self.mediaControl.selectedSegmentIndex)]
        : (self.valueField.text ?: @"");
    NSString *title = [self.titleField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!title.length) {
        title = t == PDActionShortcut ? [PDKeys prettyShortcut:value]
              : t == PDActionMedia ? [PDKeys mediaLabels][(NSUInteger)MAX(0, self.mediaControl.selectedSegmentIndex)]
              : value;
    }
    return @{ PDSlotTitle: title, PDSlotType: @(t), PDSlotValue: value, PDSlotColor: @(self.colorIndex) };
}

- (void)test {
    if ([self validate]) [PDDeck perform:[self currentSlot]];
}

- (void)save {
    if (![self validate]) {
        [self.valueField becomeFirstResponder];
        return;
    }
    [self finish:[self currentSlot]];
}

- (void)cancel { [self finish:nil]; }
- (void)remove { [self finish:@{}]; }

- (void)finish:(NSDictionary *)slot {
    [self.view endEditing:YES];
    void (^done)(NSDictionary *) = self.onDone;
    [self dismissViewControllerAnimated:YES completion:^{ if (done) done(slot); }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    if (tf == self.titleField && !self.valueField.hidden) [self.valueField becomeFirstResponder];
    else [tf resignFirstResponder];
    return NO;
}

@end
