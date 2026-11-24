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

/// Color profile in use (Ajustes › Cores). Most match a Mac finish: MacBook Neo, Air, Pro, iMac.
/// The main screen reads it when built; settings, connect and editor screens stay dark.
typedef struct {
    const char *ident;   // stored in NSUserDefaults (PDPrefTheme)
    const char *line;    // "PadDeck", "MacBook Neo", "MacBook Air", "MacBook Pro", "iMac"
    const char *name;    // Portuguese name shown in Ajustes
    BOOL light;
    unsigned background, bar, surface, surfaceActive, key, keyDark, keyActive, keyText, text, accent;
} PDPalette;

NSUInteger PDPaletteCount(void);
const PDPalette *PDPaletteAt(NSUInteger i);
const PDPalette *PDPaletteNamed(NSString *ident);
const PDPalette *PDCurrentPalette(void);
/// Rereads the setting; YES when the profile changed.
BOOL PDThemeReload(void);

static inline UIColor *PDColorBackground(void)    { return PDRGB(PDCurrentPalette()->background); }
static inline UIColor *PDColorBar(void)           { return PDRGB(PDCurrentPalette()->bar); }
static inline UIColor *PDColorSurface(void)       { return PDRGB(PDCurrentPalette()->surface); }
static inline UIColor *PDColorSurfaceActive(void) { return PDRGB(PDCurrentPalette()->surfaceActive); }
static inline UIColor *PDColorKey(void)           { return PDRGB(PDCurrentPalette()->key); }
static inline UIColor *PDColorKeyDark(void)       { return PDRGB(PDCurrentPalette()->keyDark); }
static inline UIColor *PDColorKeyActive(void)     { return PDRGB(PDCurrentPalette()->keyActive); }
static inline UIColor *PDColorAccent(void)        { return PDRGB(PDCurrentPalette()->accent); }
static inline UIColor *PDColorKeyText(CGFloat a)  { return [PDRGB(PDCurrentPalette()->keyText) colorWithAlphaComponent:a]; }
static inline UIColor *PDColorText(CGFloat a)     { return [PDRGB(PDCurrentPalette()->text) colorWithAlphaComponent:a]; }
static inline BOOL PDThemeIsLight(void)           { return PDCurrentPalette()->light; }

/// Fixed dark colors for the screens that do not follow the profile.
static inline UIColor *PDColorDarkBackground(void) { return PDRGB(0x121214); }
static inline UIColor *PDColorDarkBar(void)        { return PDRGB(0x1C1C1F); }
static inline UIColor *PDColorDarkSurface(void)    { return PDRGB(0x26262A); }
static inline UIColor *PDColorDarkSurfaceActive(void) { return PDRGB(0x2E2E33); }
static inline UIColor *PDColorBlue(void)           { return PDRGB(0x0A84FF); }
static inline UIColor *PDColorOK(void)            { return PDRGB(0x30D158); }
static inline UIColor *PDColorWarn(void)          { return PDRGB(0xFF9F0A); }
static inline UIColor *PDColorOff(void)           { return PDRGB(0xFF453A); }

/// Deck button colors (dark enough for white text).
static inline NSArray *PDDeckColors(void) {
    return @[PDRGB(0x4A4A50), PDRGB(0x1A6FD8), PDRGB(0x5E4BC4),
             PDRGB(0x2E8B45), PDRGB(0xD9730D), PDRGB(0xC9342B)];
}
