// UnityTraceLab — authorized Unity IL2CPP runtime research
// MIT © 2026 UnityTraceLab contributors
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface UTLRuntime : NSObject
+ (instancetype)shared;
- (NSDictionary *)indexMethods:(NSString *)query;
- (NSDictionary *)armTrace:(NSString *)query;
- (NSDictionary *)disarmTrace;
- (NSDictionary *)beginPhase:(NSString *)phase;
- (NSDictionary *)endPhase;
- (NSDictionary *)comparePhases;
- (NSDictionary *)exportCodeSamples;
- (NSArray<NSURL *> *)exportURLs;
- (NSDictionary *)diagnostics;
@end
NS_ASSUME_NONNULL_END
