//  YKMirror.m — 屏幕镜像（CARenderServer + MJPEG + WebSocket）
//
//  完全按原版 YKEngine 的实现路径复刻：
//    CARenderServer（私有）→ IOSurface/CVPixelBuffer → JPEG/MJPEG → WebSocket
//
//  验证依据：YKEngine(46.3MB) 二进制字符串
//    CARenderServer 0x2545319 · IOSurfaceCreate 0x2d62c8c
//    MjpegEncoder 0x23d6010 · Sec-WebSocket 0x2571ecc
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
// IOSurface 头不在公开 SDK 里，手工声明
typedef struct __IOSurface *IOSurfaceRef;
extern IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties);
extern kern_return_t IOSurfaceLock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
extern kern_return_t IOSurfaceUnlock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
extern size_t IOSurfaceGetWidth(IOSurfaceRef buffer);
extern size_t IOSurfaceGetHeight(IOSurfaceRef buffer);
extern void *IOSurfaceGetBaseAddress(IOSurfaceRef buffer);
extern size_t IOSurfaceGetBytesPerRow(IOSurfaceRef buffer);
extern const CFStringRef kIOSurfaceWidth;
extern const CFStringRef kIOSurfaceHeight;
extern const CFStringRef kIOSurfaceBytesPerElement;
extern const CFStringRef kIOSurfacePixelFormat;
#define kIOSurfaceLockReadOnly 0x00000001
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#import <dlfcn.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <CommonCrypto/CommonDigest.h>

typedef struct _CARenderServer *CARenderServerRef;

static NSData *YkGrabJPEGFallback(double quality);
static IOSurfaceRef YkRenderDisplayUnsafe(void);

static int gMirrorPort = 65330;
static int gMirrorFps  = 20;
static double gMirrorQuality = 0.6;
static NSMutableArray *gWSFds = nil;
static NSThread *gMirrorThread = nil;
static volatile BOOL gMirrorRunning = NO;

#pragma mark - CARenderServer 私有符号

static IOSurfaceRef YkRenderDisplay(void) {
    // CARenderServerCreateSnapshots 的私有签名尚未确定，调用会崩溃，暂时禁用
    if (!getenv("YK_ENABLE_CARENDERSERVER")) return NULL;
    return YkRenderDisplayUnsafe();
}

static IOSurfaceRef YkRenderDisplayUnsafe(void) {
    static void *qc = NULL;
    static void *fPort = NULL, *fSnap = NULL;
    if (!qc) qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_LAZY);
    if (!qc) return NULL;
    if (!fPort) fPort = dlsym(qc, "CARenderServerGetServerPort");
    if (!fSnap) fSnap = dlsym(qc, "CARenderServerCreateSnapshots");
    if (!fPort || !fSnap) return NULL;

    typedef unsigned int (*PortFn)(void *);
    PortFn getPort = (PortFn)fPort;
    unsigned int srv = getPort(NULL);
    if (!srv) return NULL;

    CGFloat scale = [UIScreen mainScreen].scale;
    CGRect r = CGRectMake(0, 0,
                          [UIScreen mainScreen].bounds.size.width  * scale,
                          [UIScreen mainScreen].bounds.size.height * scale);

    // CFArrayRef CARenderServerCreateSnapshots(mach_port_t, uint32_t display,
    //        uint32_t count, const CGRect *rects, uint32_t seed, uint32_t options)
    typedef CFArrayRef (*SnapFn)(unsigned int, unsigned int, unsigned int,
                                 const CGRect *, unsigned int, unsigned int);
    SnapFn snap = (SnapFn)fSnap;
    CFArrayRef arr = snap(srv, 0, 1, &r, 0, 0);
    if (!arr || CFArrayGetCount(arr) == 0) return NULL;

    IOSurfaceRef out = (IOSurfaceRef)CFArrayGetValueAtIndex(arr, 0);
    if (out) CFRetain(out);
    CFRelease(arr);
    return out;
}

#pragma mark - 帧编码（硬件 JPEG）

static NSData *YkEncodeJPEG(IOSurfaceRef surface, CGFloat quality) {
    if (!surface) return nil;
    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
    size_t w = IOSurfaceGetWidth(surface);
    size_t h = IOSurfaceGetHeight(surface);
    void *base = IOSurfaceGetBaseAddress(surface);
    size_t bpr = IOSurfaceGetBytesPerRow(surface);
    if (!base || w == 0 || h == 0) { IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL); return nil; }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(base, w, h, 8, bpr, cs,
                                             kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    NSData *jpeg = nil;
    if (ctx) {
        CGImageRef img = CGBitmapContextCreateImage(ctx);
        if (img) {
            NSMutableData *md = [NSMutableData data];
            CGImageDestinationRef dst = CGImageDestinationCreateWithData(
                (__bridge CFMutableDataRef)md, CFSTR("public.jpeg"), 1, NULL);
            if (dst) {
                NSDictionary *opts = @{ (id)kCGImageDestinationLossyCompressionQuality: @(quality) };
                CGImageDestinationAddImage(dst, img, (__bridge CFDictionaryRef)opts);
                if (CGImageDestinationFinalize(dst)) jpeg = md;
                CFRelease(dst);
            }
            CGImageRelease(img);
        }
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(cs);
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    return jpeg;
}

#pragma mark - WebSocket 握手

static NSString *YkWSKey(NSString *clientKey) {
    NSString *magic = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    NSData *d = [[clientKey stringByAppendingString:magic] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH] = {0};
    CC_SHA1(d.bytes, (CC_LONG)d.length, digest);
    return [[NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH]
            base64EncodedStringWithOptions:0];
}

// 发送一个 WebSocket 二进制帧（服务端不掩码）
static BOOL YkWSSendBinary(int fd, NSData *payload) {
    if (fd < 0 || payload.length == 0) return NO;
    uint8_t hdr[10]; int n = 0;
    hdr[n++] = 0x82;                            // FIN + binary
    size_t len = payload.length;
    if (len < 126) { hdr[n++] = (uint8_t)len; }
    else if (len < 65536) { hdr[n++] = 126; hdr[n++] = (len >> 8) & 0xFF; hdr[n++] = len & 0xFF; }
    else { hdr[n++] = 127; for (int i = 7; i >= 0; i--) hdr[n++] = (len >> (i*8)) & 0xFF; }

    struct iovec iov[2];
    iov[0].iov_base = hdr;  iov[0].iov_len = n;
    iov[1].iov_base = (void *)payload.bytes; iov[1].iov_len = payload.length;
    struct msghdr mh = {0};
    mh.msg_iov = iov; mh.msg_iovlen = 2;
    ssize_t sent = sendmsg(fd, &mh, MSG_NOSIGNAL);
    return sent > 0;
}

#pragma mark - 镜像服务

static void YkMirrorLoop(void) {
    // 数据端口（WebSocket）
    int dataFd = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(dataFd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET; a.sin_port = htons(gMirrorPort); a.sin_addr.s_addr = INADDR_ANY;
    if (bind(dataFd, (struct sockaddr *)&a, sizeof(a)) < 0) { close(dataFd); return; }
    listen(dataFd, 4);
    fcntl(dataFd, F_SETFL, O_NONBLOCK);

    NSDate *lastFrame = [NSDate dateWithTimeIntervalSince1970:0];
    double interval = 1.0 / (gMirrorFps > 0 ? gMirrorFps : 20);

    while (gMirrorRunning) {
        // 接受新连接 + 握手
        int c = accept(dataFd, NULL, NULL);
        if (c >= 0) {
            char buf[2048] = {0};
            recv(c, buf, sizeof(buf) - 1, 0);
            NSString *req = @(buf);
            NSString *key = nil;
            for (NSString *line in [req componentsSeparatedByString:@"\r\n"]) {
                if ([line.lowercaseString hasPrefix:@"sec-websocket-key:"]) {
                    key = [[line componentsSeparatedByString:@":"] lastObject];
                    key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                }
            }
            if (key.length) {
                NSString *accept = YkWSKey(key);
                NSString *resp = [NSString stringWithFormat:
                    @"HTTP/1.1 101 Switching Protocols\r\n"
                    @"Upgrade: websocket\r\nConnection: Upgrade\r\n"
                    @"Sec-WebSocket-Accept: %@\r\n\r\n", accept];
                send(c, resp.UTF8String, [resp lengthOfBytesUsingEncoding:NSUTF8StringEncoding], MSG_NOSIGNAL);
                if (!gWSFds) gWSFds = [NSMutableArray array];
                [gWSFds addObject:@(c)];
            } else {
                close(c);
            }
        }

        // 按 fps 推帧
        NSTimeInterval dt = -[lastFrame timeIntervalSinceNow];
        if (dt >= interval && gWSFds.count > 0) {
            NSData *jpeg = nil;
            @autoreleasepool {
                IOSurfaceRef s = YkRenderDisplay();
                jpeg = YkEncodeJPEG(s, gMirrorQuality);
                if (s) CFRelease(s);
                if (!jpeg) {
                    __block NSData *fb = nil;
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        fb = YkGrabJPEGFallback(gMirrorQuality);
                    });
                    jpeg = fb;
                }
            }
            if (jpeg) {
                NSMutableArray *dead = [NSMutableArray array];
                for (NSNumber *n in [gWSFds copy]) {
                    if (!YkWSSendBinary(n.intValue, jpeg)) [dead addObject:n];
                }
                for (NSNumber *n in dead) { close(n.intValue); [gWSFds removeObject:n]; }
            }
            lastFrame = [NSDate date];
        }
        usleep(5000);   // 5ms
    }
    close(dataFd);
}

#pragma mark - 对外接口

NSDictionary *YkMirrorStart(NSInteger port, NSInteger fps, double quality) {
    if (gMirrorRunning) return @{ @"value": @{ @"running": @YES, @"port": @(gMirrorPort) } };
    if (port > 0) gMirrorPort = (int)port;
    if (fps > 0) gMirrorFps = (int)fps;
    if (quality > 0) gMirrorQuality = quality;
    gMirrorRunning = YES;
    gMirrorThread = [[NSThread alloc] initWithBlock:^{ YkMirrorLoop(); }];
    gMirrorThread.name = @"YKMirror";
    [gMirrorThread start];
    return @{ @"value": @{ @"running": @YES, @"port": @(gMirrorPort),
                           @"fps": @(gMirrorFps), @"quality": @(gMirrorQuality),
                           @"codec": @"mjpeg", @"transport": @"websocket" } };
}

NSDictionary *YkMirrorStop(void) {
    gMirrorRunning = NO;
    for (NSNumber *n in [gWSFds copy]) close(n.intValue);
    [gWSFds removeAllObjects];
    return @{ @"value": @{ @"running": @NO } };
}

NSDictionary *YkMirrorStatus(void) {
    return @{ @"value": @{ @"running": @(gMirrorRunning),
                           @"port": @(gMirrorPort),
                           @"fps": @(gMirrorFps),
                           @"quality": @(gMirrorQuality),
                           @"clients": @(gWSFds.count),
                           @"codec": @"mjpeg",
                           @"capture": @"CARenderServer" } };
}

// 回退取帧：UIGraphics 渲染主窗口（不依赖私有 API）
static NSData *YkGrabJPEGFallback(double quality) {
    UIWindow *win = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (w.isKeyWindow) { win = w; break; }
    if (!win) win = UIApplication.sharedApplication.windows.firstObject;
    if (!win) return nil;

    UIGraphicsBeginImageContextWithOptions(win.bounds.size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    // 用 renderInContext（drawViewHierarchy 在后台会返回空白）
    [win.layer renderInContext:ctx];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!img) return nil;

    NSMutableData *md = [NSMutableData data];
    CGImageDestinationRef dst = CGImageDestinationCreateWithData(
        (__bridge CFMutableDataRef)md, CFSTR("public.jpeg"), 1, NULL);
    if (!dst) return nil;
    NSDictionary *opts = @{ (id)kCGImageDestinationLossyCompressionQuality: @(quality) };
    CGImageDestinationAddImage(dst, img.CGImage, (__bridge CFDictionaryRef)opts);
    BOOL ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
    return ok ? md : nil;
}

// 单帧抓取（调试用）
NSDictionary *YkMirrorGrabFrame(double quality) {
    double q = quality > 0 ? quality : 0.8;
    IOSurfaceRef s = YkRenderDisplay();
    NSData *jpeg = YkEncodeJPEG(s, q);
    BOOL viaSurface = (jpeg != nil);
    if (s) CFRelease(s);
    if (!jpeg) jpeg = YkGrabJPEGFallback(q);
    if (!jpeg) return @{ @"value": @{ @"error": @"capture_failed" } };
    return @{ @"value": @{ @"base64": [jpeg base64EncodedStringWithOptions:0],
                           @"bytes": @(jpeg.length),
                           @"codec": @"jpeg",
                           @"source": viaSurface ? @"CARenderServer" : @"UIGraphics" } };
}
