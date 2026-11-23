#import "PDKeys.h"

@implementation PDKeys

+ (NSDictionary *)charTable {
    static NSDictionary *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"a": @0, @"s": @1, @"d": @2, @"f": @3, @"h": @4, @"g": @5, @"z": @6, @"x": @7,
            @"c": @8, @"v": @9, @"b": @11, @"q": @12, @"w": @13, @"e": @14, @"r": @15,
            @"y": @16, @"t": @17, @"1": @18, @"2": @19, @"3": @20, @"4": @21, @"6": @22,
            @"5": @23, @"=": @24, @"9": @25, @"7": @26, @"-": @27, @"8": @28, @"0": @29,
            @"]": @30, @"o": @31, @"u": @32, @"[": @33, @"i": @34, @"p": @35, @"l": @37,
            @"j": @38, @"'": @39, @"k": @40, @";": @41, @"\\": @42, @",": @43, @"/": @44,
            @"n": @45, @"m": @46, @".": @47, @"`": @50, @" ": @49,
        };
    });
    return t;
}

+ (NSDictionary *)nameTable {
    static NSDictionary *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"space": @49, @"tab": @48, @"return": @36, @"enter": @36, @"esc": @53, @"escape": @53,
            @"delete": @51, @"backspace": @51, @"fwddelete": @117, @"del": @117,
            @"up": @126, @"down": @125, @"left": @123, @"right": @124,
            @"home": @115, @"end": @119, @"pgup": @116, @"pageup": @116, @"pgdn": @121, @"pagedown": @121,
            @"f1": @122, @"f2": @120, @"f3": @99, @"f4": @118, @"f5": @96, @"f6": @97,
            @"f7": @98, @"f8": @100, @"f9": @101, @"f10": @109, @"f11": @103, @"f12": @111,
            @"plus": @24, @"minus": @27,
        };
    });
    return t;
}

+ (int)codeForCharacter:(NSString *)ch {
    NSNumber *n = [self charTable][[ch lowercaseString]];
    return n ? n.intValue : -1;
}

+ (int)codeForName:(NSString *)name {
    NSString *k = [name lowercaseString];
    NSNumber *n = [self nameTable][k];
    if (n) return n.intValue;
    if (k.length == 1) return [self codeForCharacter:k];
    return -1;
}

+ (BOOL)parseShortcut:(NSString *)text code:(int *)code mods:(uint8_t *)mods {
    NSString *s = [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
    if (s.length == 0) return NO;
    // "cmd++" means command and the "=" key with shift on US; keep it simple: allow "plus".
    NSArray *parts = [s componentsSeparatedByString:@"+"];
    uint8_t m = 0;
    int c = -1;
    for (NSUInteger i = 0; i < parts.count; i++) {
        NSString *p = [parts[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (p.length == 0) return NO;
        if ([@[@"cmd", @"command", @"⌘"] containsObject:p]) m |= PDModCmd;
        else if ([@[@"shift", @"⇧"] containsObject:p]) m |= PDModShift;
        else if ([@[@"ctrl", @"control", @"⌃"] containsObject:p]) m |= PDModCtrl;
        else if ([@[@"opt", @"option", @"alt", @"⌥"] containsObject:p]) m |= PDModOpt;
        else if ([p isEqualToString:@"fn"]) m |= PDModFn;
        else {
            if (i != parts.count - 1 || c != -1) return NO;
            c = [self codeForName:p];
            if (c < 0) return NO;
        }
    }
    if (c < 0) return NO;
    if (code) *code = c;
    if (mods) *mods = m;
    return YES;
}

+ (NSString *)prettyShortcut:(NSString *)text {
    int code; uint8_t mods;
    if (![self parseShortcut:text code:&code mods:&mods]) return text;
    NSMutableString *out = [NSMutableString string];
    if (mods & PDModCtrl) [out appendString:@"⌃"];
    if (mods & PDModOpt) [out appendString:@"⌥"];
    if (mods & PDModShift) [out appendString:@"⇧"];
    if (mods & PDModCmd) [out appendString:@"⌘"];
    if (mods & PDModFn) [out appendString:@"fn "];
    NSString *key = [[[text componentsSeparatedByString:@"+"] lastObject]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSDictionary *pretty = @{ @"space": @"Espaço", @"tab": @"⇥", @"return": @"↩", @"enter": @"↩",
                              @"esc": @"esc", @"escape": @"esc", @"delete": @"⌫", @"backspace": @"⌫",
                              @"fwddelete": @"⌦", @"del": @"⌦", @"up": @"↑", @"down": @"↓",
                              @"left": @"←", @"right": @"→", @"home": @"↖", @"end": @"↘",
                              @"pgup": @"⇞", @"pageup": @"⇞", @"pgdn": @"⇟", @"pagedown": @"⇟",
                              @"plus": @"+", @"minus": @"-" };
    NSString *p = pretty[[key lowercaseString]];
    [out appendString:p ?: [key uppercaseString]];
    return out;
}

+ (NSArray *)mediaNames {
    return @[@"play", @"prev", @"next", @"voldown", @"volup", @"mute", @"brightdown", @"brightup"];
}

+ (NSArray *)mediaLabels {
    return @[@"Play", @"Anterior", @"Próxima", @"Vol −", @"Vol +", @"Mudo", @"Brilho −", @"Brilho +"];
}

+ (int)mediaCodeForName:(NSString *)name {
    NSDictionary *t = @{ @"play": @(PDMediaPlay), @"prev": @(PDMediaPrev), @"next": @(PDMediaNext),
                         @"voldown": @(PDMediaVolDown), @"volup": @(PDMediaVolUp), @"mute": @(PDMediaMute),
                         @"brightdown": @(PDMediaBrightDown), @"brightup": @(PDMediaBrightUp) };
    NSNumber *n = t[[name lowercaseString]];
    return n ? n.intValue : -1;
}

@end
