//  YKSBProbe.m — 在 SpringBoard 进程内注册 HID monitor + hook sendEvent:
//  两个观测点，互相校准：
//    A) HID monitor  → 事件有没有跨进程到达 SpringBoard 的 HID 客户端
//    B) sendEvent:   → 事件有没有变成 UIEvent
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static void SBLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[%.3f] %@\n",
                      [[NSDate date] timeIntervalSince1970], msg];
    NSString *path = @"/var/mobile/Media/sbprobe.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]; return; }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

static void *Sym(NSString *name) {
    static void *qc = NULL;
    if (!qc) qc = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    void *p = qc ? dlsym(qc, name.UTF8String) : NULL;
    if (!p) {
        static void *hid = NULL;
        if (!hid) hid = dlopen("/System/Library/PrivateFrameworks/IOHID.framework/IOHID", RTLD_LAZY);
        if (hid) p = dlsym(hid, name.UTF8String);
    }
    return p;
}

// A) HID monitor
static void SBMHIDCallback(void *target, void *refcon, void *service, void *event) {
    if (!event) return;
    void *ft = Sym(@"IOHIDEventGetType");
    uint32_t t = ft ? ((uint32_t (*)(void *))ft)(event) : 0;
    void *fs = Sym(@"IOHIDEventGetSenderID");
    uint64_t sid = fs ? ((uint64_t (*)(void *))fs)(event) : 0;
    SBLog(@"HIDMON type=%u sender=%llu", t, (unsigned long long)sid);
    (void)target; (void)refcon; (void)service;
}

// B) sendEvent
typedef void (*SendEventFn)(id, SEL, UIEvent *);
static SendEventFn gOrigSendEvent = NULL;
static void YKSendEventHook(id self, SEL _cmd, UIEvent *event) {
    @autoreleasepool {
        NSSet *touches = nil;
        @try { touches = [event allTouches]; } @catch (__unused NSException *e) { }
        if (touches.count > 0) {
            NSMutableString *d = [NSMutableString string];
            for (UITouch *t in touches)
                [d appendFormat:@"[p=%ld] ", (long)t.phase];
            SBLog(@"SENDEVENT touches=%lu %@", (unsigned long)touches.count, d);
        }
    }
    if (gOrigSendEvent) gOrigSendEvent(self, _cmd, event);
}

__attribute__((constructor))
static void YKSBProbeInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        void *hc = Sym(@"IOHIDEventSystemClientCreate");
        if (hc) {
            void *cl = ((void *(*)(CFAllocatorRef))hc)(kCFAllocatorDefault);
            if (cl) {
                void *hr = Sym(@"IOHIDEventSystemClientRegisterEventCallback");
                if (hr) ((void (*)(void *, void *, void *, uint32_t))hr)(cl, (void *)SBMHIDCallback, NULL, 0);
                void *hs = Sym(@"IOHIDEventSystemClientScheduleWithRunLoop");
                if (hs) ((void (*)(void *, CFRunLoopRef, CFStringRef))hs)(cl, CFRunLoopGetMain(), kCFRunLoopCommonModes);
                SBLog(@"hidmon client=%p", cl);
            } else SBLog(@"hidmon client=NULL");
        } else SBLog(@"hidmon no Create sym");

        @try {
            Method m = class_getInstanceMethod([UIApplication class], @selector(sendEvent:));
            if (m) {
                gOrigSendEvent = (SendEventFn)method_getImplementation(m);
                method_setImplementation(m, (IMP)YKSendEventHook);
                SBLog(@"hook sendEvent: OK");
            } else SBLog(@"sendEvent: not found");
        } @catch (NSException *e) { SBLog(@"hook fail %@", e); }
    });
}
