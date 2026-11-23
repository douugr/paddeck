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

    CGFloat _pointerSpeed, _scrollSpeed;
    BOOL _natural, _tapToClick, _tapToDrag;
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
        _hint.textColor = [UIColor colorWithWhite:1 alpha:0.12];
        _hint.font = PDFont(28, PDWeightLight);
        _hint.textAlignment = NSTextAlignmentCenter;
        [_surface addSubview:_hint];

        _leftButton = [self makeButton:@"Clique" tag:0];
        _rightButton = [self makeButton:@"Clique direito" tag:1];
    }
    return self;
}

- (UIButton *)makeButton:(NSString *)title tag:(NSInteger)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = tag;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.6] forState:UIControlStateNormal];
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
    _hint.frame = _surface.bounds;
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
}

- (BOOL)inSurface:(UITouch *)t {
    return CGRectContainsPoint(_surface.frame, [t locationInView:self]);
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (_touches.count == 0) {
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

- (void)finish:(NSSet *)touches cancelled:(BOOL)cancelled {
    for (UITouch *t in touches) [_touches removeObject:t];
    if (_touches.count > 0) return;
    _surface.backgroundColor = PDColorSurface();

    PDConnection *c = [PDConnection shared];
    BOOL tap = !cancelled && (CACurrentMediaTime() - _start) < kTapMaxDuration && _travel < kTapMaxTravel;

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
