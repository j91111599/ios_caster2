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

// 优先走 SpringBoard tweak 的 socket（真正能注入）
static NSDictionary *YkSocketSend(NSDictionary *req) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return nil;
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, "/var/tmp/yktouch.sock", sizeof(addr.sun_path) - 1);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) { close(fd); return nil; }
    NSData *body = [NSJSONSerialization dataWithJSONObject:req options:0 error:NULL];
    NSMutableData *md = [NSMutableData dataWithData:body ?: [NSData data]];
    [md appendBytes:"\n" length:1];
    write(fd, md.bytes, md.length);
    char buf[1024] = {0};
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) return nil;
    NSData *rd = [NSData dataWithBytes:buf length:(NSUInteger)n];
    id obj = [NSJSONSerialization JSONObjectWithData:rd options:0 error:NULL];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
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
    typedef IOHIDEventSystemClientRef (*CreateFn)(CFAllocatorRef);
    CreateFn create = (CreateFn)YkSym("IOHIDEventSystemClientCreate");
    if (!create) create = (CreateFn)YkSym("IOHIDEventSystemClientCreateWithType");
    if (create) gHIDClient = create(kCFAllocatorDefault);
    return gHIDClient;
}

static void YkSendEvent(IOHIDEventRef ev) {
    typedef void (*DispatchFn)(IOHIDEventSystemClientRef, IOHIDEventRef);
    DispatchFn dispatch = (DispatchFn)YkSym("IOHIDEventSystemClientDispatchEvent");
    if (dispatch && YkHIDClient() && ev) dispatch(YkHIDClient(), ev);
}

// 单指事件：phase 1=down 2=up 3=move，其余手指抬起
static void YkFingerEvent(int phase, double x, double y, double pressure, uint64_t ts) {
    typedef IOHIDEventRef (*SimpleDigitizerFn)(CFAllocatorRef, IOHIDEventRef, double, double,
                                               uint32_t, uint32_t, uint32_t, uint32_t,
                                               uint32_t, double, double, double, double,
                                               uint32_t);
    SimpleDigitizerFn simple = (SimpleDigitizerFn)YkSym("IOHIDEventCreateDigitizerFingerEvent");
    if (!simple) return;
    IOHIDEventRef ev = simple(kCFAllocatorDefault, NULL, ts, x, y, 1, 1, phase, 1, pressure, 1.0, 0.0, 0.0, 0);
    if (ev) {
        YkSendEvent(ev);
        CFRelease(ev);
    }
}

// 两指事件（捏合/多指）
static void YkTwoFingerEvent(int phase, double x1, double y1, double x2, double y2, uint64_t ts) {
    typedef IOHIDEventRef (*FingerFn)(CFAllocatorRef, IOHIDEventRef, double, double,
                                      uint32_t, uint32_t, uint32_t, uint32_t, uint32_t,
                                      double, double, double, double, uint32_t);
    FingerFn fn = (FingerFn)YkSym("IOHIDEventCreateDigitizerFingerEvent");
    if (!fn) return;
    IOHIDEventRef e1 = fn(kCFAllocatorDefault, NULL, ts, x1, y1, 1, 1, phase, 1, 1.0, 1.0, 0.0, 0.0, 0);
    IOHIDEventRef e2 = fn(kCFAllocatorDefault, NULL, ts, x2, y2, 1, 1, phase, 2, 1.0, 1.0, 0.0, 0.0, 0);
    if (e1) { YkSendEvent(e1); CFRelease(e1); }
    if (e2) { YkSendEvent(e2); CFRelease(e2); }
}

static uint64_t YkNow(void) {
    return (uint64_t)([[NSProcessInfo processInfo] systemUptime] * 1000000000ULL);
}

NSDictionary *YkTouchTap(double x, double y) {
    NSDictionary *r = YkSocketSend(@{ @"action": @"tap", @"x": @(x), @"y": @(y) });
    if (r) return @{ @"value": r };
    YkFingerEvent(1, x, y, 1.0, YkNow());
    usleep(30000);
    YkFingerEvent(2, x, y, 0.0, YkNow());
    return @{ @"value": @{ @"action": @"tap", @"x": @(x), @"y": @(y), @"sent": @(YkHIDClient() != NULL) } };
}

NSDictionary *YkTouchLongPress(double x, double y, double durationSec) {
    NSDictionary *r = YkSocketSend(@{ @"action": @"longPress", @"x": @(x), @"y": @(y), @"duration": @(durationSec) });
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
    NSDictionary *r = YkSocketSend(@{ @"action": @"swipe", @"x": @(x1), @"y": @(y1),
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
    NSDictionary *rs = YkSocketSend(@{ @"action": @"multi", @"x": @(x1), @"y": @(y1),
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
    NSDictionary *r = YkSocketSend(@{ @"action": @"ping" });
    if (r) return @{ @"value": r };
    return @{ @"value": @{ @"ok": @NO, @"reason": @"socket 不可用（tweak 未加载）" } };
}
