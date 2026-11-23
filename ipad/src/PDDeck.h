#import <UIKit/UIKit.h>

// Slot dictionary keys
#define PDSlotTitle @"title"
#define PDSlotType  @"type"    // NSNumber PDActionType
#define PDSlotValue @"value"
#define PDSlotColor @"color"   // index into PDDeckColors()

typedef NS_ENUM(NSInteger, PDActionType) {
    PDActionNone = -1,
    PDActionShortcut = 0,   // "cmd+shift+4"
    PDActionText = 1,       // typed as text
    PDActionOpen = 2,       // app name, bundle id, path or URL
    PDActionMedia = 3,      // play, next, prev, volup, voldown, mute, brightup, brightdown
};

#define PDDeckColumns 5
#define PDDeckRows 3
#define PDDeckPages 3
#define PDDeckSlotsPerPage (PDDeckColumns * PDDeckRows)

/// Shortcut buttons, persisted in Documents/deck.plist.
@interface PDDeck : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSUInteger count;
- (NSDictionary *)slotAtIndex:(NSUInteger)i;
- (void)setSlot:(NSDictionary *)slot atIndex:(NSUInteger)i;   // nil clears
- (void)resetToDefaults;
+ (PDActionType)typeOf:(NSDictionary *)slot;   // PDActionNone for empty slots
/// Performs the slot's action on the Mac.
+ (void)perform:(NSDictionary *)slot;
/// Short description of the action for the button subtitle.
+ (NSString *)subtitleFor:(NSDictionary *)slot;
@end

@class PDDeckView;
@protocol PDDeckViewDelegate <NSObject>
- (void)deckView:(PDDeckView *)view editSlotAtIndex:(NSUInteger)index;
@end

/// Paged 5×3 grid. Tap runs, long-press (or tap on an empty slot) edits.
@interface PDDeckView : UIView
@property (nonatomic, weak) id<PDDeckViewDelegate> delegate;
- (void)reload;
@end
