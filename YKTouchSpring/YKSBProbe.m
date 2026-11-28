//  YKSBProbe.m — SpringBoard 侧三层观测
//   A) HID monitor        → 事件是否到达 SpringBoard 的 HID 层
//   B) _handleHIDEvent:   → SpringBoard 是否处理 HID 事件
//   C) UIWindow sendEvent:→ 是否变成 UIEvent
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

static void *Sym(NSString *n) {
    static void *qc = NULL;
    if (!qc) qc = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    void *p = qc ? dlsym(qc, n.UTF8String) : NULL;
    if (!p) {
        static void *hid = NULL;
        if (!hid) hid = dlopen("/System/Library/PrivateFrameworks/IOHID.framework/IOHID", RTLD_LAZY);
        if (hid) p = dlsym(hid, n.UTF8String);
    }
    return p;
}

static void SBMHIDCallback(void *tt, void *r, void *s, void *e) {
    if (!e) return;
    void *ft = Sym(@"IOHIDEventGetType");
    uint32_t ty = ft ? ((uint32_t (*)(void *))ft)(e) : 0;
    if (ty == 11) {
        void *fs  = Sym(@"IOHIDEventGetSenderID");
        void *fi  = Sym(@"IOHIDEventGetIntegerValue");
        void *ff2 = Sym(@"IOHIDEventGetFloatValue");
        uint64_t sid = fs ? ((uint64_t (*)(void *))fs)(e) : 0;
        long mask = 0, rng = 0, tch = 0, idx = 0, ident = 0, disp = 0;
        double x = 0, y = 0;
        if (fi) {
            mask  = (long)((int64_t (*)(void *, uint32_t))fi)(e, 0xB0007);
            rng   = (long)((int64_t (*)(void *, uint32_t))fi)(e, 0xB0008);
            tch   = (long)((int64_t (*)(void *, uint32_t))fi)(e, 0xB0009);
            idx   = (long)((int64_t (*)(void *, uint32_t))fi)(e, 0xB0005);
            ident = (long)((int64_t (*)(void *, uint32_t))fi)(e, 0xB0006);
            disp  = (long)((int64_t (*)(void *, uint32_t))fi)(e, 0xB0019);
        }
        if (ff2) {
            x = ((double (*)(void *, uint32_t))ff2)(e, 0xB0000);
            y = ((double (*)(void *, uint32_t))ff2)(e, 0xB0001);
        }
        SBLog(@"HIDMON t11 sid=%llu mask=%ld range=%ld touch=%ld idx=%ld ident=%ld disp=%ld x=%.1f y=%.1f",
              (unsigned long long)sid, mask, rng, tch, idx, ident, disp, x, y);

        // 打印子事件（finger）字段
        void *fc2 = Sym(@"IOHIDEventGetChildren");
        if (fc2) {
            CFArrayRef kids = ((CFArrayRef (*)(void *))fc2)(e);
            if (kids) {
                CFIndex kn = CFArrayGetCount(kids);
                for (CFIndex ki = 0; ki < kn; ki++) {
                    void *k = (void *)CFArrayGetValueAtIndex(kids, ki);
                    long km = 0, kr = 0, kt = 0, kix = 0, kid2 = 0, kd = 0, kty = 0;
                    double kx = 0, ky = 0, kz = 0, kp = 0;
                    if (fi) {
                        km  = (long)((int64_t (*)(void *, uint32_t))fi)(k, 0xB0007);
                        kr  = (long)((int64_t (*)(void *, uint32_t))fi)(k, 0xB0008);
                        kt  = (long)((int64_t (*)(void *, uint32_t))fi)(k, 0xB0009);
                        kix = (long)((int64_t (*)(void *, uint32_t))fi)(k, 0xB0005);
                        kid2= (long)((int64_t (*)(void *, uint32_t))fi)(k, 0xB0006);
                        kd  = (long)((int64_t (*)(void *, uint32_t))fi)(k, 0xB0019);
                        kty = (long)((int64_t (*)(void *, uint32_t))fi)(k, 0xB0004);
                    }
                    if (ff2) {
                        kx = ((double (*)(void *, uint32_t))ff2)(k, 0xB0000);
                        ky = ((double (*)(void *, uint32_t))ff2)(k, 0xB0001);
                        kz = ((double (*)(void *, uint32_t))ff2)(k, 0xB0002);
                        kp = ((double (*)(void *, uint32_t))ff2)(k, 0xB000A);
                    }
                    SBLog(@"  CHILD[%ld] type=%ld mask=%ld range=%ld touch=%ld idx=%ld ident=%ld disp=%ld x=%.1f y=%.1f z=%.1f press=%.1f",
                          (long)ki, kty, km, kr, kt, kix, kid2, kd, kx, ky, kz, kp);
                }
            }
        }
    }
    (void)tt; (void)r; (void)s;
}

typedef void (*GenericFn)(id, SEL, id);
static GenericFn gOrigHandleHID = NULL;
static void YKHandleHID(id self, SEL _cmd, id ev) {
    SBLog(@"HANDLEHID %@ -> %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    if (gOrigHandleHID) gOrigHandleHID(self, _cmd, ev);
}

static GenericFn gOrigWinSend = NULL;

// 用 NSInvocation 调 -locationInWindow:（返回 CGPoint，不能走 performSelector）
static CGPoint YKLocInWindow(UITouch *t) {
    CGPoint p = CGPointZero;
    SEL sel = NSSelectorFromString(@"locationInWindow");
    if (![t respondsToSelector:sel]) return p;
    NSMethodSignature *sig = [t methodSignatureForSelector:sel];
    if (!sig) return p;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:t];
    [inv setSelector:sel];
    [inv invoke];
    if (sig.methodReturnLength == sizeof(CGPoint)) [inv getReturnValue:&p];
    return p;
}

static void YKWinSend(id self, SEL _cmd, id ev) {
    @autoreleasepool {
        id touches = nil;
        @try { touches = [ev allTouches]; } @catch (__unused NSException *x) { }
        NSUInteger n = 0;
        if ([touches respondsToSelector:@selector(count)]) n = [(NSSet *)touches count];
        if (n) {
            NSMutableString *d = [NSMutableString string];
            for (UITouch *t in (NSSet *)touches) {
                CGPoint p = YKLocInWindow(t);
                [d appendFormat:@"[p=%ld x=%.1f y=%.1f] ", (long)t.phase, p.x, p.y];
            }
            SBLog(@"WINSEND n=%lu %@", (unsigned long)n, d);
        }
    }
    if (gOrigWinSend) gOrigWinSend(self, _cmd, ev);
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
                SBLog(@"probe A ok");
            }
        }

        NSArray *clsNames = @[@"UIApplication", @"UIWindow", @"SBApplication",
                              @"SpringBoard", @"SBMainWorkspace", @"SBHIDEventProcessor"];
        for (NSString *cn in clsNames) {
            Class c = NSClassFromString(cn);
            if (!c) continue;
            unsigned int n = 0;
            Method *ms = class_copyMethodList(c, &n);
            for (unsigned int i = 0; i < n; i++) {
                NSString *sel = NSStringFromSelector(method_getName(ms[i]));
                NSString *low = sel.lowercaseString;
                if ([low containsString:@"hid"]) {
                    SBLog(@"FOUND %@ -> %@", cn, sel);
                    if ([sel hasPrefix:@"_handleHIDEvent"] || [sel hasPrefix:@"handleHIDEvent"]) {
                        gOrigHandleHID = (GenericFn)method_getImplementation(ms[i]);
                        method_setImplementation(ms[i], (IMP)YKHandleHID);
                        SBLog(@"HOOKED %@", sel);
                    }
                }
            }
            if (ms) free(ms);
        }

        @try {
            Method m = class_getInstanceMethod([UIWindow class], @selector(sendEvent:));
            if (m) {
                gOrigWinSend = (GenericFn)method_getImplementation(m);
                method_setImplementation(m, (IMP)YKWinSend);
                SBLog(@"probe C ok");
            }
        } @catch (__unused NSException *x) { }
    });
}
