#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, PDState) {
    PDStateIdle,        // not connected and not trying
    PDStateConnecting,  // connecting, authenticating or retrying after a drop
    PDStateConnected,
};

/// Posted on the main thread whenever state, macName or lastDenyReason change.
extern NSString *const PDConnectionChangedNotification;

@interface PDConnection : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) PDState state;
@property (nonatomic, readonly, copy) NSString *host;
@property (nonatomic, readonly, copy) NSString *macName;
/// 0 none, 1 wrong PIN, 2 too many attempts, 3 version mismatch. Reset on the next connect.
@property (nonatomic, readonly) int lastDenyReason;
@property (nonatomic, readonly, copy) NSString *lastError;
/// YES while connected (or connecting) through the USB cable.
@property (nonatomic, readonly) BOOL viaUSB;

- (void)connectToHost:(NSString *)host name:(NSString *)name pin:(NSString *)pin;
/// User-initiated disconnect: stops automatic reconnection.
- (void)disconnect;
/// Reconnects after the app comes back to the foreground, if a connection is wanted.
- (void)resumeIfNeeded;

// Input. All are safe to call from the main thread and no-ops while not connected.
- (void)sendButton:(int)button action:(int)action;   // button 0 L 1 R 2 M; action 0 down 1 up 2 click
- (void)sendMoveDX:(int)dx dy:(int)dy;
- (void)sendScrollDY:(int)dy dx:(int)dx;
- (void)sendText:(NSString *)text;
- (void)sendKey:(int)code mods:(uint8_t)mods action:(int)action;  // action 0 down 1 up 2 press
- (void)sendMedia:(int)key;
- (void)sendOpen:(NSString *)target;

@end
