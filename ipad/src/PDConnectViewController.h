#import <UIKit/UIKit.h>

/// First screen: finds Macs running the agent (Bonjour), asks for the PIN, connects,
/// then presents the main screen. Reconnects to the last Mac automatically.
@interface PDConnectViewController : UIViewController
@end
