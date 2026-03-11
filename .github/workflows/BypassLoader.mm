#import <Foundation/Foundation.h>
#import <dlfcn.h>

void cargarMod() {
    [NSThread sleepForTimeInterval:8];
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *dylibPath = [bundlePath stringByAppendingPathComponent:@"UnityAnalyticsCore.dylib"];
    dlopen([dylibPath UTF8String], RTLD_NOW);
}

__attribute__((constructor)) static void init() {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        cargarMod();
    });
}
