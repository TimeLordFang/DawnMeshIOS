#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface DawnMeshInternetDSP : NSObject
+ (instancetype)shared NS_SWIFT_NAME(shared());
- (void)start:(int)level NS_SWIFT_NAME(start(_:));
- (void)stop;
- (void)setLevel:(int)level NS_SWIFT_NAME(setLevel(_:));
@end
NS_ASSUME_NONNULL_END
