#import "PDKeyboardView.h"
#import "PDConnection.h"
#import "PDKeys.h"
#import "PDTheme.h"
#import "PDSettings.h"
#import <AudioToolbox/AudioToolbox.h>

// Key spec keys
#define K_LABEL  @"l"   // label
#define K_SLABEL @"sl"  // shifted label (small, top-left)
#define K_CHAR   @"c"   // text sent
#define K_SCHAR  @"sc"  // text sent with shift
#define K_CODE   @"k"   // virtual key code (or media key for type "media")
#define K_WIDTH  @"w"   // width in units (11 per row)
#define K_TYPE   @"t"   // char | key | mod | sys | layer | media
#define K_MOD    @"m"   // modifier bit
#define K_TARGET @"to"  // layer name for type "layer"

static const CGFloat kGap = 7;
static const CGFloat kUnitsPerRow = 11;

#pragma mark - Key view

@class PDKeyView;

@protocol PDKeyViewDelegate <NSObject>
- (void)keyDown:(PDKeyView *)key;
- (void)keyMoved:(PDKeyView *)key touch:(UITouch *)touch;
- (void)keyUp:(PDKeyView *)key;
@end

@interface PDKeyView : UIView
@property (nonatomic, strong) NSDictionary *spec;
@property (nonatomic, weak) id<PDKeyViewDelegate> delegate;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UILabel *shiftLabel;
@property (nonatomic) BOOL pressed;
@property (nonatomic) int modState;   // 0 off, 1 next key, 2 locked
@property (nonatomic, strong) UIView *lockBar;
- (BOOL)isCharKey;
@end

@implementation PDKeyView

- (instancetype)initWithSpec:(NSDictionary *)spec {
    if ((self = [super initWithFrame:CGRectZero])) {
        _spec = spec;
        self.layer.cornerRadius = 9;

        _label = [[UILabel alloc] init];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.textColor = PDColorKeyText(1);
        _label.adjustsFontSizeToFitWidth = YES;
        _label.minimumScaleFactor = 0.5;
        _label.text = spec[K_LABEL];
        [self addSubview:_label];

        if (spec[K_SLABEL]) {
            _shiftLabel = [[UILabel alloc] init];
            _shiftLabel.text = spec[K_SLABEL];
            _shiftLabel.textColor = PDColorKeyText(0.45);
            _shiftLabel.font = [UIFont systemFontOfSize:15];
            [self addSubview:_shiftLabel];
        }

        _lockBar = [[UIView alloc] init];
        _lockBar.backgroundColor = PDColorOK();
        _lockBar.layer.cornerRadius = 1.5;
        _lockBar.hidden = YES;
        [self addSubview:_lockBar];

        [self refresh];
    }
    return self;
}

- (BOOL)isCharKey { return [self.spec[K_TYPE] isEqualToString:@"char"]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    if (_shiftLabel) {
        _shiftLabel.frame = CGRectMake(9, 5, b.size.width - 12, 18);
        _label.frame = CGRectMake(4, b.size.height * 0.28, b.size.width - 8, b.size.height * 0.62);
    } else {
        _label.frame = CGRectInset(b, 6, 4);
    }
    _lockBar.frame = CGRectMake(b.size.width / 2 - 12, b.size.height - 9, 24, 3);
}

- (void)refresh {
    BOOL special = ![self isCharKey] || [self.spec[K_CHAR] isEqualToString:@" "];
    UIColor *bg = special ? PDColorKeyDark() : PDColorKey();
    if (self.modState > 0) bg = PDColorAccent();
    if (self.pressed) bg = PDColorKeyActive();
    self.backgroundColor = bg;
    // Modifier keys turn the accent color: white text reads on it in every profile.
    self.label.textColor = self.modState > 0 && !self.pressed ? [UIColor whiteColor] : PDColorKeyText(1);
    self.lockBar.hidden = self.modState != 2;
    NSString *label = self.label.text ?: @"";
    if (!special && label.length <= 2) self.label.font = [UIFont systemFontOfSize:28];
    else if (label.length <= 2) self.label.font = [UIFont systemFontOfSize:24];
    else self.label.font = [UIFont systemFontOfSize:label.length > 5 ? 16 : 19];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    self.pressed = YES;
    [self refresh];
    [self.delegate keyDown:self];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.delegate keyMoved:self touch:[touches anyObject]];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    self.pressed = NO;
    [self refresh];
    [self.delegate keyUp:self];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

@end

#pragma mark - Layout specs

static NSDictionary *charKey(NSString *c, NSString *shifted) {
    NSMutableDictionary *d = [@{ K_TYPE: @"char", K_CHAR: c, K_SCHAR: shifted,
                                 K_CODE: @([PDKeys codeForCharacter:c]), K_WIDTH: @1 } mutableCopy];
    BOOL letter = [[c uppercaseString] isEqualToString:shifted];
    d[K_LABEL] = letter ? shifted : c;
    if (!letter) d[K_SLABEL] = shifted;
    return d;
}

static NSDictionary *symKey(NSString *c) { return charKey(c, c); }

static NSDictionary *specialKey(NSString *label, int code, CGFloat w) {
    return @{ K_TYPE: @"key", K_LABEL: label, K_CODE: @(code), K_WIDTH: @(w) };
}

static NSDictionary *modKey(NSString *label, uint8_t bit, CGFloat w) {
    return @{ K_TYPE: @"mod", K_LABEL: label, K_MOD: @(bit), K_WIDTH: @(w) };
}

static NSDictionary *layerKey(NSString *label, NSString *target, CGFloat w) {
    return @{ K_TYPE: @"layer", K_LABEL: label, K_TARGET: target, K_WIDTH: @(w) };
}

static NSDictionary *mediaKey(NSString *label, int media, CGFloat w) {
    return @{ K_TYPE: @"media", K_LABEL: label, K_CODE: @(media), K_WIDTH: @(w) };
}

static NSDictionary *spaceKey(CGFloat w) {
    NSMutableDictionary *s = [charKey(@" ", @" ") mutableCopy];
    s[K_LABEL] = @"";
    s[K_WIDTH] = @(w);
    return s;
}

static NSDictionary *widen(NSDictionary *spec, CGFloat w) {
    NSMutableDictionary *d = [spec mutableCopy];
    d[K_WIDTH] = @(w);
    return d;
}

static NSArray *charRow(NSString *chars, NSString *shifted) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSUInteger i = 0; i < chars.length; i++) {
        [a addObject:charKey([chars substringWithRange:NSMakeRange(i, 1)],
                             [shifted substringWithRange:NSMakeRange(i, 1)])];
    }
    return a;
}

static NSArray *symRow(NSArray *symbols) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *s in symbols) [a addObject:symKey(s)];
    return a;
}

/// Shared bottom row, space centered: 123 ⌃ ⌥ | space | ⌘ fn áç  (3.25 + 4.5 + 3.25 = 11 units)
static NSArray *bottomRow(NSString *switchLabel, NSString *switchTarget) {
    return @[ layerKey(switchLabel, switchTarget, 1.25),
              modKey(@"⌃", PDModCtrl, 1),
              modKey(@"⌥", PDModOpt, 1),
              spaceKey(4.5),
              modKey(@"⌘", PDModCmd, 1.25),
              layerKey(@"fn", @"fn", 1),
              @{ K_TYPE: @"sys", K_LABEL: @"áç", K_WIDTH: @1 } ];
}

/// Characters offered when a key is held (most common in Portuguese first).
static NSDictionary *Variants(void) {
    static NSDictionary *v;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        v = @{
            @"a": @[@"á", @"ã", @"â", @"à", @"ä", @"å", @"æ", @"ª"],
            @"e": @[@"é", @"ê", @"è", @"ë", @"€"],
            @"i": @[@"í", @"î", @"ì", @"ï"],
            @"o": @[@"ó", @"õ", @"ô", @"ò", @"ö", @"ø", @"œ", @"º"],
            @"u": @[@"ú", @"ü", @"û", @"ù"],
            @"c": @[@"ç", @"ć", @"č"],
            @"n": @[@"ñ", @"ń"],
            @"s": @[@"ß", @"š", @"§"],
            @"y": @[@"ý", @"ÿ"],
            @"z": @[@"ž"],
            @"-": @[@"–", @"—", @"•"],
            @"'": @[@"‘", @"’"],
            @"\"": @[@"“", @"”", @"«", @"»"],
            @"$": @[@"€", @"£", @"¥", @"¢"],
            @"?": @[@"¿"],
            @"!": @[@"¡"],
            @".": @[@"…"],
            @"0": @[@"°"],
            @"/": @[@"\\"],
        };
    });
    return v;
}

static NSArray *rowWith(NSArray *first, NSArray *middle, NSArray *last) {
    NSMutableArray *a = [NSMutableArray array];
    if (first) [a addObjectsFromArray:first];
    [a addObjectsFromArray:middle];
    if (last) [a addObjectsFromArray:last];
    return a;
}

/// Every row adds up to 11 units.
static NSDictionary *Layers(void) {
    NSDictionary *del = specialKey(@"⌫", PDKeyDelete, 1);
    NSDictionary *ret = specialKey(@"return", PDKeyReturn, 2);

    NSArray *abc = @[
        rowWith(nil, charRow(@"qwertyuiop", @"QWERTYUIOP"), @[del]),
        rowWith(nil, charRow(@"asdfghjkl", @"ASDFGHJKL"), @[ret]),
        rowWith(@[modKey(@"⇧", PDModShift, 1)], charRow(@"zxcvbnm,.", @"ZXCVBNM<>"), @[modKey(@"⇧", PDModShift, 1)]),
        bottomRow(@"123", @"123"),
    ];

    NSArray *num = @[
        rowWith(nil, symRow(@[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"0"]), @[del]),
        rowWith(nil, symRow(@[@"-", @"/", @":", @";", @"(", @")", @"$", @"&", @"@"]), @[ret]),
        rowWith(@[layerKey(@"#+=", @"sym", 1.5)], symRow(@[@".", @",", @"?", @"!", @"'", @"\"", @"_", @"="]),
                @[layerKey(@"#+=", @"sym", 1.5)]),
        bottomRow(@"ABC", @"abc"),
    ];

    NSArray *sym = @[
        rowWith(nil, symRow(@[@"[", @"]", @"{", @"}", @"#", @"%", @"^", @"*", @"+", @"="]), @[del]),
        rowWith(nil, symRow(@[@"_", @"\\", @"|", @"~", @"<", @">", @"€", @"£", @"•"]), @[ret]),
        rowWith(@[layerKey(@"123", @"123", 1.5)], symRow(@[@".", @",", @"?", @"!", @"'", @"\"", @"`", @"°"]),
                @[layerKey(@"123", @"123", 1.5)]),
        bottomRow(@"ABC", @"abc"),
    ];

    int f1[6] = { 122, 120, 99, 118, 96, 97 }, f7[6] = { 98, 100, 101, 109, 103, 111 };
    NSMutableArray *r1 = [NSMutableArray arrayWithObject:specialKey(@"esc", PDKeyEscape, 1)];
    for (int i = 0; i < 6; i++) [r1 addObject:specialKey([NSString stringWithFormat:@"F%d", i + 1], f1[i], 1)];
    [r1 addObjectsFromArray:@[specialKey(@"PgUp", PDKeyPageUp, 1), specialKey(@"Home", PDKeyHome, 1), widen(del, 2)]];
    NSMutableArray *r2 = [NSMutableArray arrayWithObject:specialKey(@"tab", PDKeyTab, 1)];
    for (int i = 0; i < 6; i++) [r2 addObject:specialKey([NSString stringWithFormat:@"F%d", i + 7], f7[i], 1)];
    [r2 addObjectsFromArray:@[specialKey(@"PgDn", PDKeyPageDown, 1), specialKey(@"End", PDKeyEnd, 1), ret]];
    NSArray *fn = @[
        r1,
        r2,
        @[ mediaKey(@"🔅", PDMediaBrightDown, 1.25), mediaKey(@"🔆", PDMediaBrightUp, 1.25),
           mediaKey(@"◀◀", PDMediaPrev, 1.25), mediaKey(@"▶❚❚", PDMediaPlay, 1.25),
           mediaKey(@"▶▶", PDMediaNext, 1.25), mediaKey(@"🔇", PDMediaMute, 1.25),
           mediaKey(@"🔉", PDMediaVolDown, 1.25), mediaKey(@"🔊", PDMediaVolUp, 1.25),
           specialKey(@"⌦", PDKeyForwardDelete, 1) ],
        @[ layerKey(@"ABC", @"abc", 1.25), modKey(@"⇧", PDModShift, 1.25),
           modKey(@"⌃", PDModCtrl, 1), modKey(@"⌥", PDModOpt, 1), modKey(@"⌘", PDModCmd, 1.5),
           specialKey(@"←", PDKeyLeft, 1.25), specialKey(@"↑", PDKeyUp, 1.25),
           specialKey(@"↓", PDKeyDown, 1.25), specialKey(@"→", PDKeyRight, 1.25) ],
    ];

    return @{ @"abc": abc, @"123": num, @"sym": sym, @"fn": fn };
}

#pragma mark - Keyboard

@interface PDKeyboardView () <PDKeyViewDelegate>
@end

@implementation PDKeyboardView {
    NSDictionary *_layers;     // name -> rows (arrays of PDKeyView)
    NSString *_current;
    uint8_t _onceMods;
    uint8_t _lockedMods;
    NSTimer *_repeatTimer;
    PDKeyView *_repeatKey;
    UILabel *_preview;          // bubble with the pressed character
    PDKeyView *_previewKey;

    PDKeyView *_charKey;       // char key waiting for release (typed on touch up)
    PDKeyView *_charOwner;     // the key view that owns that touch (differs after sliding)
    NSTimer *_holdTimer;
    UIView *_variantView;       // long-press popup
    NSArray *_variantLabels;
    NSArray *_variants;
    NSInteger _variantIndex;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        self.clipsToBounds = NO;
        NSMutableDictionary *layers = [NSMutableDictionary dictionary];
        NSDictionary *specs = Layers();
        for (NSString *name in specs) {
            NSMutableArray *rows = [NSMutableArray array];
            for (NSArray *rowSpecs in specs[name]) {
                NSMutableArray *row = [NSMutableArray array];
                for (NSDictionary *s in rowSpecs) {
                    PDKeyView *k = [[PDKeyView alloc] initWithSpec:s];
                    k.delegate = self;
                    [self addSubview:k];
                    [row addObject:k];
                }
                [rows addObject:row];
            }
            layers[name] = rows;
        }
        _layers = layers;

        _preview = [[UILabel alloc] init];
        _preview.backgroundColor = PDColorKeyActive();
        _preview.textColor = PDColorKeyText(1);
        _preview.textAlignment = NSTextAlignmentCenter;
        _preview.font = [UIFont systemFontOfSize:40];
        _preview.layer.cornerRadius = 12;
        _preview.layer.masksToBounds = YES;
        _preview.hidden = YES;
        _preview.userInteractionEnabled = NO;
        [self addSubview:_preview];

        [self showLayer:@"abc"];
    }
    return self;
}

- (void)showLayer:(NSString *)name {
    _current = name;
    for (NSString *n in _layers) {
        BOOL visible = [n isEqualToString:name];
        for (NSArray *row in _layers[n]) for (PDKeyView *k in row) k.hidden = !visible;
    }
    [self refreshKeys];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    for (NSString *name in _layers) {
        NSArray *rows = _layers[name];
        CGFloat rowH = (H - kGap * (rows.count - 1)) / rows.count;
        CGFloat y = 0;
        for (NSArray *row in rows) {
            CGFloat unit = (W - kGap * (row.count - 1)) / kUnitsPerRow;
            CGFloat x = 0;
            for (PDKeyView *k in row) {
                CGFloat w = unit * [k.spec[K_WIDTH] floatValue];
                k.frame = CGRectMake(x, y, w, rowH);
                x += w + kGap;
            }
            y += rowH + kGap;
        }
    }
}

/// Touches in the gaps go to the nearest key, so no tap is lost.
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)event {
    if (self.hidden || !CGRectContainsPoint(self.bounds, p)) return nil;
    PDKeyView *best = nil;
    CGFloat bestDist = CGFLOAT_MAX;
    for (NSArray *row in _layers[_current]) {
        for (PDKeyView *k in row) {
            CGRect f = k.frame;
            if (CGRectContainsPoint(f, p)) return k;
            CGFloat dx = MAX(0, MAX(CGRectGetMinX(f) - p.x, p.x - CGRectGetMaxX(f)));
            CGFloat dy = MAX(0, MAX(CGRectGetMinY(f) - p.y, p.y - CGRectGetMaxY(f)));
            CGFloat d = dx * dx + dy * dy;
            if (d < bestDist) { bestDist = d; best = k; }
        }
    }
    return best;
}

#pragma mark - State

- (uint8_t)mods { return _onceMods | _lockedMods; }

- (void)refreshKeys {
    uint8_t mods = [self mods];
    for (NSArray *row in _layers[_current]) {
        for (PDKeyView *k in row) {
            NSString *type = k.spec[K_TYPE];
            if ([type isEqualToString:@"mod"]) {
                uint8_t bit = [k.spec[K_MOD] unsignedCharValue];
                k.modState = (_lockedMods & bit) ? 2 : (_onceMods & bit) ? 1 : 0;
            } else if ([type isEqualToString:@"char"]) {
                NSString *c = k.spec[K_CHAR], *s = k.spec[K_SCHAR];
                BOOL letter = [[c uppercaseString] isEqualToString:s] && ![c isEqualToString:s];
                k.label.text = letter ? ((mods & PDModShift) ? s : c) : k.spec[K_LABEL];
            }
            [k refresh];
        }
    }
}

- (void)consumeOnceMods {
    if (_onceMods) {
        _onceMods = 0;
        [self refreshKeys];
    }
}

#pragma mark - Key events

#pragma mark - Feedback (the iPad has no vibration motor: sound + bubble)

- (void)click {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:PDPrefKeyClick]) {
        AudioServicesPlaySystemSound(1104);   // the iOS keyboard click
    }
}

/// Above the key, or below it when the keyboard sits at the top of the screen.
- (CGFloat)popupYForKey:(CGRect)f height:(CGFloat)h {
    CGFloat above = CGRectGetMinY(f) - h - 6;
    CGFloat topInWindow = [self convertPoint:CGPointMake(0, above) toView:nil].y;
    return topInWindow >= 0 ? above : CGRectGetMaxY(f) + 6;
}

- (void)showPreview:(PDKeyView *)key {
    NSString *text = key.label.text;
    if (![key isCharKey] || [key.spec[K_CHAR] isEqualToString:@" "] || !text.length) return;
    CGRect f = key.frame;
    CGFloat w = f.size.width * 1.15, h = f.size.height * 0.95;
    _preview.text = text;
    _preview.frame = CGRectMake(CGRectGetMidX(f) - w / 2, [self popupYForKey:f height:h], w, h);
    _preview.hidden = NO;
    [self bringSubviewToFront:_preview];
    _previewKey = key;
}

- (void)hidePreview:(PDKeyView *)key {
    if (key == _previewKey) {
        _preview.hidden = YES;
        _previewKey = nil;
    }
}

- (void)keyDown:(PDKeyView *)key {
    [self click];
    [self showPreview:key];
    NSDictionary *s = key.spec;
    NSString *type = s[K_TYPE];
    PDConnection *c = [PDConnection shared];

    if ([type isEqualToString:@"mod"]) {
        uint8_t bit = [s[K_MOD] unsignedCharValue];
        if (_lockedMods & bit) { _lockedMods &= ~bit; }
        else if (_onceMods & bit) { _onceMods &= ~bit; _lockedMods |= bit; }
        else { _onceMods |= bit; }
        [self refreshKeys];
        return;
    }
    // A letter still under another finger is typed first (fast typing overlaps touches).
    [self commitPending];
    uint8_t mods = [self mods];

    if ([type isEqualToString:@"layer"]) {
        [self stopRepeat];
        [self showLayer:s[K_TARGET]];
        return;
    }
    if ([type isEqualToString:@"sys"]) {
        [self.delegate keyboardViewWantsSystemKeyboard:self];
        return;
    }
    if ([type isEqualToString:@"media"]) {
        [c sendMedia:[s[K_CODE] intValue]];
        return;
    }

    if ([type isEqualToString:@"char"]) {
        int code = [s[K_CODE] intValue];
        BOOL space = [s[K_CHAR] isEqualToString:@" "];
        if ((mods & (PDModCmd | PDModCtrl | PDModOpt | PDModFn)) && code >= 0) {
            [c sendKey:code mods:mods action:2];     // shortcuts fire right away
            [self consumeOnceMods];
        } else if (space) {
            [c sendText:@" "];
            [self consumeOnceMods];
            [self startRepeat:key];
        } else {
            // Letters/symbols are typed on release, so a hold can offer variants
            // and a wrong touch can slide to the right key first.
            _charKey = key;
            _charOwner = key;
            [self armHoldTimer];
        }
        return;
    }

    // special key
    int code = [s[K_CODE] intValue];
    [c sendKey:code mods:mods action:2];
    [self consumeOnceMods];
    if (code == PDKeyDelete || code == PDKeyForwardDelete ||
        (code >= PDKeyLeft && code <= PDKeyUp)) {
        [self startRepeat:key];
    }
}

- (void)armHoldTimer {
    [_holdTimer invalidate];
    _holdTimer = nil;
    if ([Variants() objectForKey:_charKey.spec[K_CHAR]]) {
        _holdTimer = [NSTimer scheduledTimerWithTimeInterval:0.42 target:self selector:@selector(holdFired)
                                                    userInfo:nil repeats:NO];
    }
}

- (PDKeyView *)keyAtPoint:(CGPoint)p {
    for (NSArray *row in _layers[_current]) {
        for (PDKeyView *k in row) {
            if (CGRectContainsPoint(CGRectInset(k.frame, -kGap / 2, -kGap / 2), p)) return k;
        }
    }
    return nil;
}

- (void)keyUp:(PDKeyView *)key {
    [self hidePreview:key];
    if (key == _repeatKey) [self stopRepeat];
    if (key != _charOwner || !_charKey) return;
    key = _charKey;
    [self hidePreview:key];

    BOOL shift = ([self mods] & PDModShift) != 0;
    NSString *text;
    if (_variantView) {
        text = _variantIndex >= 0 ? _variants[(NSUInteger)_variantIndex] : nil;
        if (text && shift) text = [text uppercaseString];
    } else {
        text = shift ? key.spec[K_SCHAR] : key.spec[K_CHAR];
    }
    if (text) {
        [[PDConnection shared] sendText:text];
        [self consumeOnceMods];
    }
    [self cancelHold];
}

/// Types the pending letter now (another key was pressed before it was released).
- (void)commitPending {
    if (!_charKey) return;
    if (!_variantView) {
        BOOL shift = ([self mods] & PDModShift) != 0;
        [[PDConnection shared] sendText:shift ? _charKey.spec[K_SCHAR] : _charKey.spec[K_CHAR]];
        [self consumeOnceMods];
    }
    [self cancelHold];
}

- (void)keyMoved:(PDKeyView *)key touch:(UITouch *)touch {
    if (key != _charOwner || !_charKey) return;
    if (!_variantView) {
        // Slide to the neighbouring letter before releasing.
        PDKeyView *k = [self keyAtPoint:[touch locationInView:self]];
        if (k && k != _charKey && [k isCharKey] && ![k.spec[K_CHAR] isEqualToString:@" "]) {
            [self hidePreview:_charKey];
            _charKey.pressed = NO;
            [_charKey refresh];
            _charKey = k;
            k.pressed = YES;
            [k refresh];
            [self showPreview:k];
            [self armHoldTimer];
        }
        return;
    }
    CGPoint p = [touch locationInView:_variantView];
    CGFloat cell = _variantView.bounds.size.width / _variants.count;
    NSInteger i = (NSInteger)floor(p.x / cell);
    if (p.y > _variantView.bounds.size.height + 120) i = -1;   // dragged far below: cancel
    i = MAX(-1, MIN((NSInteger)_variants.count - 1, i));
    if (p.x < -cell * 0.5) i = -1;
    [self highlightVariant:i];
}

- (void)holdFired {
    _holdTimer = nil;
    PDKeyView *key = _charKey;
    NSArray *variants = Variants()[key.spec[K_CHAR]];
    if (!key || !variants.count) return;
    [self hidePreview:key];
    BOOL shift = ([self mods] & PDModShift) != 0;

    CGRect f = key.frame;
    CGFloat cellW = MAX(64, f.size.width * 0.9), h = f.size.height;
    CGFloat w = cellW * variants.count;
    CGFloat x = MIN(MAX(0, CGRectGetMinX(f)), self.bounds.size.width - w);
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(x, [self popupYForKey:f height:h], w, h)];
    box.backgroundColor = PDColorKeyDark();
    box.layer.cornerRadius = 12;
    box.layer.borderWidth = 1;
    box.layer.borderColor = PDColorKeyText(0.15).CGColor;
    box.userInteractionEnabled = NO;
    NSMutableArray *labels = [NSMutableArray array];
    for (NSUInteger i = 0; i < variants.count; i++) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(i * cellW + 3, 3, cellW - 6, h - 6)];
        l.text = shift ? [variants[i] uppercaseString] : variants[i];
        l.textColor = PDColorKeyText(1);
        l.font = [UIFont systemFontOfSize:32];
        l.textAlignment = NSTextAlignmentCenter;
        l.layer.cornerRadius = 9;
        l.layer.masksToBounds = YES;
        [box addSubview:l];
        [labels addObject:l];
    }
    [self addSubview:box];
    _variantView = box;
    _variantLabels = labels;
    _variants = variants;
    [self highlightVariant:0];
    [self click];
}

- (void)highlightVariant:(NSInteger)i {
    _variantIndex = i;
    for (NSUInteger j = 0; j < _variantLabels.count; j++) {
        UILabel *l = _variantLabels[j];
        l.backgroundColor = (NSInteger)j == i ? PDColorAccent() : [UIColor clearColor];
        l.textColor = (NSInteger)j == i ? [UIColor whiteColor] : PDColorKeyText(1);
    }
}

- (void)cancelHold {
    [_holdTimer invalidate];
    _holdTimer = nil;
    if (_charKey && _charKey != _charOwner) {   // slid onto it: clear its highlight
        _charKey.pressed = NO;
        [_charKey refresh];
        [self hidePreview:_charKey];
    }
    [_variantView removeFromSuperview];
    _variantView = nil;
    _variantLabels = nil;
    _variants = nil;
    _variantIndex = -1;
    _charKey = nil;
    _charOwner = nil;
}

- (void)startRepeat:(PDKeyView *)key {
    [self stopRepeat];
    _repeatKey = key;
    _repeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.45 target:self selector:@selector(repeatStart)
                                                  userInfo:nil repeats:NO];
}

- (void)repeatStart {
    _repeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.06 target:self selector:@selector(repeatTick)
                                                  userInfo:nil repeats:YES];
}

- (void)repeatTick {
    if (!_repeatKey.pressed) { [self stopRepeat]; return; }
    NSDictionary *s = _repeatKey.spec;
    if ([s[K_TYPE] isEqualToString:@"char"]) {
        [[PDConnection shared] sendText:s[K_CHAR]];
    } else {
        [[PDConnection shared] sendKey:[s[K_CODE] intValue] mods:[self mods] action:2];
    }
}

- (void)stopRepeat {
    [_repeatTimer invalidate];
    _repeatTimer = nil;
    _repeatKey = nil;
}

@end
