#import <Foundation/Foundation.h>

// Modifier bits (same as the protocol).
enum {
    PDModShift = 1 << 0,
    PDModCtrl  = 1 << 1,
    PDModOpt   = 1 << 2,
    PDModCmd   = 1 << 3,
    PDModFn    = 1 << 4,
};

// macOS virtual key codes used outside the letter/digit table.
enum {
    PDKeyReturn = 36, PDKeyTab = 48, PDKeySpace = 49, PDKeyDelete = 51,
    PDKeyEscape = 53, PDKeyForwardDelete = 117,
    PDKeyLeft = 123, PDKeyRight = 124, PDKeyDown = 125, PDKeyUp = 126,
    PDKeyHome = 115, PDKeyEnd = 119, PDKeyPageUp = 116, PDKeyPageDown = 121,
};

// NX media keys (protocol MEDIA payload).
enum {
    PDMediaVolUp = 0, PDMediaVolDown = 1, PDMediaBrightUp = 2, PDMediaBrightDown = 3,
    PDMediaMute = 7, PDMediaPlay = 16, PDMediaNext = 17, PDMediaPrev = 18,
};

@interface PDKeys : NSObject

/// Key code for a single character on a US layout ("a", "4", "[", …), or -1.
+ (int)codeForCharacter:(NSString *)ch;

/// Key code for a name: letters, digits, symbols, "space", "tab", "return", "esc",
/// "delete", "fwddelete", "up", "down", "left", "right", "home", "end", "pgup",
/// "pgdn", "f1"…"f12". Returns -1 when unknown.
+ (int)codeForName:(NSString *)name;

/// Parses "cmd+shift+4", "ctrl+up", "⌘C"-free plain syntax. Returns NO when invalid.
+ (BOOL)parseShortcut:(NSString *)text code:(int *)code mods:(uint8_t *)mods;

/// Pretty form of a shortcut string: "cmd+shift+4" -> "⌘⇧4". Falls back to the input.
+ (NSString *)prettyShortcut:(NSString *)text;

/// Media key names used by the deck: play, next, prev, volup, voldown, mute, brightup, brightdown.
+ (NSArray *)mediaNames;
+ (NSArray *)mediaLabels;
+ (int)mediaCodeForName:(NSString *)name;

@end
