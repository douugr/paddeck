#import <UIKit/UIKit.h>

@class PDKeyboardView;

@protocol PDKeyboardViewDelegate <NSObject>
/// The "áç" key: show the iOS keyboard (accents, emoji, dictation).
- (void)keyboardViewWantsSystemKeyboard:(PDKeyboardView *)view;
@end

/// Mac-style keyboard (US layout keys, text sent as Unicode). Modifiers: tap once
/// for the next key, tap twice to lock, tap again to release.
@interface PDKeyboardView : UIView
@property (nonatomic, weak) id<PDKeyboardViewDelegate> delegate;
@end
