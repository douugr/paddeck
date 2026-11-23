#import <UIKit/UIKit.h>
#import "PDConnectViewController.h"
#import "PDConnection.h"
#import "PDSettings.h"
#import "PDTheme.h"

@interface PDAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation PDAppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    PDRegisterDefaults();
    [[UINavigationBar appearance] setBarStyle:UIBarStyleBlack];
    [[UINavigationBar appearance] setTintColor:PDColorAccent()];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.tintColor = PDColorAccent();
    self.window.backgroundColor = PDColorBackground();
    self.window.rootViewController = [[PDConnectViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)app {
    [[PDConnection shared] resumeIfNeeded];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([PDAppDelegate class]));
    }
}
