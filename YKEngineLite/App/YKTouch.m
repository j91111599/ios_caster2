#include <stdio.h>
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

uint64_t gYkSenderID = 0;



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


// 原版 startTouchHIDEventMonitorIfNeeded：先注册回调，让 client 成为"活跃事件源"
static uint64_t gYkLastRealSender = 0;
static void YkHIDEventCallback(void *target, void *refcon, void *service, IOHIDEventRef event) {
    // 目的不是处理事件，而是让 client 保持订阅状态
    (void)target; (void)service;
    if (event) {
        void *fg = YkSym("IOHIDEventGetSenderID");
        if (fg) {
            uint64_t sid = ((uint64_t (*)(IOHIDEventRef))fg)(event);
            if (sid) gYkLastRealSender = sid;
        }
    }
    (void)refcon;
}

static IOHIDEventSystemClientRef YkHIDClientMain(void) {
    // 必须只在主线程调用：client 要绑到主 runloop，否则 Dispatch 会被静默丢弃
    static IOHIDEventSystemClientRef client = NULL;
    if (client) return client;

    void *hc = YkSym("IOHIDEventSystemClientCreate");
    if (hc) client = ((IOHIDEventSystemClientRef (*)(CFAllocatorRef))hc)(kCFAllocatorDefault);
    if (!client) {
        void *h = YkSym("IOHIDEventSystemClientCreateWithType");
        if (h) {
            typedef IOHIDEventSystemClientRef (*T3)(CFAllocatorRef, int, CFDictionaryRef);
            client = ((T3)h)(kCFAllocatorDefault, 2, NULL);
        }
    }
    if (client) {
        // 原版：先 RegisterEventCallback，再 Schedule(CommonModes)
        void *hr = YkSym("IOHIDEventSystemClientRegisterEventCallback");
        if (hr) {
            ((void (*)(IOHIDEventSystemClientRef, void *, void *, uint32_t))hr)(
                        client, (void *)YkHIDEventCallback, NULL, 0);
            fprintf(stderr, "[touch] RegisterEventCallback done\n"); fflush(stderr);
        }
        void *hs = YkSym("IOHIDEventSystemClientScheduleWithRunLoop");
        if (hs) ((void (*)(IOHIDEventSystemClientRef, CFRunLoopRef, CFStringRef))hs)(
                    client, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        fprintf(stderr, "[touch] client(main)=%p\n", (void *)client); fflush(stderr);
    } else {
        fprintf(stderr, "[touch] client=NULL\n"); fflush(stderr);
    }
    return client;
}

static IOHIDEventSystemClientRef YkHIDClient(void) {
    // 任意线程调用都安全：切到主线程取 client
    if ([NSThread isMainThread]) return YkHIDClientMain();
    __block IOHIDEventSystemClientRef c = NULL;
    dispatch_sync(dispatch_get_main_queue(), ^{ c = YkHIDClientMain(); });
    return c;
}

// 枚举 HID 服务，按 usage 找出触摸屏，返回其 registry ID（= senderID）
static uint64_t YkFindTouchSenderID(void) {
    void *fc = YkSym("IOHIDEventSystemClientCopyServices");
    void *fr = YkSym("IOHIDServiceClientGetRegistryID");
    void *fp = YkSym("IOHIDServiceClientCopyProperty");
    if (!fc || !fr || !fp) { fprintf(stderr, "[touch] missing sym\n"); return 0; }

    IOHIDEventSystemClientRef cl = YkHIDClient();
    if (!cl) return 0;

    CFArrayRef svcs = ((CFArrayRef (*)(IOHIDEventSystemClientRef))fc)(cl);
    if (!svcs) { fprintf(stderr, "[touch] CopyServices NULL\n"); return 0; }

    CFIndex n = CFArrayGetCount(svcs);
    fprintf(stderr, "[touch] services=%ld\n", (long)n); fflush(stderr);

    uint64_t found = 0;
    for (CFIndex i = 0; i < n; i++) {
        void *svc = (void *)CFArrayGetValueAtIndex(svcs, i);
        if (!svc) continue;

        int page = -1, usage = -1;
        CFTypeRef up = ((CFTypeRef (*)(void *, CFStringRef))fp)(svc, CFSTR("PrimaryUsagePage"));
        CFTypeRef us = ((CFTypeRef (*)(void *, CFStringRef))fp)(svc, CFSTR("PrimaryUsage"));
        if (up) { CFNumberGetValue(up, kCFNumberIntType, &page);  CFRelease(up); }
        if (us) { CFNumberGetValue(us, kCFNumberIntType, &usage); CFRelease(us); }

        // 只看 digitizer 类
        if (page == 0x0D) {
            uint64_t rid = ((uint64_t (*)(void *))fr)(svc);
            fprintf(stderr, "[touch] DIGITIZER svc[%ld] page=%d usage=%d rid=%llu\n",
                    (long)i, page, usage, (unsigned long long)rid);
            fflush(stderr);
            if (!found) found = rid;
        }
    }
    CFRelease(svcs);
    fprintf(stderr, "[touch] picked sender=%llu\n", (unsigned long long)found); fflush(stderr);
    return found;
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
    // 原版 eventMaskFromEventInfo：按 phase 返回 0~4
    //   began->3(Range|Touch)  moved->4(Position)  ended->0
    uint32_t mask;
    if (phase == 1)      mask = 3;   // began
    else if (phase == 3) mask = 4;   // moved
    else                 mask = 0;   // up / 其他
    int      touch = (phase == 2) ? 0 : 1;
    double   press = (phase == 2) ? 0.0 : (pressure > 0 ? pressure : 1.0);

    // 父事件：transducerType = 3 (Hand)
    fprintf(stderr, "[touch] step1 before DigitizerEvent\n"); fflush(stderr);
    IOHIDEventRef hand = ((YkDigitizerFn)fp)(kCFAllocatorDefault, ts,
                                             3, 0, 0, mask, 0,
                                             x, y, 0.0, press, 0.0, 1, touch, 0);
    fprintf(stderr, "[touch] step2 hand=%p\n", (void *)hand); fflush(stderr);
    if (!hand) return;
    // 原版：hand 事件必须设置字段 4 = 1（键盘事件同样设置）
    {
        void *fsi = YkSym("IOHIDEventSetIntegerValue");
        if (fsi) {
            ((void (*)(IOHIDEventRef, uint32_t, int64_t))fsi)(hand, 4, 1);
            fprintf(stderr, "[touch] set field4\n"); fflush(stderr);
        }
    }


    fprintf(stderr, "[touch] step3 before FingerEvent\n"); fflush(stderr);
    // 完全对齐原版 YKPointRadius.m 的写法：
//   index = 0, z = y, 并在 AppendEvent 之前补齐 5 个物理属性
    IOHIDEventRef fingerEv = ((YkFingerFn)ff)(kCFAllocatorDefault, ts,
                                              0,            // index  ← 原版固定 0
                                              1,            // identity
                                              mask, 0,
                                              x, y,
                                              y,            // z       ← 原版用 y
                                              press, 0.0, 1, touch, 0);
    if (fingerEv) {
        void *sf = YkSym("IOHIDEventSetFloatValue");
        if (sf) {
            void (*SetF)(IOHIDEventRef, uint32_t, double) = (void (*)(IOHIDEventRef, uint32_t, double))sf;
            SetF(fingerEv, 0xb0011, 1.0);   // Quality
            SetF(fingerEv, 0xb0012, 1.0);   // Density
            SetF(fingerEv, 0xb0013, 0.0);   // Irregularity
            SetF(fingerEv, 0xb0014, 5.0);   // MajorRadius
            SetF(fingerEv, 0xb0015, 5.0);   // MinorRadius
            fprintf(stderr, "[touch] finger physics set\n"); fflush(stderr);
        }
        if (fa) ((YkAppendFn)fa)(hand, fingerEv, 0);
        fprintf(stderr, "[touch] step5 appended\n"); fflush(stderr);
        CFRelease(fingerEv);
    }

    // 原版会补 timestamp + senderID（SpringBoard 靠 senderID 判断事件来源）
    void *fst = YkSym("IOHIDEventSetTimeStamp");
    if (fst) ((void (*)(IOHIDEventRef, uint64_t))fst)(hand, mach_absolute_time());
    if (gYkSenderID == 1) gYkSenderID = YkFindTouchSenderID();   // 1 = 自动探测
    if (gYkSenderID && gYkSenderID != 1) {
        void *fsi = YkSym("IOHIDEventSetSenderID");
        if (fsi) ((void (*)(IOHIDEventRef, uint64_t))fsi)(hand, gYkSenderID);
    }
    // 标记为显示集成设备（坐标才映射到屏幕）——原版同样设置
    {
        void *fsv = YkSym("IOHIDEventSetIntegerValue");
        if (fsv) {
            ((void (*)(IOHIDEventRef, uint32_t, int64_t))fsv)(hand, 0x000B0019, 1);
            fprintf(stderr, "[touch] set IsDisplayIntegrated\n"); fflush(stderr);
        }
    }

    fprintf(stderr, "[touch] step5b dispatch client=%p sender=%llu\n",
            (void *)YkHIDClient(), (unsigned long long)gYkSenderID); fflush(stderr);
    if ([NSThread isMainThread]) {
        YkSendEvent(hand);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            YkSendEvent(hand);
            CFRelease(hand);
        });
        fprintf(stderr, "[touch] step6 dispatched(main async)\n"); fflush(stderr);
        return;
    }
    fprintf(stderr, "[touch] step6 dispatched\n"); fflush(stderr);
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
    // 原版序列：began -> moved(位置微移) -> ended
    YkFingerEvent(1, x,        y,        1.0, YkNow());
    usleep(20000);
    YkFingerEvent(3, x + 0.5,  y + 0.5,  1.0, YkNow());
    usleep(20000);
    YkFingerEvent(2, x + 0.5,  y + 0.5,  0.0, YkNow());
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


#pragma mark - 闭环自检：Monitor client 能否收到自己派发的事件

static volatile int gYkMonCount = 0;
static volatile double gYkMonX = -1, gYkMonY = -1;

static void YkMonCallback(void *target, void *refcon, void *service, IOHIDEventRef event) {
    if (!event) return;
    gYkMonCount++;
    void *ft = YkSym("IOHIDEventGetType");
    if (ft) {
        uint32_t t = ((uint32_t (*)(IOHIDEventRef))ft)(event);
        if (t == 11) {   // kIOHIDEventTypeDigitizer
            void *fg = YkSym("IOHIDEventGetFloatValue");
            if (fg) {
                gYkMonX = ((double (*)(IOHIDEventRef, uint32_t))fg)(event, 0xB0000);
                gYkMonY = ((double (*)(IOHIDEventRef, uint32_t))fg)(event, 0xB0001);
            }
            fprintf(stderr, "[loopback] MONITOR GOT digitizer count=%d x=%.1f y=%.1f\n",
                    gYkMonCount, gYkMonX, gYkMonY); fflush(stderr);
        }
    }
    (void)target; (void)refcon; (void)service;
}

static IOHIDEventSystemClientRef gYkMon = NULL;

NSDictionary *YkLoopbackTest(double x, double y) {
    // 1) 建 Monitor client
    if (!gYkMon) {
        void *hc = YkSym("IOHIDEventSystemClientCreateWithType");
        if (hc) {
            gYkMon = ((IOHIDEventSystemClientRef (*)(CFAllocatorRef, int, CFDictionaryRef))hc)(
                        kCFAllocatorDefault, 1 /*Monitor*/, NULL);
        }
        if (gYkMon) {
            void *hr = YkSym("IOHIDEventSystemClientRegisterEventCallback");
            if (hr) ((void (*)(IOHIDEventSystemClientRef, void *, void *, uint32_t))hr)(
                        gYkMon, (void *)YkMonCallback, NULL, 0);
            void *hs = YkSym("IOHIDEventSystemClientScheduleWithRunLoop");
            if (hs) ((void (*)(IOHIDEventSystemClientRef, CFRunLoopRef, CFStringRef))hs)(
                        gYkMon, CFRunLoopGetMain(), kCFRunLoopCommonModes);
            fprintf(stderr, "[loopback] monitor ready %p\n", (void *)gYkMon); fflush(stderr);
        } else {
            fprintf(stderr, "[loopback] monitor create FAILED\n"); fflush(stderr);
        }
    }

    gYkMonCount = 0; gYkMonX = -1; gYkMonY = -1;

    // 2) 用 Inject client 派发
    YkInject(1, x, y, 1, 1.0);       // began
    usleep(150000);
    int afterDown = gYkMonCount;

    // 3) 等待 monitor 回调
    for (int i = 0; i < 20; i++) {
        if (gYkMonCount > 0) break;
        usleep(50000);
    }

    return @{ @"value": @{
        @"monitorReady": @(gYkMon != NULL),
        @"afterDown": @(afterDown),
        @"received": @(gYkMonCount),
        @"monX": @(gYkMonX),
        @"monY": @(gYkMonY),
        @"sentX": @(x), @"sentY": @(y) } };
}
