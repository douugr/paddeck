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
#define PDPrefInertialScroll @"inertialScroll"  // bool: momentum scrolling
#define PDPrefScrollStrip    @"scrollStrip"     // bool: one-finger scroll strip on the trackpad edge
#define PDPrefScrollStripLeft @"scrollStripLeft" // bool: strip on the left edge
#define PDPrefTheme          @"theme"           // string: color profile id (PDTheme.m)
#define PDPrefKeyClick       @"keyClick"        // bool: click sound on keys
#define PDPrefLastHost       @"lastHost"        // string (IP)
#define PDPrefLastName       @"lastName"        // string (Mac name)
#define PDPrefPins           @"pins"            // up to 1.7: dict name/host -> PIN (removed on launch)
#define PDPrefPairedMacs     @"pairedMacs"      // dict Mac key (hex) -> Mac name
#define PDPrefPairedTargets  @"pairedTargets"   // dict Bonjour name / IP -> Mac key (hex)

void PDRegisterDefaults(void);
