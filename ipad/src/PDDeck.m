#import "PDDeck.h"
#import <QuartzCore/QuartzCore.h>
#import "PDConnection.h"
#import "PDKeys.h"
#import "PDTheme.h"

#pragma mark - Model

static NSDictionary *Slot(NSString *title, PDActionType type, NSString *value, NSInteger color) {
    return @{ PDSlotTitle: title, PDSlotType: @(type), PDSlotValue: value, PDSlotColor: @(color) };
}

/// Lets page swipes start on top of buttons.
@interface PDPagingScroll : UIScrollView
@end

@implementation PDPagingScroll
- (BOOL)touchesShouldCancelInContentView:(UIView *)view { return YES; }
@end

@implementation PDDeck {
    NSMutableArray *_slots;
}

+ (instancetype)shared {
    static PDDeck *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [[PDDeck alloc] init]; });
    return d;
}

+ (NSString *)path {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"deck.plist"];
}

- (instancetype)init {
    if ((self = [super init])) {
        NSArray *saved = [NSArray arrayWithContentsOfFile:[PDDeck path]];
        if (saved.count == PDDeckPages * PDDeckSlotsPerPage) {
            _slots = [saved mutableCopy];
        } else {
            [self resetToDefaults];
        }
    }
    return self;
}

+ (NSArray *)defaults {
    // colors: 0 gray, 1 blue, 2 purple, 3 green, 4 orange, 5 red
    NSArray *page1 = @[
        Slot(@"Spotlight", PDActionShortcut, @"cmd+space", 1),
        Slot(@"Trocar app", PDActionShortcut, @"cmd+tab", 1),
        Slot(@"Mission Control", PDActionShortcut, @"ctrl+up", 2),
        Slot(@"Mesa ←", PDActionShortcut, @"ctrl+left", 2),
        Slot(@"Mesa →", PDActionShortcut, @"ctrl+right", 2),
        Slot(@"Copiar", PDActionShortcut, @"cmd+c", 0),
        Slot(@"Colar", PDActionShortcut, @"cmd+v", 0),
        Slot(@"Desfazer", PDActionShortcut, @"cmd+z", 0),
        Slot(@"Captura", PDActionShortcut, @"cmd+shift+4", 3),
        Slot(@"Fechar janela", PDActionShortcut, @"cmd+w", 5),
        Slot(@"Anterior", PDActionMedia, @"prev", 4),
        Slot(@"Play / Pausa", PDActionMedia, @"play", 4),
        Slot(@"Próxima", PDActionMedia, @"next", 4),
        Slot(@"Vol −", PDActionMedia, @"voldown", 4),
        Slot(@"Vol +", PDActionMedia, @"volup", 4),
    ];
    NSArray *page2 = @[
        Slot(@"Safari", PDActionOpen, @"Safari", 1),
        Slot(@"Finder", PDActionOpen, @"Finder", 1),
        Slot(@"Terminal", PDActionOpen, @"Terminal", 1),
        Slot(@"Música", PDActionOpen, @"Music", 1),
        Slot(@"Ajustes", PDActionOpen, @"System Settings", 1),
        Slot(@"Nova aba", PDActionShortcut, @"cmd+t", 0),
        Slot(@"Recarregar", PDActionShortcut, @"cmd+r", 0),
        Slot(@"Buscar", PDActionShortcut, @"cmd+f", 0),
        Slot(@"Salvar", PDActionShortcut, @"cmd+s", 0),
        Slot(@"Tela cheia", PDActionShortcut, @"ctrl+cmd+f", 2),
        Slot(@"Mudo", PDActionMedia, @"mute", 4),
        Slot(@"Mostrar mesa", PDActionShortcut, @"f11", 2),
        Slot(@"Esconder app", PDActionShortcut, @"cmd+h", 2),
        Slot(@"Sair do app", PDActionShortcut, @"cmd+q", 5),
        Slot(@"Bloquear tela", PDActionShortcut, @"ctrl+cmd+q", 5),
    ];
    NSMutableArray *all = [NSMutableArray arrayWithArray:page1];
    [all addObjectsFromArray:page2];
    while (all.count < PDDeckPages * PDDeckSlotsPerPage) [all addObject:@{}];
    return all;
}

- (void)resetToDefaults {
    _slots = [[PDDeck defaults] mutableCopy];
    [self save];
}

- (void)save {
    [_slots writeToFile:[PDDeck path] atomically:YES];
}

- (NSUInteger)count { return _slots.count; }

- (NSDictionary *)slotAtIndex:(NSUInteger)i {
    return i < _slots.count ? _slots[i] : @{};
}

- (void)setSlot:(NSDictionary *)slot atIndex:(NSUInteger)i {
    if (i >= _slots.count) return;
    _slots[i] = slot ?: @{};
    [self save];
}

+ (PDActionType)typeOf:(NSDictionary *)slot {
    NSNumber *t = slot[PDSlotType];
    return t ? (PDActionType)t.integerValue : PDActionNone;
}

+ (void)perform:(NSDictionary *)slot {
    PDConnection *c = [PDConnection shared];
    NSString *v = slot[PDSlotValue] ?: @"";
    switch ([self typeOf:slot]) {
        case PDActionShortcut: {
            int code; uint8_t mods;
            if ([PDKeys parseShortcut:v code:&code mods:&mods]) [c sendKey:code mods:mods action:2];
            break;
        }
        case PDActionText: [c sendText:v]; break;
        case PDActionOpen: [c sendOpen:v]; break;
        case PDActionMedia: {
            int m = [PDKeys mediaCodeForName:v];
            if (m >= 0) [c sendMedia:m];
            break;
        }
        default: break;
    }
}

+ (NSString *)subtitleFor:(NSDictionary *)slot {
    NSString *v = slot[PDSlotValue] ?: @"";
    switch ([self typeOf:slot]) {
        case PDActionShortcut: return [PDKeys prettyShortcut:v];
        case PDActionText: return [NSString stringWithFormat:@"“%@”", v];
        case PDActionOpen: return v;
        case PDActionMedia: {
            NSUInteger i = [[PDKeys mediaNames] indexOfObject:v];
            return i == NSNotFound ? v : [PDKeys mediaLabels][i];
        }
        default: return @"";
    }
}

@end

#pragma mark - Button

@interface PDDeckButton : UIControl
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *subtitle;
@property (nonatomic, strong) CAShapeLayer *dash;
@property (nonatomic, strong) UIColor *baseColor;
@end

@implementation PDDeckButton

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 16;
        _title = [[UILabel alloc] init];
        _title.textColor = [UIColor whiteColor];
        _title.font = PDFont(22, PDWeightSemibold);
        _title.textAlignment = NSTextAlignmentCenter;
        _title.adjustsFontSizeToFitWidth = YES;
        _title.minimumScaleFactor = 0.6;
        _title.userInteractionEnabled = NO;
        [self addSubview:_title];

        _subtitle = [[UILabel alloc] init];
        _subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.65];
        _subtitle.font = [UIFont systemFontOfSize:15];
        _subtitle.textAlignment = NSTextAlignmentCenter;
        _subtitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _subtitle.userInteractionEnabled = NO;
        [self addSubview:_subtitle];

        _dash = [CAShapeLayer layer];
        _dash.fillColor = [UIColor clearColor].CGColor;
        _dash.strokeColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
        _dash.lineWidth = 2;
        _dash.lineDashPattern = @[@8, @6];
        [self.layer addSublayer:_dash];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    _title.frame = CGRectMake(10, b.size.height / 2 - 30, b.size.width - 20, 34);
    _subtitle.frame = CGRectMake(10, b.size.height / 2 + 6, b.size.width - 20, 22);
    _dash.frame = b;
    _dash.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 1, 1) cornerRadius:16].CGPath;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? [self.baseColor colorWithAlphaComponent:0.6] : self.baseColor;
    self.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
}

- (void)showSlot:(NSDictionary *)slot {
    BOOL empty = [PDDeck typeOf:slot] == PDActionNone;
    _dash.hidden = !empty;
    if (empty) {
        self.baseColor = [UIColor clearColor];
        _title.text = @"+";
        _title.textColor = [UIColor colorWithWhite:1 alpha:0.25];
        _subtitle.text = @"";
    } else {
        NSArray *colors = PDDeckColors();
        NSUInteger ci = [slot[PDSlotColor] unsignedIntegerValue];
        self.baseColor = colors[ci < colors.count ? ci : 0];
        _title.text = slot[PDSlotTitle];
        _title.textColor = [UIColor whiteColor];
        _subtitle.text = [PDDeck subtitleFor:slot];
    }
    self.backgroundColor = self.baseColor;
}

@end

#pragma mark - Deck view

@interface PDDeckView () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIPageControl *pager;
@property (nonatomic, strong) NSArray *buttons;
@end

@implementation PDDeckView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _scroll = [[PDPagingScroll alloc] init];
        _scroll.pagingEnabled = YES;
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.delegate = self;
        _scroll.delaysContentTouches = NO;
        [self addSubview:_scroll];

        _pager = [[UIPageControl alloc] init];
        _pager.numberOfPages = PDDeckPages;
        _pager.userInteractionEnabled = NO;
        [self addSubview:_pager];

        NSMutableArray *buttons = [NSMutableArray array];
        for (NSUInteger i = 0; i < PDDeckPages * PDDeckSlotsPerPage; i++) {
            PDDeckButton *b = [[PDDeckButton alloc] init];
            b.tag = (NSInteger)i;
            [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
            UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                                                initWithTarget:self action:@selector(longPressed:)];
            lp.minimumPressDuration = 0.6;
            [b addGestureRecognizer:lp];
            [_scroll addSubview:b];
            [buttons addObject:b];
        }
        _buttons = buttons;
        [self reload];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat pagerH = 28;
    _scroll.frame = CGRectMake(0, 0, b.size.width, b.size.height - pagerH);
    _pager.frame = CGRectMake(0, b.size.height - pagerH, b.size.width, pagerH);
    CGFloat pw = _scroll.bounds.size.width, ph = _scroll.bounds.size.height;
    _scroll.contentSize = CGSizeMake(pw * PDDeckPages, ph);

    CGFloat gap = 14, margin = 12;
    CGFloat w = (pw - margin * 2 - gap * (PDDeckColumns - 1)) / PDDeckColumns;
    CGFloat h = (ph - margin * 2 - gap * (PDDeckRows - 1)) / PDDeckRows;
    for (PDDeckButton *btn in _buttons) {
        NSUInteger i = (NSUInteger)btn.tag;
        NSUInteger page = i / PDDeckSlotsPerPage, j = i % PDDeckSlotsPerPage;
        NSUInteger col = j % PDDeckColumns, row = j / PDDeckColumns;
        btn.transform = CGAffineTransformIdentity;
        btn.frame = CGRectMake(page * pw + margin + col * (w + gap), margin + row * (h + gap), w, h);
    }
    _scroll.contentOffset = CGPointMake(pw * _pager.currentPage, 0);
}

- (void)reload {
    PDDeck *deck = [PDDeck shared];
    for (PDDeckButton *b in _buttons) [b showSlot:[deck slotAtIndex:(NSUInteger)b.tag]];
}

- (void)scrollViewDidScroll:(UIScrollView *)sv {
    CGFloat w = sv.bounds.size.width;
    if (w > 0) _pager.currentPage = (NSInteger)lround(sv.contentOffset.x / w);
}

- (void)tapped:(PDDeckButton *)b {
    NSDictionary *slot = [[PDDeck shared] slotAtIndex:(NSUInteger)b.tag];
    if ([PDDeck typeOf:slot] == PDActionNone) {
        [self.delegate deckView:self editSlotAtIndex:(NSUInteger)b.tag];
    } else {
        [PDDeck perform:slot];
    }
}

- (void)longPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIControl *b = (UIControl *)g.view;
    [b cancelTrackingWithEvent:nil];
    b.highlighted = NO;
    [self.delegate deckView:self editSlotAtIndex:(NSUInteger)b.tag];
}

@end
