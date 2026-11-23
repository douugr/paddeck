#import "PDSettings.h"

void PDRegisterDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        PDPrefPointerSpeed: @1.6,
        PDPrefScrollSpeed: @1.5,
        PDPrefNaturalScroll: @YES,
        PDPrefTapToClick: @YES,
        PDPrefTapToDrag: @YES,
        PDPrefKeepAwake: @YES,
        PDPrefShowKeyboard: @YES,
        PDPrefKeyClick: @YES,
        PDPrefPins: @{},
    }];
}
