#import "PDTheme.h"
#import "PDSettings.h"

// Same profiles as the App Store app (app/PadDeck/UI/Theme.swift).
#define BLACK 0x1C1C1E
#define DARK(ident, line, name, bg, bar, sf, act, k, kd, ka, acc) \
    { ident, line, name, NO, bg, bar, sf, act, k, kd, ka, 0xFFFFFF, 0xFFFFFF, acc }
#define LIGHT_BLACK_KEYS(ident, line, name, bg, bar, sf, act, txt, acc) \
    { ident, line, name, YES, bg, bar, sf, act, BLACK, 0x2C2C2F, 0x55555A, 0xFFFFFF, txt, acc }
#define LIGHT_KEYS(ident, line, name, bg, bar, sf, act, k, kd, ka, kt, txt, acc) \
    { ident, line, name, YES, bg, bar, sf, act, k, kd, ka, kt, txt, acc }
#define IMAC(ident, name, front, back, bg, bar, act, txt) \
    { ident, "iMac", name, YES, bg, bar, front, act, 0xFFFFFF, 0xEDEDF0, act, BLACK, txt, back }

static const PDPalette kPalettes[] = {
    DARK("dark", "PadDeck", "Escuro", 0x121214, 0x1C1C1F, 0x26262A, 0x2E2E33, 0x3A3A3F, 0x2A2A2E, 0x5A5A62, 0x0A84FF),

    LIGHT_KEYS("neo-silver", "MacBook Neo", "Prateado", 0xE4E5E8, 0xD8D9DD, 0xD0D1D5, 0xC3C4C9,
               0xF7F7F9, 0xD5D6DA, 0xBDBEC3, BLACK, 0x2E2F33, 0x0A6FE0),
    LIGHT_KEYS("neo-blush", "MacBook Neo", "Blush", 0xF3E4E1, 0xEBD8D4, 0xE5CEC9, 0xD9BFB9,
               0xFBF1EF, 0xE3CCC7, 0xD2B2AB, 0x4A2E2A, 0x5A3A35, 0xC25B73),
    LIGHT_KEYS("neo-citrus", "MacBook Neo", "Cítrico", 0xEEF0CB, 0xE5E8B8, 0xDDE1A8, 0xD1D696,
               0xF8F9E3, 0xD9DDA2, 0xC8CD8A, 0x363A10, 0x42461A, 0x6F7F0A),
    DARK("neo-indigo", "MacBook Neo", "Índigo", 0x1D2140, 0x252A4E, 0x2F355E, 0x39406C, 0x434A80, 0x363C6C, 0x5C66A3, 0x93A5FF),

    LIGHT_BLACK_KEYS("air-skyblue", "MacBook Air", "Azul-céu", 0xDCE6EE, 0xD0DCE6, 0xC5D4E0, 0xB7C8D6, 0x2B3945, 0x2F7DC0),
    LIGHT_BLACK_KEYS("air-silver", "MacBook Air", "Prateado", 0xE3E4E7, 0xD7D8DC, 0xCFD0D4, 0xC2C3C8, 0x2E2F33, 0x0A6FE0),
    LIGHT_BLACK_KEYS("air-starlight", "MacBook Air", "Estelar", 0xEFE9DF, 0xE6DED1, 0xDDD4C5, 0xD1C6B5, 0x3D372E, 0x9A733C),
    DARK("air-midnight", "MacBook Air", "Meia-noite", 0x141822, 0x1D2230, 0x272D3C, 0x313849, 0x343B50, 0x292F41, 0x4E5770, 0x5E9CFF),
    DARK("air-spacegray", "MacBook Air", "Cinza-espacial", 0x2E2F33, 0x38393D, 0x45464B, 0x4F5055, 0x18181A, 0x222224, 0x5A5B60, 0x0A84FF),

    DARK("pro-spaceblack", "MacBook Pro", "Preto-espacial", 0x0A0A0B, 0x141415, 0x1E1F21, 0x27282B, 0x303134, 0x242527, 0x4B4C50, 0x0A84FF),
    LIGHT_BLACK_KEYS("pro-silver", "MacBook Pro", "Prateado", 0xE3E4E7, 0xD7D8DC, 0xCFD0D4, 0xC2C3C8, 0x2E2F33, 0x0A6FE0),

    IMAC("imac-blue", "Azul", 0xCADDEF, 0x2D6BB4, 0xDCE8F4, 0xD1E1F0, 0xB8CEE5, 0x1F3A5C),
    IMAC("imac-purple", "Roxo", 0xDDD4EE, 0x7653B5, 0xE9E3F5, 0xE1D9F0, 0xCDC1E4, 0x3E2B60),
    IMAC("imac-pink", "Rosa", 0xF2D5D8, 0xCF4A6B, 0xF8E5E7, 0xF4DCDF, 0xE7C2C7, 0x5E2232),
    IMAC("imac-orange", "Laranja", 0xF6D7C2, 0xDC6427, 0xFAE6D8, 0xF7DECC, 0xEAC4AA, 0x5C2E12),
    IMAC("imac-yellow", "Amarelo", 0xF4E6B6, 0xC9970E, 0xF9F0D2, 0xF6EAC2, 0xE7D59C, 0x4F3D06),
    IMAC("imac-green", "Verde", 0xD0E7D0, 0x3A8A4B, 0xE1F0E1, 0xD8EBD8, 0xBCD9BD, 0x1F4A27),
    IMAC("imac-silver", "Prateado", 0xE5E6E9, 0x6B6E75, 0xEEEFF1, 0xE7E8EB, 0xD0D1D6, 0x2E2F33),
};

static const PDPalette *gCurrent;

NSUInteger PDPaletteCount(void) { return sizeof(kPalettes) / sizeof(kPalettes[0]); }

const PDPalette *PDPaletteAt(NSUInteger i) { return &kPalettes[i < PDPaletteCount() ? i : 0]; }

const PDPalette *PDPaletteNamed(NSString *ident) {
    for (NSUInteger i = 0; i < PDPaletteCount(); i++) {
        if (ident && strcmp(kPalettes[i].ident, ident.UTF8String) == 0) return &kPalettes[i];
    }
    return &kPalettes[0];
}

const PDPalette *PDCurrentPalette(void) {
    if (!gCurrent) gCurrent = PDPaletteNamed([[NSUserDefaults standardUserDefaults] stringForKey:PDPrefTheme]);
    return gCurrent;
}

BOOL PDThemeReload(void) {
    const PDPalette *p = PDPaletteNamed([[NSUserDefaults standardUserDefaults] stringForKey:PDPrefTheme]);
    if (p == PDCurrentPalette()) return NO;
    gCurrent = p;
    return YES;
}
