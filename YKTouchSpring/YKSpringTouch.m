//  YKSpringTouch.m — 注入 SpringBoard 的触控注入模块
//
//  原理：SpringBoard 进程持有 hid 服务权限，可创建 inject 类型 client，
//        从而把 digitizer 事件真正送进系统事件流。
//  通信：UNIX domain socket /var/tmp/yktouch.sock（App 已 no-sandbox，可连）
//  协议：一行 JSON 请求 → 一行 JSON 响应
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <string.h>
#import <sys/un.h>
#import <unistd.h>
#import <dlfcn.h>
#import <pthread.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

static IOHIDEventSystemClientRef gClient = NULL;
static void *gIOKit = NULL;

static void *YkSym(const char *n) {
    if (!gIOKit) gIOKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    void *p = gIOKit ? dlsym(gIOKit, n) : NULL;
    if (!p) {
        static void *hid = NULL;
        if (!hid) hid = dlopen("/System/Library/PrivateFrameworks/IOHID.framework/IOHID", RTLD_LAZY);
        if (hid) p = dlsym(hid, n);
    }
    return p;
}

static IOHIDEventSystemClientRef YkClient(void) {
    if (gClient) return gClient;
    // type 2 = kIOHIDEventSystemClientTypeInject
    typedef IOHIDEventSystemClientRef (*CreateWithTypeFn)(int);
    CreateWithTypeFn cwt = (CreateWithTypeFn)YkSym("IOHIDEventSystemClientCreateWithType");
    if (cwt) gClient = cwt(2);
    if (!gClient) {
        typedef IOHIDEventSystemClientRef (*CreateFn)(CFAllocatorRef);
        CreateFn c = (CreateFn)YkSym("IOHIDEventSystemClientCreate");
        if (c) gClient = c(kCFAllocatorDefault);
    }
    return gClient;
}

static void YkDispatch(IOHIDEventRef ev) {
    typedef void (*DispatchFn)(IOHIDEventSystemClientRef, IOHIDEventRef);
    DispatchFn d = (DispatchFn)YkSym("IOHIDEventSystemClientDispatchEvent");
    if (d && YkClient() && ev) d(YkClient(), ev);
}

static uint64_t YkNow(void) {
    return (uint64_t)([[NSProcessInfo processInfo] systemUptime] * 1000000000ULL);
}

// phase: 1=down 2=up 3=move
static void YkFinger(int phase, double x, double y, int finger, double pressure) {
    typedef IOHIDEventRef (*FingerFn)(CFAllocatorRef, IOHIDEventRef, double, double,
                                      uint32_t, uint32_t, uint32_t, uint32_t, uint32_t,
                                      double, double, double, double, uint32_t);
    FingerFn fn = (FingerFn)YkSym("IOHIDEventCreateDigitizerFingerEvent");
    if (!fn) return;
    IOHIDEventRef ev = fn(kCFAllocatorDefault, NULL, YkNow(), x, y,
                          1, 1, (uint32_t)phase, (uint32_t)finger,
                          pressure, 1.0, 0.0, 0.0, 0);
    if (ev) { YkDispatch(ev); CFRelease(ev); }
}

static void DoTap(double x, double y) {
    YkFinger(1, x, y, 1, 1.0);
    usleep(40000);
    YkFinger(2, x, y, 1, 0.0);
}
static void DoLongPress(double x, double y, double dur) {
    YkFinger(1, x, y, 1, 1.0);
    usleep((useconds_t)(dur * 1000000));
    YkFinger(2, x, y, 1, 0.0);
}
static void DoSwipe(double x1, double y1, double x2, double y2, double dur, int steps) {
    if (steps <= 0) steps = 12;
    YkFinger(1, x1, y1, 1, 1.0);
    useconds_t gap = (useconds_t)(dur * 1000000 / steps);
    for (int i = 1; i <= steps; i++) {
        double t = (double)i / steps;
        YkFinger(3, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, 1, 1.0);
        usleep(gap);
    }
    YkFinger(2, x2, y2, 1, 0.0);
}
static void DoMulti(double x1, double y1, double x2, double y2, double dur) {
    YkFinger(1, x1, y1, 1, 1.0);
    YkFinger(1, x2, y2, 2, 1.0);
    usleep((useconds_t)(dur * 1000000));
    YkFinger(2, x1, y1, 1, 0.0);
    YkFinger(2, x2, y2, 2, 0.0);
}

static NSData *HandleLine(NSString *line) {
    NSDictionary *req = nil;
    NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (d) req = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    if (![req isKindOfClass:[NSDictionary class]])
        return [@"{\"error\":\"bad json\"}\n" dataUsingEncoding:NSUTF8StringEncoding];

    NSString *action = req[@"action"] ?: @"tap";
    double x = [req[@"x"] doubleValue], y = [req[@"y"] doubleValue];
    NSDictionary *resp = nil;

    if ([action isEqualToString:@"tap"]) {
        DoTap(x, y);
        resp = @{ @"ok": @YES, @"action": action, @"x": @(x), @"y": @(y) };
    } else if ([action isEqualToString:@"longPress"]) {
        DoLongPress(x, y, [req[@"duration"] doubleValue] ?: 1.0);
        resp = @{ @"ok": @YES, @"action": action };
    } else if ([action isEqualToString:@"swipe"]) {
        DoSwipe(x, y, [req[@"toX"] doubleValue], [req[@"toY"] doubleValue],
                [req[@"duration"] doubleValue] ?: 0.3, (int)([req[@"steps"] integerValue] ?: 12));
        resp = @{ @"ok": @YES, @"action": action };
    } else if ([action isEqualToString:@"multi"]) {
        DoMulti(x, y, [req[@"x2"] doubleValue], [req[@"y2"] doubleValue],
                [req[@"duration"] doubleValue] ?: 0.3);
        resp = @{ @"ok": @YES, @"action": action };
    } else if ([action isEqualToString:@"ping"]) {
        resp = @{ @"ok": @YES, @"client": @(YkClient() != NULL), @"pid": @(getpid()) };
    } else {
        resp = @{ @"ok": @NO, @"error": @"unknown action" };
    }

    NSData *out = [NSJSONSerialization dataWithJSONObject:resp options:0 error:NULL];
    NSMutableData *md = [NSMutableData dataWithData:out ?: [NSData data]];
    [md appendBytes:"\n" length:1];
    return md;
}

static CFDataRef PortCallback(CFMessagePortRef port, SInt32 msgid, CFDataRef data, void *info) {
    NSString *line = @"{}";
    if (data && CFDataGetLength(data) > 0) {
        NSData *d = (__bridge NSData *)data;
        line = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"{}";
    }
    NSData *resp = HandleLine(line);
    return (__bridge_retained CFDataRef)resp;
}

// 独立线程跑自己的 runloop —— 绝不能在构造函数里用 CFGetCurrentRunLoop
// 原版同样做法：NSThread "com.sky.ykpro.MachPortListenerThread"
static void YKPortThreadMain(void) {
    @autoreleasepool {
        CFMessagePortRef local = CFMessagePortCreateLocal(kCFAllocatorDefault,
                                                          CFSTR("com.yk.touch"),
                                                          PortCallback, NULL, NULL);
        if (!local) return;
        CFRunLoopSourceRef src = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, local, 0);
        if (src) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
            CFRelease(src);
        }
        CFRunLoopRun();     // 线程自己的循环，不碰 SpringBoard 主线程
    }
}

__attribute__((constructor))
static void YKSpringTouchInit(void) {
    // 延后到主 runloop 起来之后再启线程，避免 SpringBoard 启动阶段崩溃
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSThread *t = [[NSThread alloc] initWithBlock:^{ YKPortThreadMain(); }];
        t.name = @"YKTouchListener";
        t.stackSize = 512 * 1024;
        [t start];
    });
}
