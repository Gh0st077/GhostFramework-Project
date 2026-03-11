#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

void cargarMod() {
    [NSThread sleepForTimeInterval:8];
    NSString *path = [[NSBundle mainBundle] bundlePath];
    NSString *dylibPath = [path stringByAppendingPathComponent:@"UnityAnalyticsCore.dylib"];
    dlopen([dylibPath UTF8String], RTLD_NOW);
}

__attribute__((constructor)) static void init() {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        cargarMod();
    });
}
