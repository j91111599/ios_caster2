#import <mach/mach_time.h>
//  YKSBProbe — SpringBoard 内部注入自测
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static void SBLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[%.3f] %@\n", [[NSDate date] timeIntervalSince1970], msg];
    NSString *path = @"/var/mobile/Media/sbprobe.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]; return; }
    [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile];
}
static void *Sym(NSString *n) {
    static void *qc = NULL;
    if (!qc) qc = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    void *p = qc ? dlsym(qc, n.UTF8String) : NULL;
    if (!p) { static void *hid = NULL;
        if (!hid) hid = dlopen("/System/Library/PrivateFrameworks/IOHID.framework/IOHID", RTLD_LAZY);
        if (hid) p = dlsym(hid, n.UTF8String); }
    return p;
}
static void SBTap(double nx, double ny) {
    void *fp=Sym(@"IOHIDEventCreateDigitizerEvent");
    void *ff=Sym(@"IOHIDEventCreateDigitizerFingerEvent");
    void *fa=Sym(@"IOHIDEventAppendEvent");
    void *fsi=Sym(@"IOHIDEventSetIntegerValue");
    void *fsf=Sym(@"IOHIDEventSetFloatValue");
    void *fss=Sym(@"IOHIDEventSetSenderID");
    void *fc=Sym(@"IOHIDEventSystemClientCreate");
    void *hr=Sym(@"IOHIDEventSystemClientRegisterEventCallback");
    void *hs=Sym(@"IOHIDEventSystemClientScheduleWithRunLoop");
    void *hd=Sym(@"IOHIDEventSystemClientDispatchEvent");
    if(!fp||!ff||!hd||!fc){ SBLog(@"SBtap missing sym fp=%p ff=%p hd=%p fc=%p",fp,ff,hd,fc); return; }
    static void *client=NULL;
    if(!client){
        client=((void*(*)(CFAllocatorRef))fc)(kCFAllocatorDefault);
        if(client){
            if(hr)((void(*)(void*,void*,void*,uint32_t))hr)(client,NULL,NULL,0);
            if(hs)((void(*)(void*,CFRunLoopRef,CFStringRef))hs)(client,CFRunLoopGetMain(),kCFRunLoopCommonModes);
        }
    }
    if(!client){ SBLog(@"SBtap client NULL"); return; }
    uint64_t sid=9223372071603639153ULL;
    for(int phase=1; phase<=2; phase++){
        uint64_t ts=mach_absolute_time();
        int touch=(phase==2)?0:1, range=(phase==2)?0:1;
        void *hand=((void*(*)(CFAllocatorRef,uint64_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,double,double,double,double,double,int,int,uint32_t))fp)(
            kCFAllocatorDefault,ts,3,0,0,2,0,0.0,0.0,0.0,0.0,0.0,0,touch,0);
        if(!hand) continue;
        if(fsi)((void(*)(void*,uint32_t,int64_t))fsi)(hand,4,1);
        if(fsi)((void(*)(void*,uint32_t,int64_t))fsi)(hand,0xB0019,1);
        void *finger=((void*(*)(CFAllocatorRef,uint64_t,uint32_t,uint32_t,uint32_t,uint32_t,double,double,double,double,double,int,int,uint32_t))ff)(
            kCFAllocatorDefault,ts,2,2,3,0,nx,ny,0.0,0.0,0.0,range,touch,0);
        if(finger){
            if(fsf){ void(*SF)(void*,uint32_t,double)=(void(*)(void*,uint32_t,double))fsf;
                SF(finger,0xB0011,1.0); SF(finger,0xB0012,1.0); SF(finger,0xB0013,0.0);
                SF(finger,0xB0014,5.0); SF(finger,0xB0015,5.0); }
            if(fa)((void(*)(void*,void*,uint32_t))fa)(hand,finger,0);
            if(fsi)((void(*)(void*,uint32_t,int64_t))fsi)(finger,0xB0008,range);
            if(fsi)((void(*)(void*,uint32_t,int64_t))fsi)(finger,0xB0009,touch);
            CFRelease(finger);
        }
        if(fss)((void(*)(void*,uint64_t))fss)(hand,sid);
        ((void(*)(void*,void*))hd)(client,hand);
        CFRelease(hand);
        SBLog(@"SBtap phase=%d dispatched", phase);
        usleep(60000);
    }
}

// ---- 序列化事件为字节流，用于原版 vs 我们的二进制对比 ----
static void SBDumpEvent(void *e, const char *tag) {
    void *fcd = Sym(@"IOHIDEventCreateData");
    if (!fcd) { SBLog(@"%s no CreateData sym", tag); return; }
    CFDataRef d = ((CFDataRef (*)(CFAllocatorRef, void *))fcd)(kCFAllocatorDefault, e);
    if (!d) { SBLog(@"%s CreateData NULL", tag); return; }
    CFIndex n = CFDataGetLength(d);
    const UInt8 *b = CFDataGetBytePtr(d);
    NSMutableString *hx = [NSMutableString string];
    CFIndex lim = n > 96 ? 96 : n;
    for (CFIndex i = 0; i < lim; i++) [hx appendFormat:@"%02x", b[i]];
    SBLog(@"DUMP %s len=%ld %@", tag, (long)n, hx);
    CFRelease(d);
}

// hook IOHIDEventSystemClientDispatchEvent，抓出发送方的事件
typedef void (*DispFn)(void *, void *);
static DispFn gOrigDisp = NULL;
static void SBDispHook(void *client, void *event) {
    if (event) SBDumpEvent(event, "SENT");
    if (gOrigDisp) gOrigDisp(client, event);
}

__attribute__((constructor))
static void YKSBProbeInit(void){
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(10.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        // 安装 dispatch hook（用 substrate）
        {
            void *hMS = NULL;
            void *sub = dlopen("/var/jb/usr/lib/libsubstrate.dylib", RTLD_LAZY);
            if (!sub) sub = dlopen("/usr/lib/libsubstrate.dylib", RTLD_LAZY);
            if (sub) hMS = dlsym(sub, "MSHookFunction");
            if (!hMS) {
                void *el = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_LAZY);
                if (el) hMS = dlsym(el, "MSHookFunction");
            }
            void *target = Sym(@"IOHIDEventSystemClientDispatchEvent");
            if (hMS && target) {
                ((void (*)(void *, void *, void **))hMS)(target, (void *)SBDispHook, (void **)&gOrigDisp);
                SBLog(@"dispatch hook installed orig=%p", (void *)gOrigDisp);
            } else {
                SBLog(@"dispatch hook FAILED hMS=%p target=%p", hMS, target);
            }
        }
        SBLog(@"=== SB tap test START ===");
        SBTap(0.384,0.931);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            SBLog(@"=== SB tap test END ===");
        });
    });
}
