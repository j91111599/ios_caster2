#import <mach/mach_time.h>
//  YKTouch.m — 触控注入（IOHIDEventSystemClient，私有符号 dlsym）
//
//  依赖：App 已签 platform-application + no-sandbox（本项目已具备）
//  坐标：像素（非磅），与 /touch/tap 一致
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

// 走 SpringBoard tweak 的 CFMessagePort（内核跨进程，不依赖文件路径）
static NSDictionary *YkPortSend(NSDictionary *req) {
    static CFMessagePortRef remote = NULL;
    static BOOL tried = NO;
    if (!tried) { tried = YES; remote = CFMessagePortCreateRemote(kCFAllocatorDefault, CFSTR("com.yk.touch")); }
    if (!remote) return nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:req options:0 error:NULL];
    if (!body) return nil;
    CFDataRef reply = NULL;
    SInt32 st = CFMessagePortSendRequest(remote, 1, (__bridge CFDataRef)body, 2.0, 2.0,
                                         kCFRunLoopDefaultMode, &reply);
    if (st != kCFMessagePortSuccess || !reply) return nil;
    NSDictionary *out = [NSJSONSerialization JSONObjectWithData:(__bridge NSData *)reply options:0 error:NULL];
    CFRelease(reply);
    return [out isKindOfClass:[NSDictionary class]] ? out : nil;
}

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

static IOHIDEventSystemClientRef gHIDClient = NULL;

static void *YkSym(const char *name) {
    static void *h1 = NULL, *h2 = NULL;
    if (!h1) h1 = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!h2) h2 = dlopen("/System/Library/PrivateFrameworks/IOHID.framework/IOHID", RTLD_LAZY);
    void *p = h1 ? dlsym(h1, name) : NULL;
    if (!p && h2) p = dlsym(h2, name);
    return p;
}

static IOHIDEventSystemClientRef YkHIDClient(void) {
    if (gHIDClient) return gHIDClient;
    void *s1 = YkSym("IOHIDEventSystemClientCreateWithType");
    if (s1) gHIDClient = ((IOHIDEventSystemClientRef (*)(int))s1)(2);
    if (!gHIDClient) {
        void *s2 = YkSym("IOHIDEventSystemClientCreate");
        if (s2) gHIDClient = ((IOHIDEventSystemClientRef (*)(CFAllocatorRef))s2)(kCFAllocatorDefault);
    }
    return gHIDClient;
}

static void YkSendEvent(IOHIDEventRef ev) {
    void *d = YkSym("IOHIDEventSystemClientDispatchEvent");
    if (d && YkHIDClient() && ev)
        ((void (*)(IOHIDEventSystemClientRef, IOHIDEventRef))d)(YkHIDClient(), ev);
}

// IOHIDEventCreateDigitizerEvent(alloc, time, type, index, identity, eventMask,
//     buttonMask, x, y, z, tipPressure, barrelPressure, range, touch, options)
typedef IOHIDEventRef (*YkDigitizerFn)(CFAllocatorRef, uint64_t, uint32_t, uint32_t,
                                       uint32_t, uint32_t, uint32_t, double, double,
                                       double, double, double, int, int, uint32_t);

// IOHIDEventCreateDigitizerFingerEvent(alloc, time, index, identity, eventMask,
//     buttonMask, x, y, z, tipPressure, twist, range, touch, options)
typedef IOHIDEventRef (*YkFingerFn)(CFAllocatorRef, uint64_t, uint32_t, uint32_t,
                                    uint32_t, uint32_t, double, double, double,
                                    double, double, int, int, uint32_t);

typedef void (*YkAppendFn)(IOHIDEventRef, IOHIDEventRef, uint32_t);

// 标准三段式：父 digitizer 事件 + 手指子事件 + 显示集成标记
static void YkInject(int phase, double x, double y, uint32_t finger, double pressure) {
    void *fp = YkSym("IOHIDEventCreateDigitizerEvent");
    void *ff = YkSym("IOHIDEventCreateDigitizerFingerEvent");
    void *fa = YkSym("IOHIDEventAppendEvent");
    if (!fp || !ff) return;

    uint64_t ts = mach_absolute_time();
    uint32_t mask  = 3;                        // Range | Touch
    int      touch = (phase == 2) ? 0 : 1;
    double   press = (phase == 2) ? 0.0 : (pressure > 0 ? pressure : 1.0);

    // 父事件：transducerType = 3 (Hand)
    IOHIDEventRef hand = ((YkDigitizerFn)fp)(kCFAllocatorDefault, ts,
                                             3, 0, 0, mask, 0,
                                             x, y, 0.0, press, 0.0, 1, touch, 0);
    if (!hand) return;

    IOHIDEventRef fingerEv = ((YkFingerFn)ff)(kCFAllocatorDefault, ts,
                                              finger, finger, mask, 0,
                                              x, y, 0.0, press, 0.0, 1, touch, 0);
    if (fingerEv) {
        if (fa) ((YkAppendFn)fa)(hand, fingerEv, 0);
        CFRelease(fingerEv);
    }

    YkSendEvent(hand);
    CFRelease(hand);
}

static void YkFingerEvent(int phase, double x, double y, double pressure, uint64_t ts) {
    (void)ts;
    YkInject(phase, x, y, 1, pressure);
}

static void YkTwoFingerEvent(int phase, double x1, double y1, double x2, double y2, uint64_t ts) {
    (void)ts;
    YkInject(phase, x1, y1, 1, 1.0);
    YkInject(phase, x2, y2, 2, 1.0);
}

static uint64_t YkNow(void) {
    return mach_absolute_time();
}

NSDictionary *YkTouchTap(double x, double y) {
    NSDictionary *r = YkPortSend(@{ @"action": @"tap", @"x": @(x), @"y": @(y) });
    if (r) return @{ @"value": r };
    YkFingerEvent(1, x, y, 1.0, YkNow());
    usleep(30000);
    YkFingerEvent(2, x, y, 0.0, YkNow());
    return @{ @"value": @{ @"action": @"tap", @"x": @(x), @"y": @(y), @"sent": @(YkHIDClient() != NULL) } };
}

NSDictionary *YkTouchLongPress(double x, double y, double durationSec) {
    NSDictionary *r = YkPortSend(@{ @"action": @"longPress", @"x": @(x), @"y": @(y), @"duration": @(durationSec) });
    if (r) return @{ @"value": r };
    YkFingerEvent(1, x, y, 1.0, YkNow());
    usleep((useconds_t)(durationSec * 1000000));
    YkFingerEvent(2, x, y, 0.0, YkNow());
    return @{ @"value": @{ @"action": @"longPress", @"x": @(x), @"y": @(y),
                           @"duration": @(durationSec), @"sent": @(YkHIDClient() != NULL) } };
}

NSDictionary *YkTouchSwipe(double x1, double y1, double x2, double y2,
                           double durationSec, NSInteger steps)
{
    if (steps <= 0) steps = 12;
    NSDictionary *r = YkPortSend(@{ @"action": @"swipe", @"x": @(x1), @"y": @(y1),
                                      @"toX": @(x2), @"toY": @(y2),
                                      @"duration": @(durationSec), @"steps": @(steps) });
    if (r) return @{ @"value": r };
    YkFingerEvent(1, x1, y1, 1.0, YkNow());
    useconds_t gap = (useconds_t)(durationSec * 1000000 / steps);
    for (NSInteger i = 1; i <= steps; i++) {
        double t = (double)i / steps;
        double cx = x1 + (x2 - x1) * t;
        double cy = y1 + (y2 - y1) * t;
        YkFingerEvent(3, cx, cy, 1.0, YkNow());
        usleep(gap);
    }
    YkFingerEvent(2, x2, y2, 0.0, YkNow());
    return @{ @"value": @{ @"action": @"swipe", @"from": @[ @(x1), @(y1) ],
                           @"to": @[ @(x2), @(y2) ], @"steps": @(steps),
                           @"sent": @(YkHIDClient() != NULL) } };
}

NSDictionary *YkTouchMulti(int fingers, double x1, double y1, double x2, double y2,
                           double durationSec)
{
    if (fingers < 2) return YkTouchTap(x1, y1);
    NSDictionary *rs = YkPortSend(@{ @"action": @"multi", @"x": @(x1), @"y": @(y1),
                                       @"x2": @(x2), @"y2": @(y2), @"duration": @(durationSec) });
    if (rs) return @{ @"value": rs };
    YkTwoFingerEvent(1, x1, y1, x2, y2, YkNow());
    usleep((useconds_t)(durationSec * 1000000));
    YkTwoFingerEvent(2, x1, y1, x2, y2, YkNow());
    return @{ @"value": @{ @"action": @"multi", @"fingers": @(fingers),
                           @"points": @[ @[ @(x1), @(y1) ], @[ @(x2), @(y2) ] ],
                           @"sent": @(YkHIDClient() != NULL) } };
}

NSDictionary *YkTouchPing(void) {
    NSDictionary *r = YkPortSend(@{ @"action": @"ping" });
    if (r) return @{ @"value": r };
    return @{ @"value": @{ @"ok": @NO, @"reason": @"socket 不可用（tweak 未加载）" } };
}
