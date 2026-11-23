#import <UIKit/UIKit.h>

static inline UIColor *PDRGB(unsigned rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0
                           green:((rgb >> 8) & 0xff) / 255.0
                            blue:(rgb & 0xff) / 255.0
                           alpha:1];
}

/// System font with a weight, without referencing the iOS 8.2+ UIFontWeight* symbols
/// (so the app also launches on iOS 8.0/8.1).
#define PDWeightLight    (-0.4)
#define PDWeightMedium   0.23
#define PDWeightSemibold 0.3
#define PDWeightBold     0.4
static inline UIFont *PDFont(CGFloat size, CGFloat weight) {
    if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)]) return [UIFont systemFontOfSize:size weight:weight];
    return weight >= 0.3 ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
}

static inline UIColor *PDColorBackground(void)    { return PDRGB(0x121214); }
static inline UIColor *PDColorBar(void)           { return PDRGB(0x1C1C1F); }
static inline UIColor *PDColorSurface(void)       { return PDRGB(0x26262A); }
static inline UIColor *PDColorSurfaceActive(void) { return PDRGB(0x2E2E33); }
static inline UIColor *PDColorKey(void)           { return PDRGB(0x3A3A3F); }
static inline UIColor *PDColorKeyDark(void)       { return PDRGB(0x2A2A2E); }
static inline UIColor *PDColorKeyActive(void)     { return PDRGB(0x5A5A62); }
static inline UIColor *PDColorAccent(void)        { return PDRGB(0x0A84FF); }
static inline UIColor *PDColorOK(void)            { return PDRGB(0x30D158); }
static inline UIColor *PDColorWarn(void)          { return PDRGB(0xFF9F0A); }
static inline UIColor *PDColorOff(void)           { return PDRGB(0xFF453A); }

/// Deck button colors (dark enough for white text).
static inline NSArray *PDDeckColors(void) {
    return @[PDRGB(0x4A4A50), PDRGB(0x1A6FD8), PDRGB(0x5E4BC4),
             PDRGB(0x2E8B45), PDRGB(0xD9730D), PDRGB(0xC9342B)];
}
