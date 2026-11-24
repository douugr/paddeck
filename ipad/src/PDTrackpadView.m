#import "PDTrackpadView.h"
#import <QuartzCore/QuartzCore.h>
#import "PDConnection.h"
#import "PDSettings.h"
#import "PDKeys.h"
#import "PDTheme.h"

static const CGFloat kButtonsHeight = 56;
static const CFTimeInterval kTapMaxDuration = 0.3;
static const CGFloat kTapMaxTravel = 10;
static const NSTimeInterval kDragWindow = 0.22;  // delay before a single tap clicks (tap-to-drag)

@interface PDTrackpadView ()
@property (nonatomic, strong) UIView *surface;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UIButton *leftButton;
@property (nonatomic, strong) UIButton *rightButton;
@property (nonatomic, strong) UIView *strip;       // one-finger scroll strip on an edge
@property (nonatomic, strong) UILabel *stripGrip;
@end

@implementation PDTrackpadView {
    NSMutableSet *_touches;
    NSUInteger _maxFingers;
    CFTimeInterval _start;
    CGFloat _travel;
    CGFloat _remX, _remY, _scrollRemX, _scrollRemY;
    CGPoint _swipe;
    BOOL _swipeFired;
    BOOL _dragging;
    BOOL _secondTap;       // a tap happened just before this gesture and its click is on hold
    NSTimer *_clickTimer;

    // Momentum scrolling ("flick" with two fingers, like a Mac trackpad)
    NSMutableArray *_scrollSamples;    // @[time, dx, dy] of the last ~100 ms, scaled and signed
    CADisplayLink *_momentumLink;
    CGFloat _momentumX, _momentumY;    // px per second
    CFTimeInterval _momentumLast;
    BOOL _inertia;

    CGFloat _pointerSpeed, _scrollSpeed;
    BOOL _natural, _tapToClick, _tapToDrag;

    BOOL _stripOn, _stripLeft;
    UITouch *_stripTouch;     // while set, the strip owns the gesture
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.multipleTouchEnabled = YES;
        _touches = [NSMutableSet set];

        _surface = [[UIView alloc] init];
        _surface.backgroundColor = PDColorSurface();
        _surface.layer.cornerRadius = 14;
        _surface.userInteractionEnabled = NO;   // touches handled by self
        [self addSubview:_surface];

        _hint = [[UILabel alloc] init];
        _hint.text = @"Trackpad";
        _hint.textColor = PDColorText(PDThemeIsLight() ? 0.2 : 0.12);
        _hint.font = PDFont(28, PDWeightLight);
        _hint.textAlignment = NSTextAlignmentCenter;
        [_surface addSubview:_hint];

        _leftButton = [self makeButton:@"Clique" tag:0];
        _rightButton = [self makeButton:@"Clique direito" tag:1];

        _strip = [[UIView alloc] init];
        _strip.backgroundColor = PDColorSurfaceActive();
        _strip.layer.cornerRadius = 12;
        _strip.userInteractionEnabled = NO;
        _stripGrip = [[UILabel alloc] init];
        _stripGrip.numberOfLines = 3;
        _stripGrip.text = @"\u25B2\n\u2261\n\u25BC";   // ▲ ≡ ▼
        _stripGrip.textColor = PDColorText(0.3);
        _stripGrip.font = PDFont(13, PDWeightMedium);
        _stripGrip.textAlignment = NSTextAlignmentCenter;
        [_strip addSubview:_stripGrip];
        [_surface addSubview:_strip];

        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        _stripOn = [d boolForKey:PDPrefScrollStrip];
        _stripLeft = [d boolForKey:PDPrefScrollStripLeft];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyStripPrefs)
                                                     name:NSUserDefaultsDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyStripPrefs {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL on = [d boolForKey:PDPrefScrollStrip], left = [d boolForKey:PDPrefScrollStripLeft];
    if (on == _stripOn && left == _stripLeft) return;
    _stripOn = on;
    _stripLeft = left;
    dispatch_async(dispatch_get_main_queue(), ^{ [self setNeedsLayout]; });
}

- (UIButton *)makeButton:(NSString *)title tag:(NSInteger)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = tag;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:PDColorText(0.65) forState:UIControlStateNormal];
    b.titleLabel.font = PDFont(15, PDWeightMedium);
    b.backgroundColor = PDColorSurface();
    b.layer.cornerRadius = 12;
    [b addTarget:self action:@selector(buttonDown:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(buttonUp:)
       forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addSubview:b];
    return b;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat gap = 8;
    _surface.frame = CGRectMake(0, 0, b.size.width, b.size.height - kButtonsHeight - gap);
    CGFloat stripW = 56, inset = 6;
    CGRect sb = _surface.bounds;
    _strip.hidden = !_stripOn;
    _strip.frame = CGRectMake(_stripLeft ? inset : sb.size.width - stripW - inset, inset,
                              stripW, MAX(sb.size.height - inset * 2, 0));
    _stripGrip.frame = _strip.bounds;
    // Keep the hint centred in the area that still moves the pointer.
    CGRect free = sb;
    if (_stripOn) {
        free.size.width -= stripW + inset;
        if (_stripLeft) free.origin.x += stripW + inset;
    }
    _hint.frame = free;
    CGFloat w = (b.size.width - gap) / 2;
    CGFloat y = b.size.height - kButtonsHeight;
    _leftButton.frame = CGRectMake(0, y, w, kButtonsHeight);
    _rightButton.frame = CGRectMake(w + gap, y, w, kButtonsHeight);
}

#pragma mark - Hold buttons

- (void)buttonDown:(UIButton *)b {
    b.backgroundColor = PDColorKeyActive();
    [[PDConnection shared] sendButton:(int)b.tag action:0];
}

- (void)buttonUp:(UIButton *)b {
    b.backgroundColor = PDColorSurface();
    [[PDConnection shared] sendButton:(int)b.tag action:1];
}

#pragma mark - Gestures

- (void)loadPrefs {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    _pointerSpeed = [d floatForKey:PDPrefPointerSpeed];
    _scrollSpeed = [d floatForKey:PDPrefScrollSpeed];
    _natural = [d boolForKey:PDPrefNaturalScroll];
    _tapToClick = [d boolForKey:PDPrefTapToClick];
    _tapToDrag = [d boolForKey:PDPrefTapToDrag];
    _inertia = [d boolForKey:PDPrefInertialScroll];
}

- (BOOL)inStrip:(UITouch *)t {
    if (!_stripOn || _strip.hidden) return NO;
    // A little extra margin makes the edge easy to hit.
    CGRect r = CGRectInset([_surface convertRect:_strip.frame toView:self], -6, 0);
    return CGRectContainsPoint(r, [t locationInView:self]);
}

- (BOOL)inSurface:(UITouch *)t {
    return CGRectContainsPoint(_surface.frame, [t locationInView:self]);
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self stopMomentum];   // touching the trackpad stops a flick, like on the Mac
    if (_stripTouch) return;
    if (_touches.count == 0 && !_clickTimer) {
        for (UITouch *t in touches) {
            if (![self inStrip:t]) continue;
            [self loadPrefs];
            _stripTouch = t;
            if (!_scrollSamples) _scrollSamples = [NSMutableArray array];
            [_scrollSamples removeAllObjects];
            _scrollRemX = _scrollRemY = 0;
            _strip.backgroundColor = PDColorText(PDThemeIsLight() ? 0.16 : 0.14);
            return;
        }
    }
    if (_touches.count == 0) {
        if (!_scrollSamples) _scrollSamples = [NSMutableArray array];
        [_scrollSamples removeAllObjects];
        [self loadPrefs];
        _maxFingers = 0;
        _start = CACurrentMediaTime();
        _travel = 0;
        _swipe = CGPointZero;
        _swipeFired = NO;
        _remX = _remY = _scrollRemX = _scrollRemY = 0;
        if (_clickTimer) {
            [_clickTimer invalidate];
            _clickTimer = nil;
            _secondTap = YES;
        }
    }
    for (UITouch *t in touches) {
        if ([self inSurface:t]) [_touches addObject:t];
    }
    _maxFingers = MAX(_maxFingers, _touches.count);
    if (_secondTap && _maxFingers > 1) {
        // Not a double tap after all: deliver the held click and carry on.
        _secondTap = NO;
        [[PDConnection shared] sendButton:0 action:2];
    }
    _surface.backgroundColor = PDColorSurfaceActive();
}

- (CGPoint)averageDelta {
    CGPoint sum = CGPointZero;
    NSUInteger n = 0;
    for (UITouch *t in _touches) {
        CGPoint a = [t locationInView:self], p = [t previousLocationInView:self];
        sum.x += a.x - p.x;
        sum.y += a.y - p.y;
        n++;
    }
    if (n) { sum.x /= n; sum.y /= n; }
    return sum;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (_stripTouch) {
        if (![touches containsObject:_stripTouch]) return;
        CGFloat dy = [_stripTouch locationInView:self].y - [_stripTouch previousLocationInView:self].y;
        // A bit faster than two fingers: the strip is narrow and used with one finger.
        CGFloat v = dy * _scrollSpeed * 1.5 * (_natural ? 1 : -1);
        CGFloat fy = v + _scrollRemY;
        int iy = (int)lround(fy);
        _scrollRemY = fy - iy;
        if (iy) [[PDConnection shared] sendScrollDY:iy dx:0];
        CFTimeInterval now = CACurrentMediaTime();
        [_scrollSamples addObject:@[@(now), @0, @(v)]];
        while (_scrollSamples.count && now - [_scrollSamples[0][0] doubleValue] > 0.1) [_scrollSamples removeObjectAtIndex:0];
        return;
    }
    if (_touches.count == 0) return;
    CGPoint d = [self averageDelta];
    CGFloat dist = hypot(d.x, d.y);
    _travel += dist;
    PDConnection *c = [PDConnection shared];

    if (_touches.count == 1 && _maxFingers == 1) {
        if (_secondTap && !_dragging && _travel > 6) {
            _dragging = YES;
            [c sendButton:0 action:0];
        }
        CGFloat gain = _pointerSpeed * MIN(1.0 + dist * 0.08, 4.0);
        CGFloat fx = d.x * gain + _remX, fy = d.y * gain + _remY;
        int ix = (int)lround(fx), iy = (int)lround(fy);
        _remX = fx - ix;
        _remY = fy - iy;
        [c sendMoveDX:ix dy:iy];
    } else if (_touches.count == 2 && _maxFingers == 2) {
        if (_travel < 4) return;   // keep two-finger taps clean
        CGFloat sign = _natural ? 1 : -1;
        CGFloat fy = d.y * _scrollSpeed * sign + _scrollRemY;
        CGFloat fx = d.x * _scrollSpeed * sign + _scrollRemX;
        int iy = (int)lround(fy), ix = (int)lround(fx);
        _scrollRemY = fy - iy;
        _scrollRemX = fx - ix;
        [c sendScrollDY:iy dx:ix];
        CFTimeInterval now = CACurrentMediaTime();
        [_scrollSamples addObject:@[@(now), @(d.x * _scrollSpeed * sign), @(d.y * _scrollSpeed * sign)]];
        while (_scrollSamples.count && now - [_scrollSamples[0][0] doubleValue] > 0.1) [_scrollSamples removeObjectAtIndex:0];
    } else if (_touches.count == 3 && !_swipeFired) {
        _swipe.x += d.x;
        _swipe.y += d.y;
        int code = -1;
        if (_swipe.x < -80) code = PDKeyRight;        // fingers left -> next space
        else if (_swipe.x > 80) code = PDKeyLeft;
        else if (_swipe.y < -60) code = PDKeyUp;      // Mission Control
        else if (_swipe.y > 60) code = PDKeyDown;     // App Exposé
        if (code >= 0) {
            _swipeFired = YES;
            [c sendKey:code mods:PDModCtrl action:2];
        }
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self finish:touches cancelled:NO];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self finish:touches cancelled:YES];
}

#pragma mark - Momentum

- (void)startMomentum {
    CFTimeInterval now = CACurrentMediaTime();
    if (!_scrollSamples.count) return;
    CFTimeInterval first = [_scrollSamples[0][0] doubleValue], last = [[_scrollSamples lastObject][0] doubleValue];
    if (now - last > 0.06) return;   // paused before lifting: no flick
    double sx = 0, sy = 0;
    for (NSArray *s in _scrollSamples) { sx += [s[1] doubleValue]; sy += [s[2] doubleValue]; }
    double span = MAX(now - first, 1.0 / 60);
    double vx = sx / span, vy = sy / span;
    if (hypot(vx, vy) < 250) return;
    _momentumX = vx;
    _momentumY = vy;
    _scrollRemX = _scrollRemY = 0;
    _momentumLast = now;
    _momentumLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(momentumTick)];
    [_momentumLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)momentumTick {
    CFTimeInterval now = CACurrentMediaTime();
    double dt = MIN(MAX(now - _momentumLast, 0), 0.05);
    _momentumLast = now;
    double decay = pow(0.95, dt * 60);   // friction close to macOS
    _momentumX *= decay;
    _momentumY *= decay;
    if (hypot(_momentumX, _momentumY) < 30) { [self stopMomentum]; return; }
    CGFloat fx = _momentumX * dt + _scrollRemX, fy = _momentumY * dt + _scrollRemY;
    int ix = (int)lround(fx), iy = (int)lround(fy);
    _scrollRemX = fx - ix;
    _scrollRemY = fy - iy;
    [[PDConnection shared] sendScrollDY:iy dx:ix];
}

- (void)stopMomentum {
    [_momentumLink invalidate];
    _momentumLink = nil;
    _momentumX = _momentumY = 0;
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if (!newWindow) [self stopMomentum];
}

- (void)finish:(NSSet *)touches cancelled:(BOOL)cancelled {
    if (_stripTouch) {
        if (![touches containsObject:_stripTouch]) return;
        _stripTouch = nil;
        _strip.backgroundColor = PDColorSurfaceActive();
        if (!cancelled && _inertia) [self startMomentum];
        return;
    }
    for (UITouch *t in touches) [_touches removeObject:t];
    if (_touches.count > 0) return;
    _surface.backgroundColor = PDColorSurface();

    PDConnection *c = [PDConnection shared];
    BOOL tap = !cancelled && (CACurrentMediaTime() - _start) < kTapMaxDuration && _travel < kTapMaxTravel;
    if (_maxFingers == 2 && !tap && !cancelled && _inertia) [self startMomentum];

    if (_dragging) {
        _dragging = NO;
        _secondTap = NO;
        [c sendButton:0 action:1];
        return;
    }
    if (_secondTap) {
        _secondTap = NO;
        [c sendButton:0 action:2];               // the held first click
        if (tap) [c sendButton:0 action:2];      // second click -> double click on the Mac
        return;
    }
    if (!tap || !_tapToClick || _maxFingers == 0) return;

    if (_maxFingers == 1) {
        if (_tapToDrag) {
            _clickTimer = [NSTimer scheduledTimerWithTimeInterval:kDragWindow target:self
                                                         selector:@selector(clickTimerFired)
                                                         userInfo:nil repeats:NO];
        } else {
            [c sendButton:0 action:2];
        }
    } else if (_maxFingers == 2) {
        [c sendButton:1 action:2];
    } else if (_maxFingers == 3) {
        [c sendButton:2 action:2];
    }
}

- (void)clickTimerFired {
    _clickTimer = nil;
    [[PDConnection shared] sendButton:0 action:2];
}

@end
