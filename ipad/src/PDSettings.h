#import <Foundation/Foundation.h>

// NSUserDefaults keys
#define PDPrefPointerSpeed   @"pointerSpeed"    // float 0.5 – 4
#define PDPrefScrollSpeed    @"scrollSpeed"     // float 0.5 – 4
#define PDPrefNaturalScroll  @"naturalScroll"   // bool
#define PDPrefTapToClick     @"tapToClick"      // bool
#define PDPrefTapToDrag      @"tapToDrag"       // bool (double-tap and drag)
#define PDPrefKeepAwake      @"keepAwake"       // bool
#define PDPrefShowKeyboard   @"showKeyboard"    // bool
#define PDPrefKeyboardOnTop   @"keyboardOnTop"   // bool: keyboard above the trackpad
#define PDPrefKeyClick       @"keyClick"        // bool: click sound on keys
#define PDPrefLastHost       @"lastHost"        // string (IP)
#define PDPrefLastName       @"lastName"        // string (Mac name)
#define PDPrefPins           @"pins"            // dict name/host -> PIN

void PDRegisterDefaults(void);
