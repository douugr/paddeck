#import <UIKit/UIKit.h>

@interface PDSettingsViewController : UITableViewController
@property (nonatomic, copy) void (^onClose)(void);
@end
