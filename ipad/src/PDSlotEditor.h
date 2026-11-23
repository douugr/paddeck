#import <UIKit/UIKit.h>

/// Edits one deck slot. onDone gets the new slot dictionary, @{} when deleted,
/// or nil when cancelled.
@interface PDSlotEditor : UIViewController
- (instancetype)initWithSlot:(NSDictionary *)slot;
@property (nonatomic, copy) void (^onDone)(NSDictionary *slot);
@end
