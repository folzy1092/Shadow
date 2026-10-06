#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Shadow: on-device code signing of an unpacked .app with zsign
/// (third-party/zsign). Synchronous and slow; call it off the main thread.
@interface ShadowZsign : NSObject

/// Re-signs every Mach-O and bundle inside `appPath` (a `.app` folder) with the
/// certificate from `p12Path` and embeds `provisionPath`. Entitlements come
/// from the profile. Returns nil on success, otherwise a readable error.
+ (NSString * _Nullable)signAppAtPath:(NSString *)appPath
                        provisionPath:(NSString *)provisionPath
                              p12Path:(NSString *)p12Path
                             password:(NSString *)password NS_SWIFT_NAME(sign(appPath:provisionPath:p12Path:password:));

/// Checks that the p12 opens with `password` and its certificate belongs to the
/// profile, without signing anything. Returns nil when the pair is usable.
+ (NSString * _Nullable)checkProvisionPath:(NSString *)provisionPath
                                   p12Path:(NSString *)p12Path
                                  password:(NSString *)password NS_SWIFT_NAME(check(provisionPath:p12Path:password:));

@end

NS_ASSUME_NONNULL_END
