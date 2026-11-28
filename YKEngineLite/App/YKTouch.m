static int gYkEpoch = 0;
static void YkTryRecordEvent(void *event);
int gYkClientType = 2;
#include <stdio.h>
#include <stdlib.h>
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

// senderID 必须是真实触摸屏服务的 registry ID，否则 SpringBoard 只把事件
// 收进 HID 系统却不会派发给任何窗口（原版所有注入点都硬编码这一个值）。
#define YK_SENDER_DEFAULT 0x8000000817319371ULL
#define YK_SENDER_FILE    @"/var/mobile/Library/YKEngineLite/sender.txt"

uint64_t gYkSenderID = 0;          // 0/1 = 自动解析；>1 = 指定值
static uint64_t gYkSenderFile = 0; // 持久化缓存
static int gYkUseCaptured = 0;

static uint64_t YkSenderLoad(void) {
    if (gYkSenderFile) return gYkSenderFile;
    NSString *s = [NSString stringWithContentsOfFile:YK_SENDER_FILE
                                            encoding:NSUTF8StringEncoding error:NULL];
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length) {
        unsigned long long v = strtoull(s.UTF8String, NULL, 0);
        if (v > 1) gYkSenderFile = v;
    }
    return gYkSenderFile;
}

static void YkSenderSave(uint64_t v) {
    if (v <= 1 || v == gYkSenderFile) return;
    gYkSenderFile = v;
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/YKEngineLite"
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSString stringWithFormat:@"%llu", (unsigned long long)v]
        writeToFile:YK_SENDER_FILE atomically:YES encoding:NSUTF8StringEncoding error:NULL];
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


// 原版 startTouchHIDEventMonitorIfNeeded：先注册回调，让 client 成为"活跃事件源"
static uint64_t gYkLastRealSender = 0;
static uint32_t gYkLastRealType   = 0;
static uint32_t gYkLastRealMask   = 0;
static uint32_t gYkLastRealIndex  = 0;
static uint32_t gYkLastRealIdent  = 0;
static double   gYkLastRealX = 0, gYkLastRealY = 0;
static volatile int gYkRealCount = 0;

static void YkHIDEventCallback(void *target, void *refcon, void *service, IOHIDEventRef event) {
    (void)target; (void)refcon; (void)service;
    if (!event) return;
    void *ft = YkSym("IOHIDEventGetType");
    void *fg = YkSym("IOHIDEventGetIntegerValue");
    void *ff = YkSym("IOHIDEventGetFloatValue");
    void *fs = YkSym("IOHIDEventGetSenderID");
    if (!ft) return;
    uint32_t t = ((uint32_t (*)(IOHIDEventRef))ft)(event);
    if (t != 11) return;                      // 只要 digitizer
    YkTryRecordEvent(event);

    gYkRealCount++;
    gYkLastRealType = t;
    if (fs) gYkLastRealSender = ((uint64_t (*)(IOHIDEventRef))fs)(event);
    if (fg) {
        gYkLastRealIndex = (uint32_t)((int64_t (*)(IOHIDEventRef, uint32_t))fg)(event, 0xB0005);
        gYkLastRealIdent = (uint32_t)((int64_t (*)(IOHIDEventRef, uint32_t))fg)(event, 0xB0006);
        gYkLastRealMask  = (uint32_t)((int64_t (*)(IOHIDEventRef, uint32_t))fg)(event, 0xB0007);
    }
    if (ff) {
        gYkLastRealX = ((double (*)(IOHIDEventRef, uint32_t))ff)(event, 0xB0000);
        gYkLastRealY = ((double (*)(IOHIDEventRef, uint32_t))ff)(event, 0xB0001);
    }
    fprintf(stderr, "[real] n=%d sender=%llu idx=%u ident=%u mask=%u x=%.1f y=%.1f\n",
            gYkRealCount, (unsigned long long)gYkLastRealSender,
            gYkLastRealIndex, gYkLastRealIdent, gYkLastRealMask,
            gYkLastRealX, gYkLastRealY);
    fflush(stderr);
}

static IOHIDEventSystemClientRef YkHIDClientMain(void) {
    static IOHIDEventSystemClientRef client = NULL;
    static int usedType = -1;
    if (client && usedType == gYkClientType) return client;
    if (client && usedType != gYkClientType) { client = NULL; }
    usedType = gYkClientType;

    void *hc = YkSym("IOHIDEventSystemClientCreate");
    if (hc) client = ((IOHIDEventSystemClientRef (*)(CFAllocatorRef))hc)(kCFAllocatorDefault);
    if (!client) {
        void *h = YkSym("IOHIDEventSystemClientCreateWithType");
        if (h) {
            typedef IOHIDEventSystemClientRef (*T3)(CFAllocatorRef, int, CFDictionaryRef);
            client = ((T3)h)(kCFAllocatorDefault, gYkClientType, NULL);
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

void YkResetClient(void);   // forward

static IOHIDEventSystemClientRef YkHIDClient(void) {
    // 任意线程调用都安全：切到主线程取 client
    if ([NSThread isMainThread]) return YkHIDClientMain();
    __block IOHIDEventSystemClientRef c = NULL;
    dispatch_sync(dispatch_get_main_queue(), ^{ c = YkHIDClientMain(); });
    return c;
}

// 枚举 HID 服务，按 usage 找出触摸屏，返回其 registry ID（= senderID）
static uint64_t YkFindTouchSenderID(void) {
    static uint64_t cached = 0;
    if (cached) return cached;
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
    cached = found;
    return found;
}

// senderID 解析优先级：请求显式值 > 持久化值 > 服务枚举 > 原版硬编码常量
static uint64_t YkResolveSender(void) {
    uint64_t v = gYkSenderID;
    if (v == 1) v = YkFindTouchSenderID();
    if (v <= 1) v = YkSenderLoad();
    if (v <= 1) v = YkFindTouchSenderID();
    if (v <= 1) v = YK_SENDER_DEFAULT;
    YkSenderSave(v);
    return v;
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
    // 原版实测：父事件 mask 恒为 2 (Touch)，range 恒为 0，坐标恒为 0,0
    uint32_t mask = 2;
    int      touch = (phase == 2) ? 0 : 1;   // down=1 up=0
    int      range = 0;   // 原版父事件 range 恒为 0
    double   press = (phase == 2) ? 0.0 : (pressure > 0 ? pressure : 1.0);

    // 父事件：transducerType = 3 (Hand)
    fprintf(stderr, "[touch] step1 before DigitizerEvent\n"); fflush(stderr);
    IOHIDEventRef hand = ((YkDigitizerFn)fp)(kCFAllocatorDefault, ts,
                                             3, 0, 0, mask, 0,
                                             0.0, 0.0, 0.0, press, 0.0, range, touch, 0);
    fprintf(stderr, "[touch] step2 hand=%p\n", (void *)hand); fflush(stderr);
    if (!hand) return;
    // 原版：父事件设递增 epoch（字段 0xb001b）
    {
        void *fsi3 = YkSym("IOHIDEventSetIntegerValue");
        if (fsi3) {
            int ep = ++gYkEpoch;
            ((void (*)(IOHIDEventRef, uint32_t, int64_t))fsi3)(hand, 0xb001b, ep);
            // 原版校验要求：父事件 0xb0004 (DigitizerType) 必须 == 3 (Hand)
            ((void (*)(IOHIDEventRef, uint32_t, int64_t))fsi3)(hand, 0xb0004, 3);
            ((void (*)(IOHIDEventRef, uint32_t, int64_t))fsi3)(hand, 0xb0005, 0);  // index
            ((void (*)(IOHIDEventRef, uint32_t, int64_t))fsi3)(hand, 0xb0006, 0);  // identity
            fprintf(stderr, "[touch] epoch=%d\n", ep); fflush(stderr);
        }
    }

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
    // 原版实测（探针逐字段对比）：
    //   CHILD: mask=3 range=1/0 touch=1/0 idx=2 ident=2 disp=0
    //          x,y 是归一化 0~1（不是像素！） z=0 press=0
    CGSize scr = [UIScreen mainScreen].bounds.size;
    double nx = (scr.width  > 0) ? x / (scr.width  * [UIScreen mainScreen].scale) : x;
    double ny = (scr.height > 0) ? y / (scr.height * [UIScreen mainScreen].scale) : y;
    if (nx > 1.0) nx = 1.0; if (ny > 1.0) ny = 1.0;

    IOHIDEventRef fingerEv = ((YkFingerFn)ff)(kCFAllocatorDefault, ts,
                                              2,            // index
                                              2,            // identity
                                              3,            // mask = Range|Touch
                                              0,
                                              nx, ny,       // 归一化坐标
                                              0.0,          // z = 0
                                              0.0,          // tipPressure = 0
                                              0.0,          // twist
                                              (phase == 2) ? 0 : 1,   // range
                                              touch,        // touch
                                              0);
    if (fingerEv) {
        void *sf = YkSym("IOHIDEventSetFloatValue");
        if (sf) {
            void (*SetF)(IOHIDEventRef, uint32_t, double) = (void (*)(IOHIDEventRef, uint32_t, double))sf;
            SetF(fingerEv, 0xb0011, 1.0);
            SetF(fingerEv, 0xb0012, 1.0);
            SetF(fingerEv, 0xb0013, 0.0);
            SetF(fingerEv, 0xb0014, 5.0);
            SetF(fingerEv, 0xb0015, 5.0);
                SetF(fingerEv, 0xb001a, 1.0);   // QualityRadiiAccuracy
        }
        fprintf(stderr, "[touch] finger nx=%.3f ny=%.3f touch=%d\n", nx, ny, touch); fflush(stderr);
        if (fa) ((YkAppendFn)fa)(hand, fingerEv, 0);
        // append 后用父事件的 range=0 覆盖了子事件，这里补回
        {
            void *fsi2 = YkSym("IOHIDEventSetIntegerValue");
            if (fsi2) {
                int r2 = (phase == 2) ? 0 : 1;
                ((void (*)(IOHIDEventRef, uint32_t, int64_t))fsi2)(fingerEv, 0xB0008, r2);
                ((void (*)(IOHIDEventRef, uint32_t, int64_t))fsi2)(fingerEv, 0xB0009, touch);
                fprintf(stderr, "[touch] child range=%d touch=%d\n", r2, touch); fflush(stderr);

            }
        }
        fprintf(stderr, "[touch] step5 appended\n"); fflush(stderr);
        CFRelease(fingerEv);
    }

    // 原版会补 timestamp + senderID（SpringBoard 靠 senderID 判断事件来源）
    void *fst = YkSym("IOHIDEventSetTimeStamp");
    if (fst) ((void (*)(IOHIDEventRef, uint64_t))fst)(hand, mach_absolute_time());
    uint64_t sid = YkResolveSender();
    {
        void *fss = YkSym("IOHIDEventSetSenderID");
        if (fss) ((void (*)(IOHIDEventRef, uint64_t))fss)(hand, sid);
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
            (void *)YkHIDClient(), (unsigned long long)sid); fflush(stderr);
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
    // 原版实测：只有 down / up 两帧
    YkFingerEvent(1, x, y, 1.0, YkNow());
    usleep(60000);
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

// ---- Home 键：原版 r6TWsk92…/menuLongPress 的等价实现 ----
// IOHIDEventCreateKeyboardEvent(alloc, ts, page=0x0C, usage=0x40, isDown, options)
// page 0x0C / usage 0x40 = Consumer "Menu"，iOS 上等同 Home 键。
static void YkMenuEvent(int down) {
    void *fk = YkSym("IOHIDEventCreateKeyboardEvent");
    if (!fk) { fprintf(stderr, "[touch] no CreateKeyboardEvent\n"); return; }
    typedef IOHIDEventRef (*YkKeyFn)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, int, uint32_t);
    IOHIDEventRef ev = ((YkKeyFn)fk)(kCFAllocatorDefault, mach_absolute_time(),
                                     0x0C, 0x40, down, 0);
    if (!ev) return;
    void *fss = YkSym("IOHIDEventSetSenderID");
    if (fss) ((void (*)(IOHIDEventRef, uint64_t))fss)(ev, YkResolveSender());
    YkSendEvent(ev);
    CFRelease(ev);
}

NSDictionary *YkTouchHome(int count, double hold) {
    NSDictionary *r = YkPortSend(@{ @"action": @"home", @"count": @(count),
                                     @"hold": @(hold) });
    if (r) return @{ @"value": r };
    if (count < 1) count = 1;
    if (hold <= 0) hold = 0.05;
    for (int i = 0; i < count; i++) {
        YkMenuEvent(1);
        usleep((useconds_t)(hold * 1000000));
        YkMenuEvent(0);
        if (i + 1 < count) usleep(150000);   // 原版双击间隔 150 ms
    }
    return @{ @"value": @{ @"action": @"home", @"count": @(count), @"ok": @YES } };
}

NSDictionary *YkTouchDoubleTap(double x, double y, double gapSec) {
    if (gapSec <= 0) gapSec = 0.08;
    YkFingerEvent(1, x, y, 1.0, YkNow());
    usleep(40000);
    YkFingerEvent(2, x, y, 0.0, YkNow());
    usleep((useconds_t)(gapSec * 1000000));
    YkFingerEvent(1, x, y, 1.0, YkNow());
    usleep(40000);
    YkFingerEvent(2, x, y, 0.0, YkNow());
    return @{ @"value": @{ @"action": @"doubleTap", @"x": @(x), @"y": @(y),
                           @"gap": @(gapSec), @"ok": @YES } };
}

// 双指线性捏合：index 1 从 p1→q1，index 2 从 p2→q2
NSDictionary *YkTouchPinch(double x1, double y1, double ex1, double ey1,
                           double x2, double y2, double ex2, double ey2,
                           double durationSec, NSInteger steps)
{
    if (steps <= 0) steps = 12;
    if (durationSec <= 0) durationSec = 0.35;
    useconds_t gap = (useconds_t)(durationSec * 1000000 / steps);

    // 两指按下（同一帧内两个子事件）
    YkInject(1, x1, y1, 1, 1.0);
    YkInject(1, x2, y2, 2, 1.0);
    usleep(gap);
    for (NSInteger i = 1; i <= steps; i++) {
        double t = (double)i / steps;
        YkInject(3, x1 + (ex1 - x1) * t, y1 + (ey1 - y1) * t, 1, 1.0);
        YkInject(3, x2 + (ex2 - x2) * t, y2 + (ey2 - y2) * t, 2, 1.0);
        usleep(gap);
    }
    YkInject(2, ex1, ey1, 1, 0.0);
    YkInject(2, ex2, ey2, 2, 0.0);
    return @{ @"value": @{ @"action": @"pinch", @"steps": @(steps), @"ok": @YES } };
}

// 通用序列：points = [{x,y,touch(0/1),delayMs,finger}]
NSDictionary *YkTouchSequence(NSArray *points, double defaultGapMs) {
    if (![points isKindOfClass:[NSArray class]] || points.count == 0)
        return @{ @"value": @{ @"error": @"empty_sequence" } };
    if (defaultGapMs <= 0) defaultGapMs = 20;

    int fingerDown[4] = {0, 0, 0, 0};
    NSInteger sent = 0;
    for (id raw in points) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *p = raw;
        double x = [p[@"x"] doubleValue], y = [p[@"y"] doubleValue];
        int finger = (int)([p[@"finger"] integerValue]);
        if (finger < 1 || finger > 3) finger = 1;
        int touch = p[@"touch"] ? [p[@"touch"] intValue] : 1;
        int phase;
        if (p[@"type"]) {
            NSString *t = [p[@"type"] description];
            phase = [t isEqualToString:@"down"] ? 1 : ([t isEqualToString:@"up"] ? 2 : 3);
        } else if (touch) {
            phase = fingerDown[finger] ? 3 : 1;
        } else {
            phase = 2;
        }
        fingerDown[finger] = touch;
        YkInject(phase, x, y, (uint32_t)finger, touch ? 1.0 : 0.0);
        sent++;
        double d = p[@"delayMs"] ? [p[@"delayMs"] doubleValue] : defaultGapMs;
        if (d > 0) usleep((useconds_t)(d * 1000));
    }
    for (int f = 1; f <= 3; f++)
        if (fingerDown[f]) YkInject(2, 0, 0, (uint32_t)f, 0.0);
    return @{ @"value": @{ @"action": @"sequence", @"frames": @(sent), @"ok": @YES } };
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

NSDictionary *YkTouchCaptureInfo(void) {
    return @{ @"value": @{
        @"count": @(gYkRealCount),
        @"sender": @(gYkLastRealSender),
        @"index": @(gYkLastRealIndex),
        @"identity": @(gYkLastRealIdent),
        @"mask": @(gYkLastRealMask),
        @"x": @(gYkLastRealX),
        @"y": @(gYkLastRealY) } };
}


#pragma mark - 录制 / 回放（复刻原版 YKEventRecord + YKPointRadius）

static volatile int  gYkRecArmed = 0;
static NSData       *gYkRecBlob  = nil;      // 录制到的真实事件序列化数据
static double        gYkRecX = 0, gYkRecY = 0;

// 在已有 monitor 回调里调用（YkHIDEventCallback 处理 type==11 时）
static void YkTryRecordEvent(void *event) {
    if (!gYkRecArmed || gYkRecBlob) return;
    void *fcd = YkSym("IOHIDEventCreateData");
    void *ff  = YkSym("IOHIDEventGetFloatValue");
    if (!fcd) return;
    CFDataRef d = ((CFDataRef (*)(CFAllocatorRef, IOHIDEventRef))fcd)(kCFAllocatorDefault, event);
    if (!d) return;
    NSData *nd = (__bridge_transfer NSData *)d;
    if (nd.length > 32) {
        gYkRecBlob = nd;
        if (ff) {
            gYkRecX = ((double (*)(IOHIDEventRef, uint32_t))ff)(event, 0xB0000);
            gYkRecY = ((double (*)(IOHIDEventRef, uint32_t))ff)(event, 0xB0001);
        }
        fprintf(stderr, "[touch] RECORDED len=%lu x=%.3f y=%.3f\n",
                (unsigned long)nd.length, gYkRecX, gYkRecY);
        fflush(stderr);
        // 落盘备份
        [nd writeToFile:@"/var/mobile/Media/yk_touch_seed.bin" atomically:YES];
    }
}

void YkHIDBoot(void) {
    // 原版 YKService 在 init 里就创建 client，而不是懒加载
    IOHIDEventSystemClientRef c = YkHIDClient();
    uint64_t sid = YkResolveSender();       // 启动即定下 senderID 并落盘
    fprintf(stderr, "[touch] BOOT client=%p type=%d sender=%llu\n",
            (void *)c, gYkClientType, (unsigned long long)sid);
    fflush(stderr);
}

NSDictionary *YkRecordArm(void) {
    gYkRecBlob = nil;
    gYkRecArmed = 1;
    // 确保 monitor 已注册
    YkHIDClient();
    return @{ @"value": @{ @"armed": @YES } };
}

NSDictionary *YkRecordStatus(void) {
    return @{ @"value": @{ @"armed": @(gYkRecArmed),
                           @"recorded": @(gYkRecBlob != nil),
                           @"len": @(gYkRecBlob.length),
                           @"x": @(gYkRecX), @"y": @(gYkRecY) } };
}

// 回放：反序列化 → 改坐标 → 派发
NSDictionary *YkReplayAtRaw(double x, double y, int raw) {
    NSData *blob = gYkRecBlob;
    if (!blob) blob = [NSData dataWithContentsOfFile:@"/var/mobile/Media/yk_touch_seed.bin"];
    if (!blob) return @{ @"value": @{ @"error": @"no_seed" } };

    void *fw  = YkSym("IOHIDEventCreateWithData");
    void *hdc = YkSym("IOHIDEventSystemClientDispatchEvent");
    void *fsf = YkSym("IOHIDEventSetFloatValue");
    void *fss = YkSym("IOHIDEventSetSenderID");
    if (!fw || !hdc) return @{ @"value": @{ @"error": @"no_sym" } };

    // 归一化
    CGSize scr = [UIScreen mainScreen].bounds.size;
    double sc = [UIScreen mainScreen].scale;
    double nx = x / (scr.width * sc), ny = y / (scr.height * sc);

    IOHIDEventRef ev = ((IOHIDEventRef (*)(CFAllocatorRef, CFDataRef, int, int))fw)(
                        kCFAllocatorDefault, (__bridge CFDataRef)blob, 1, 0);
    if (!ev) return @{ @"value": @{ @"error": @"deserialize_failed" } };

    if (!raw) {
        if (fsf) {
            ((void (*)(IOHIDEventRef, uint32_t, double))fsf)(ev, 0xB0000, nx);
            ((void (*)(IOHIDEventRef, uint32_t, double))fsf)(ev, 0xB0001, ny);
        }
        if (fss && gYkSenderID) ((void (*)(IOHIDEventRef, uint64_t))fss)(ev, gYkSenderID);
    }

    IOHIDEventSystemClientRef cl = YkHIDClient();
    if (cl) ((void (*)(IOHIDEventSystemClientRef, IOHIDEventRef))hdc)(cl, ev);
    CFRelease(ev);
    fprintf(stderr, "[touch] REPLAY len=%lu nx=%.3f ny=%.3f\n",
            (unsigned long)blob.length, nx, ny); fflush(stderr);
    return @{ @"value": @{ @"replayed": @YES, @"len": @(blob.length),
                           @"nx": @(nx), @"ny": @(ny) } };
}
