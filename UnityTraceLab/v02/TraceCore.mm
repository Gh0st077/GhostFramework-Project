// UnityTraceLab v0.2 — runtime metadata, safe code sampling, opt-in function call tracing.
// For developer-owned/authorized Unity IL2CPP applications. Does not bypass app protections.
// MIT © 2026 UnityTraceLab contributors; Dobby linked under Apache-2.0.
#import "TraceCore.h"
#import <CommonCrypto/CommonDigest.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#include <atomic>
#include <stdint.h>
#include <string.h>
#include <math.h>

// Dobby Apache-2.0; linked statically by CI. We do not inspect/modify arguments.
extern "C" int DobbyInstrument(void *address, void (*callback)(void *, void *));
extern "C" int DobbyDestroy(void *address);

struct Il2CppDomain; struct Il2CppAssembly; struct Il2CppImage;
struct Il2CppClass; struct MethodInfo; struct Il2CppType; struct Il2CppThread;
typedef Il2CppDomain *(*domain_get_fn)();
typedef const Il2CppAssembly **(*assemblies_fn)(const Il2CppDomain *, size_t *);
typedef const Il2CppImage *(*image_fn)(const Il2CppAssembly *);
typedef const char *(*image_name_fn)(const Il2CppImage *);
typedef size_t (*class_count_fn)(const Il2CppImage *);
typedef Il2CppClass *(*class_at_fn)(const Il2CppImage *, size_t);
typedef const char *(*class_str_fn)(Il2CppClass *);
typedef const MethodInfo *(*methods_fn)(Il2CppClass *, void **);
typedef const char *(*method_str_fn)(const MethodInfo *);
typedef uint32_t (*param_count_fn)(const MethodInfo *);
typedef const Il2CppType *(*param_fn)(const MethodInfo *, uint32_t);
typedef const Il2CppType *(*return_fn)(const MethodInfo *);
typedef char *(*type_name_fn)(const Il2CppType *);
typedef void (*free_fn)(void *);
typedef Il2CppThread *(*attach_fn)(Il2CppDomain *);
typedef void (*detach_fn)(Il2CppThread *);

static NSString *UTDir(void) {
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: NSTemporaryDirectory();
    NSString *dir = [doc stringByAppendingPathComponent:@"UnityTraceLab"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}
static NSString *UTPath(NSString *filename) { return [UTDir() stringByAppendingPathComponent:filename]; }
static NSString *UTStr(const char *c) { return c ? ([NSString stringWithUTF8String:c] ?: @"") : @""; }
static NSString *UTTime(void) {
    static NSDateFormatter *format = nil;
    @synchronized ([NSDateFormatter class]) {
        if (!format) {
            format = [NSDateFormatter new];
            format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            format.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
        }
        return [format stringFromDate:[NSDate date]];
    }
}
static void UTWrite(NSString *path, NSDictionary *obj) {
    if (!path || !obj) return;
    NSData *json = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingFragmentsAllowed error:nil];
    if (!json) return;
    NSMutableData *data = [json mutableCopy];
    [data appendBytes:"\n" length:1];
    @synchronized ([NSFileHandle class]) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:path])
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *f = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!f) return;
        @try { [f seekToEndOfFile]; [f writeData:data]; [f closeFile]; }
        @catch (__unused NSException *e) { @try { [f closeFile]; } @catch (__unused NSException *ignore) {} }
    }
}
static void UTLog(NSString *kind, NSString *msg, NSDictionary *info) {
    NSMutableDictionary *obj = [@{
        @"time": UTTime(), @"kind":kind ?: @"unknown", @"message":msg ?: @"",
        @"schema":@2, @"bundle":NSBundle.mainBundle.bundleIdentifier ?: @"unknown"
    } mutableCopy];
    if (info) [obj addEntriesFromDictionary:info];
    UTWrite(UTPath(@"events.jsonl"),obj);
    NSLog(@"[UnityTraceLab] %@: %@",kind,msg);
}
static NSString *UTHex(uint64_t v) { return [NSString stringWithFormat:@"0x%llx", (unsigned long long)v]; }
static NSString *UTSHA(NSData *d) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, digest);
    NSMutableString *s = [NSMutableString new];
    for (size_t i=0; i<CC_SHA256_DIGEST_LENGTH; ++i) [s appendFormat:@"%02x",digest[i]];
    return s;
}

// Only native code within loaded Mach-O __text sections qualifies for addresses and samples.
static BOOL UTCodeSection(uintptr_t address, size_t *remaining, NSString **module, uintptr_t *base) {
    for (uint32_t i=0; i<_dyld_image_count(); ++i) {
        const struct mach_header *hdr = _dyld_get_image_header(i);
        if (!hdr || hdr->magic != MH_MAGIC_64) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const uint8_t *cursor = (const uint8_t *)(hdr+1);
        const struct mach_header_64 *mh = (const struct mach_header_64 *)hdr;
        for (uint32_t j=0;j<mh->ncmds;++j) {
            const struct load_command *lc = (const struct load_command *)cursor;
            if (lc->cmdsize < sizeof(*lc)) break;
            if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                if (seg->initprot & VM_PROT_EXECUTE) {
                    const struct section_64 *sect = (const struct section_64 *)(seg+1);
                    uint32_t cap = (lc->cmdsize - sizeof(*seg))/sizeof(*sect);
                    for (uint32_t k=0;k<MIN(seg->nsects,cap);++k) {
                        if (strncmp(sect[k].sectname, "__text", 16) != 0) continue;
                        uintptr_t start = (uintptr_t)((int64_t)sect[k].addr + slide);
                        uint64_t size = sect[k].size;
                        if (address >= start && address-start < size) {
                            if (remaining) *remaining=(size_t)(size-(address-start));
                            if (module) *module=UTStr(_dyld_get_image_name(i)).lastPathComponent;
                            if (base) *base=(uintptr_t)hdr;
                            return YES;
                        }
                    }
                }
            }
            cursor += lc->cmdsize;
        }
    }
    return NO;
}
static NSData *UTReadCode(uintptr_t address, NSUInteger requested) {
    size_t remain=0;
    if (!UTCodeSection(address,&remain,NULL,NULL)) return nil;
    size_t size=MIN((size_t)requested, remain);
    if (!size || size>4096) return nil;
    NSMutableData *bytes=[NSMutableData dataWithLength:size];
    vm_size_t obtained=0;
    kern_return_t status=vm_read_overwrite(mach_task_self(),(vm_address_t)address,
                              size,(vm_address_t)bytes.mutableBytes,&obtained);
    if (status != KERN_SUCCESS || obtained != size) return nil;
    return bytes;
}
static uintptr_t UTMethodPointer(const MethodInfo *method) {
    if (!method) return 0;
    uintptr_t ptr=0;
    vm_size_t n=0;
    kern_return_t kr=vm_read_overwrite(mach_task_self(),(vm_address_t)method,
                                            sizeof(ptr),(vm_address_t)&ptr,&n);
    if (kr != KERN_SUCCESS || n != sizeof(ptr)) return 0;
#if __has_feature(ptrauth_calls)
    ptr = (uintptr_t)__builtin_ptrauth_strip((void *)ptr, 0);
#endif
    return UTCodeSection(ptr,NULL,NULL,NULL) ? ptr : 0;
}

static const size_t kTraceSlots=8;
static const size_t kTraceRing=16384;
struct UTSlot {
    std::atomic<uintptr_t> addr{0};
    std::atomic<uint64_t> total{0};
};
struct UTHit {
    std::atomic<uint64_t> seq{0};
    std::atomic<uintptr_t> addr{0};
    std::atomic<uint64_t> tick{0};
    std::atomic<int> phase{0};
};
static UTSlot gSlots[kTraceSlots];
static UTHit gRing[kTraceRing];
static std::atomic<int> gPhase{0};           // 0 idle, 1 baseline, 2 target
static std::atomic<bool> gEnabled{false};
static std::atomic<uint64_t> gSequence{0};
static void UTInstrument(void *address, void *context) {
    (void)context;
    if (!gEnabled.load(std::memory_order_relaxed)) return;
    int phase=gPhase.load(std::memory_order_relaxed);
    if (!phase) return;
    uintptr_t a=(uintptr_t)address;
    for (size_t i=0;i<kTraceSlots;++i) {
        if (gSlots[i].addr.load(std::memory_order_relaxed) != a) continue;
        uint64_t count=gSlots[i].total.fetch_add(1,std::memory_order_relaxed)+1;
        // Aggregate all hits but sample one in eight for bounded per-call telemetry.
        if ((count&7) != 1) return;
        uint64_t seq=gSequence.fetch_add(1,std::memory_order_relaxed)+1;
        UTHit &hit=gRing[(seq-1)%kTraceRing];
        hit.seq.store(0,std::memory_order_relaxed);
        hit.addr.store(a,std::memory_order_relaxed);
        hit.tick.store(mach_absolute_time(),std::memory_order_relaxed);
        hit.phase.store(phase,std::memory_order_relaxed);
        hit.seq.store(seq,std::memory_order_release);
        return;
    }
}
static NSString *UTTypeString(const Il2CppType *t,type_name_fn getType,free_fn release) {
    if (!t||!getType) return @"?";
    char *raw=getType(t);
    if (!raw) return @"?";
    NSString *value=UTStr(raw);
    if (release) release(raw);
    return value;
}
static void *UTUnity(void) {
    for(uint32_t i=0;i<_dyld_image_count();++i) {
        const char *n=_dyld_get_image_name(i);
        if (n&&strstr(n,"UnityFramework")) return dlopen(n,RTLD_NOW|RTLD_NOLOAD);
    }
    return NULL;
}
static NSDictionary *UTError(NSString *code, NSString *detail) {
    UTLog(@"error",detail,@{@"code":code});
    return @{@"ok":@NO,@"code":code,@"error":detail};
}

@interface UTLRuntime () {
    NSMutableArray<NSDictionary *> *_catalog;
    NSMutableArray<NSDictionary *> *_tracked;
    NSMutableArray<NSNumber *> *_baseHits;
    NSMutableArray<NSNumber *> *_targetHits;
    uint64_t _phaseStart[kTraceSlots];
    CFAbsoluteTime _started;
    double _baseSeconds;
    double _targetSeconds;
    NSString *_phaseName;
}
@end
@implementation UTLRuntime
+ (instancetype)shared {
    static UTLRuntime *obj=nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{obj=[UTLRuntime new];});
    return obj;
}
- (instancetype)init {
    if ((self=[super init])) {
        _catalog=[NSMutableArray new]; _tracked=[NSMutableArray new];
        _baseHits=[NSMutableArray new]; _targetHits=[NSMutableArray new];
        _phaseName=@"idle";
        UTLog(@"startup",@"Runtime library initialized; instrumentation OFF",nil);
    }
    return self;
}
- (NSDictionary *)indexMethods:(NSString *)query {
    @synchronized(self) {
        if (_tracked.count) return UTError(@"TRACE_ACTIVE",@"Disarm tracing before rebuilding the catalog");
        void *handle=UTUnity();
        if (!handle) return UTError(@"NO_UNITY",@"UnityFramework not loaded; open the Unity scene first");
#define SYM(name,type) type name=(type)dlsym(handle,"il2cpp_" #name)
        SYM(domain_get,domain_get_fn);
        assemblies_fn assemblies=(assemblies_fn)dlsym(handle,"il2cpp_domain_get_assemblies");
        image_fn getImage=(image_fn)dlsym(handle,"il2cpp_assembly_get_image");
        image_name_fn getImageName=(image_name_fn)dlsym(handle,"il2cpp_image_get_name");
        class_count_fn getClassCount=(class_count_fn)dlsym(handle,"il2cpp_image_get_class_count");
        class_at_fn getClass=(class_at_fn)dlsym(handle,"il2cpp_image_get_class");
        class_str_fn getClassName=(class_str_fn)dlsym(handle,"il2cpp_class_get_name");
        class_str_fn getNamespace=(class_str_fn)dlsym(handle,"il2cpp_class_get_namespace");
        methods_fn getMethods=(methods_fn)dlsym(handle,"il2cpp_class_get_methods");
        method_str_fn getName=(method_str_fn)dlsym(handle,"il2cpp_method_get_name");
        param_count_fn getCount=(param_count_fn)dlsym(handle,"il2cpp_method_get_param_count");
        param_fn getParam=(param_fn)dlsym(handle,"il2cpp_method_get_param");
        return_fn getReturn=(return_fn)dlsym(handle,"il2cpp_method_get_return_type");
        type_name_fn getType=(type_name_fn)dlsym(handle,"il2cpp_type_get_name");
        free_fn il2cppFree=(free_fn)dlsym(handle,"il2cpp_free");
        attach_fn attach=(attach_fn)dlsym(handle,"il2cpp_thread_attach");
        detach_fn detach=(detach_fn)dlsym(handle,"il2cpp_thread_detach");
        if (!domain_get||!assemblies||!getImage||!getClassCount||!getClass||!getClassName||!getMethods||!getName)
            return UTError(@"API_UNAVAILABLE",@"Required IL2CPP exports are unavailable or stripped");
        Il2CppDomain *domain=domain_get();
        if (!domain) return UTError(@"DOMAIN_NOT_READY",@"IL2CPP domain not initialized");
        Il2CppThread *thread=attach?attach(domain):NULL;
        size_t assemblyCount=0;
        const Il2CppAssembly **all=assemblies(domain,&assemblyCount);
        if (!all) {if(thread&&detach)detach(thread);return UTError(@"NO_ASSEMBLIES",@"No assemblies returned");}
        [_catalog removeAllObjects];
        [[NSFileManager defaultManager] removeItemAtPath:UTPath(@"methods.jsonl") error:nil];
        NSString *needle=query.lowercaseString ?: @"";
        NSUInteger visited=0, accepted=0, addressable=0;
        for(size_t a=0;a<MIN(assemblyCount,(size_t)512)&&visited<250000;++a) {
            const Il2CppImage *img=getImage(all[a]); if (!img) continue;
            NSString *assembly=getImageName?UTStr(getImageName(img)):@"";
            size_t classCount=MIN(getClassCount(img),(size_t)50000);
            for(size_t c=0;c<classCount&&visited<250000;++c) {
                Il2CppClass *klass=getClass(img,c); if(!klass)continue;
                NSString *className=UTStr(getClassName(klass));
                NSString *ns=getNamespace?UTStr(getNamespace(klass)):@"";
                void *iterator=NULL; const MethodInfo *method;
                while((method=getMethods(klass,&iterator))&&visited<250000) {
                    visited++;
                    NSString *methodName=UTStr(getName(method));
                    NSString *qualified=[NSString stringWithFormat:@"%@.%@::%@",ns,className,methodName];
                    if (needle.length&&[qualified.lowercaseString rangeOfString:needle].location==NSNotFound)continue;
                    if (accepted>=15000) break;
                    uint32_t args=getCount?MIN(getCount(method),(uint32_t)32):0;
                    NSMutableArray *parameters=[NSMutableArray new];
                    for(uint32_t p=0;p<args;++p) [parameters addObject:UTTypeString(getParam?getParam(method,p):NULL,getType,il2cppFree)];
                    NSString *returnType=getReturn?UTTypeString(getReturn(method),getType,il2cppFree):@"?";
                    NSString *signature=[NSString stringWithFormat:@"%@ %@(%@)",
                        returnType,qualified,[parameters componentsJoinedByString:@", "]];
                    uintptr_t address=UTMethodPointer(method), imageBase=0;
                    NSString *codeModule=@"";
                    if(address) {UTCodeSection(address,NULL,&codeModule,&imageBase);addressable++;}
                    NSDictionary *item=@{
                        @"assembly":assembly,@"class":className,@"namespace":ns,
                        @"method":methodName,@"signature":signature,
                        @"address":@(address),@"address_hex":address?UTHex(address):@"",
                        @"rva":address?UTHex(address-imageBase):@"",
                        @"module":codeModule, @"parameter_types":parameters,
                        @"address_confidence": address ? @"validated_executable_text" : @"unavailable",
                        @"note":@"MethodInfo first-pointer ABI dependent; not a source decompilation"
                    };
                    [_catalog addObject:item];
                    UTWrite(UTPath(@"methods.jsonl"),item);
                    accepted++;
                }
                if(accepted>=15000)break;
            }
            if(accepted>=15000)break;
        }
        if(thread&&detach)detach(thread);
        UTLog(@"index",@"IL2CPP catalog exported",@{@"matches":@(accepted),@"addressable":@(addressable),@"scanned":@(visited),@"filter":needle});
        return @{@"ok":@YES,@"matches":@(accepted),@"addressable":@(addressable),@"scanned":@(visited),
                 @"message":@"Metadata + executable-validated code addresses; no methods executed yet"};
    }
}
- (NSDictionary *)armTrace:(NSString *)query {
    @synchronized(self) {
        if(_tracked.count) return UTError(@"ALREADY_ARMED",@"Disarm before changing trace targets");
        NSString *needle=query.lowercaseString ?: @"";
        if (!needle.length) return UTError(@"FILTER_REQUIRED",@"Choose a specific class/method filter before arming");
        NSMutableSet<NSNumber *> *seen=[NSMutableSet new];
        NSMutableArray<NSDictionary *> *candidates=[NSMutableArray new];
        for(NSDictionary *item in _catalog) {
            if ([item[@"address"] unsignedLongLongValue]==0)continue;
            if ([item[@"signature"] lowercaseString] &&
                [[item[@"signature"] lowercaseString] rangeOfString:needle].location==NSNotFound) continue;
            NSNumber *address=item[@"address"];
            if([seen containsObject:address])continue;
            [seen addObject:address];
            [candidates addObject:item];
        }
        if(!candidates.count) return UTError(@"NO_MATCH",@"No executable-validated method addresses match that filter");
        if(candidates.count>kTraceSlots)
            return UTError(@"TOO_MANY",@"Filter is too broad: more than eight distinct functions. Narrow it before tracing.");
        [_baseHits removeAllObjects]; [_targetHits removeAllObjects];
        _baseSeconds=0;_targetSeconds=0;_phaseName=@"idle";_started=0;
        gPhase.store(0);gEnabled.store(false);
        for(size_t i=0;i<kTraceSlots;++i) {
            gSlots[i].addr.store(0);gSlots[i].total.store(0);
        }
        NSMutableArray *installed=[NSMutableArray new];
        NSMutableArray *errors=[NSMutableArray new];
        for(NSDictionary *item in candidates) {
            uintptr_t address=[item[@"address"] unsignedLongLongValue];
            if(!UTCodeSection(address,NULL,NULL,NULL))continue;
            int result=DobbyInstrument((void*)address,&UTInstrument);
            if(result==0) {
                size_t i=installed.count;
                gSlots[i].addr.store(address);
                [installed addObject:item];
                [_baseHits addObject:@0];[_targetHits addObject:@0];
            } else {
                [errors addObject:@{@"address":item[@"address_hex"],@"status":@(result),@"signature":item[@"signature"]}];
            }
        }
        [_tracked addObjectsFromArray:installed];
        gEnabled.store(_tracked.count>0);
        UTLog(@"trace_armed",@"User explicitly armed native function tracing",
              @{@"count":@(_tracked.count),@"failures":errors,@"filter":needle});
        if(!_tracked.count) return UTError(@"INSTRUMENT_FAILED",@"Dobby failed to instrument all candidate addresses");
        return @{@"ok":@YES,@"armed":@(_tracked.count),@"failures":errors,
                 @"methods":[installed valueForKey:@"signature"]};
    }
}
- (NSDictionary *)disarmTrace {
    @synchronized(self) {
        gPhase.store(0);gEnabled.store(false);
        for(NSDictionary *item in _tracked) DobbyDestroy((void *)(uintptr_t)[item[@"address"] unsignedLongLongValue]);
        NSUInteger count=_tracked.count;
        [_tracked removeAllObjects];
        for(size_t i=0;i<kTraceSlots;++i)gSlots[i].addr.store(0);
        _phaseName=@"idle";
        UTLog(@"trace_disarmed",@"Native hooks restored",@{@"count":@(count)});
        return @{@"ok":@YES,@"disarmed":@(count)};
    }
}
- (NSDictionary *)beginPhase:(NSString *)phase {
    @synchronized(self) {
        if(!_tracked.count) return UTError(@"NOT_ARMED",@"Arm selected methods first");
        if(gPhase.load()!=0)return UTError(@"PHASE_ACTIVE",@"End the current phase first");
        BOOL baseline=[phase isEqualToString:@"baseline"];
        BOOL target=[phase isEqualToString:@"target"];
        if(!baseline&&!target)return UTError(@"BAD_PHASE",@"Expected baseline or target");
        for(size_t i=0;i<_tracked.count;++i) _phaseStart[i]=gSlots[i].total.load();
        _started=CFAbsoluteTimeGetCurrent();
        _phaseName=phase;
        gPhase.store(baseline?1:2);
        UTLog(@"phase_start",phase,@{@"targets":@(_tracked.count)});
        return @{@"ok":@YES,@"phase":phase};
    }
}
- (NSDictionary *)endPhase {
    @synchronized(self) {
        int phase=gPhase.exchange(0);
        if(!phase)return UTError(@"NO_PHASE",@"No active baseline/target phase");
        double seconds=MAX(0.001,CFAbsoluteTimeGetCurrent()-_started);
        NSMutableArray *deltas=[NSMutableArray new];
        for(size_t i=0;i<_tracked.count;++i) {
            uint64_t delta=gSlots[i].total.load()-_phaseStart[i];
            [deltas addObject:@(delta)];
            NSMutableArray *arr=(phase==1)?_baseHits:_targetHits;
            uint64_t prior=[arr[i] unsignedLongLongValue];
            arr[i]=@(prior+delta);
        }
        if(phase==1)_baseSeconds+=seconds;else _targetSeconds+=seconds;
        NSString *name=(phase==1)?@"baseline":@"target";
        _phaseName=@"idle";
        UTLog(@"phase_end",name,@{@"seconds":@(seconds),@"hits":deltas});
        return @{@"ok":@YES,@"phase":name,@"duration_seconds":@(seconds),@"counts":deltas};
    }
}
- (NSDictionary *)comparePhases {
    @synchronized(self) {
        if(!_tracked.count) return UTError(@"NOT_ARMED",@"Arm a selection before comparing");
        if(_baseSeconds==0||_targetSeconds==0)
            return UTError(@"INSUFFICIENT_DATA",@"Record a baseline and a target interval first");
        NSMutableArray *ranked=[NSMutableArray new];
        for(size_t i=0;i<_tracked.count;++i) {
            uint64_t b=[_baseHits[i] unsignedLongLongValue],t=[_targetHits[i] unsignedLongLongValue];
            double baseRate=b/_baseSeconds, targetRate=t/_targetSeconds;
            double fold=(targetRate+0.25)/(baseRate+0.25);
            // Associative, not causal. Scores require repeated controlled trials.
            double score=log2(MAX(0.0001,fold))*log1p((double)t);
            NSDictionary *item=@{
                @"signature":_tracked[i][@"signature"],
                @"address":_tracked[i][@"address_hex"],
                @"rva":_tracked[i][@"rva"],
                @"baseline_hits":@(b),@"target_hits":@(t),
                @"baseline_seconds":@(_baseSeconds),@"target_seconds":@(_targetSeconds),
                @"baseline_rate_per_s":@(baseRate),@"target_rate_per_s":@(targetRate),
                @"rate_fold_change":@(fold),@"score":@(score),
                @"interpretation":@"Correlation only; concurrent game activity can create false positives"
            };
            [ranked addObject:item];
        }
        [ranked sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
            double d=[b[@"score"] doubleValue]-[a[@"score"] doubleValue];
            return d>0?NSOrderedDescending:d<0?NSOrderedAscending:NSOrderedSame;
        }];
        UTWrite(UTPath(@"comparisons.jsonl"),@{@"time":UTTime(),@"candidates":ranked,@"schema":@2});
        return @{@"ok":@YES,@"ranked":ranked};
    }
}
- (NSDictionary *)exportCodeSamples {
    @synchronized(self) {
        if(!_catalog.count)return UTError(@"EMPTY_CATALOG",@"Index methods before exporting bytes");
        NSString *samples=[UTDir() stringByAppendingPathComponent:@"code_samples"];
        [[NSFileManager defaultManager] createDirectoryAtPath:samples withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:UTPath(@"code_manifest.jsonl") error:nil];
        NSUInteger dumped=0;
        NSMutableSet *seen=[NSMutableSet new];
        for(NSDictionary *item in _catalog) {
            uintptr_t address=[item[@"address"] unsignedLongLongValue];
            if(!address||[seen containsObject:@(address)])continue;
            [seen addObject:@(address)];
            if(dumped>=64)break;
            NSData *bytes=UTReadCode(address,256);
            if(!bytes.length)continue;
            NSString *name=[NSString stringWithFormat:@"method_%03lu_%llx.bin",(unsigned long)dumped,(unsigned long long)address];
            NSString *path=[samples stringByAppendingPathComponent:name];
            if(![bytes writeToFile:path atomically:YES])continue;
            UTWrite(UTPath(@"code_manifest.jsonl"),@{
                @"signature":item[@"signature"],@"module":item[@"module"],@"address":item[@"address_hex"],
                @"rva":item[@"rva"],@"file":name,@"size":@(bytes.length),@"sha256":UTSHA(bytes),
                @"complete_function":@NO,
                @"note":@"Bounded code sample. Native function length cannot be inferred from IL2CPP metadata."
            });
            dumped++;
        }
        UTLog(@"code_export",@"Read verified executable bytes into bounded samples",@{@"samples":@(dumped)});
        return @{@"ok":@YES,@"count":@(dumped),@"directory":samples,
                 @"warning":@"These are real code bytes, not reconstructed source or guaranteed complete functions"};
    }
}
- (NSArray<NSURL *> *)exportURLs {
    @synchronized(self) {
        NSString *trace=UTPath(@"trace.jsonl");
        [[NSFileManager defaultManager] removeItemAtPath:trace error:nil];
        uint64_t end=gSequence.load(), start=end>kTraceRing?end-kTraceRing+1:1;
        NSUInteger exported=0;
        for(uint64_t seq=start;seq<=end;++seq) {
            UTHit &hit=gRing[(seq-1)%kTraceRing];
            if(hit.seq.load(std::memory_order_acquire)!=seq) continue;
            uintptr_t addr=hit.addr.load();
            int phase=hit.phase.load();
            NSString *sig=@"";
            for(NSDictionary *m in _tracked)if([m[@"address"] unsignedLongLongValue]==addr) {sig=m[@"signature"];break;}
            UTWrite(trace,@{@"seq":@(seq),@"mach_ticks":@(hit.tick.load()),
                            @"phase":phase==1?@"baseline":@"target",
                            @"address":UTHex(addr),@"signature":sig,
                            @"sampling":@"one_in_eight_per_method"});
            exported++;
        }
        UTLog(@"export",@"Trace buffer and reports ready",@{@"samples_exported":@(exported),@"samples_total":@(end)});
        NSMutableArray<NSURL *> *out=[NSMutableArray new];
        for(NSString *n in @[@"events.jsonl",@"methods.jsonl",@"trace.jsonl",
                            @"comparisons.jsonl",@"code_manifest.jsonl"]) {
            NSString *p=UTPath(n);
            if([[NSFileManager defaultManager] fileExistsAtPath:p])
                [out addObject:[NSURL fileURLWithPath:p]];
        }
        // The Share Sheet receives individual sample files, not a raw folder.
        NSString *dir=[UTDir() stringByAppendingPathComponent:@"code_samples"];
        NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
        for(NSString *n in [files sortedArrayUsingSelector:@selector(compare:)]) {
            if(out.count>=75)break;
            if([n.pathExtension.lowercaseString isEqualToString:@"bin"])
                [out addObject:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:n]]];
        }
        return out;
    }
}
- (NSDictionary *)diagnostics {
    @synchronized(self) {
        return @{@"ok":@YES,@"version":@"0.2",@"methods_indexed":@(_catalog.count),
                 @"hooks_armed":@(_tracked.count),@"current_phase":_phaseName ?: @"idle",
                 @"baseline_seconds":@(_baseSeconds),@"target_seconds":@(_targetSeconds),
                 @"ring_samples":@(gSequence.load()),@"ring_capacity":@(kTraceRing),
                 @"dropped_old_samples":@(gSequence.load()>kTraceRing?gSequence.load()-kTraceRing:0),
                 @"safety":@"Explicit opt-in; no automatic hooks; capped to 8 methods"};
    }
}
@end
