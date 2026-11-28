//  YKSBBall.m —— SpringBoard 侧悬浮录制球（原版「打开录制小球」的跨 App 版本）
//
//  行为：
//    · App 通过 CFMessagePort "com.yk.ball" 下发 show/hide/start/stop/status；
//    · 球可拖动，点击展开/收起菜单（开始 / 暂停 / 完成 / 取消）；
//    · 录制时用 IOHID 监视器采集全局 digitizer 事件（归一化坐标 → 像素），
//      结束时 POST 到 daemon 65325 /record/save。
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <dlfcn.h>
#import <mach/mach_time.h>

static void YKBallHIDCallback(void *target, void *refcon, void *service, void *event);

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

static void *SBSym(const char *n) {
    static void *h1 = NULL, *h2 = NULL;
    if (!h1) h1 = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!h2) h2 = dlopen("/System/Library/PrivateFrameworks/IOHID.framework/IOHID", RTLD_LAZY);
    void *p = h1 ? dlsym(h1, n) : NULL;
    if (!p && h2) p = dlsym(h2, n);
    return p;
}

static void SBLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *path = @"/var/mobile/Media/ykball.log";
    NSString *line = [NSString stringWithFormat:@"[%.0f] %@\n", [[NSDate date] timeIntervalSince1970], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]; return; }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

#pragma mark - 录制采集

@interface YKBallRecorder : NSObject
@property (nonatomic, strong) NSMutableArray *steps;
@property (nonatomic, assign) BOOL recording;
@property (nonatomic, assign) NSTimeInterval startedAt;
@property (nonatomic, assign) CGSize screen;
+ (instancetype)shared;
- (void)start;
- (void)resume;
- (void)pause;
- (void)finish;      // 保存
- (void)cancel;
@end

static IOHIDEventSystemClientRef gMon = NULL;
static void *gMonRef = NULL;

@implementation YKBallRecorder {
    BOOL _paused;
    NSTimeInterval _pausedTotal;
    NSTimeInterval _pauseAt;
}

+ (instancetype)shared {
    static YKBallRecorder *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [YKBallRecorder new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _steps = [NSMutableArray array];
        _screen = [UIScreen mainScreen].bounds.size;
    }
    return self;
}

- (void)installMonitor {
    if (gMon) return;
    void *fc = SBSym("IOHIDEventSystemClientCreate");
    void *hr = SBSym("IOHIDEventSystemClientRegisterEventCallback");
    void *hs = SBSym("IOHIDEventSystemClientScheduleWithRunLoop");
    if (!fc || !hr) { SBLog(@"monitor symbols missing"); return; }
    gMon = ((IOHIDEventSystemClientRef (*)(CFAllocatorRef))fc)(kCFAllocatorDefault);
    if (!gMon) { SBLog(@"monitor client nil"); return; }
    ((void (*)(IOHIDEventSystemClientRef, void *, void *, uint32_t))hr)(
        gMon, (void *)YKBallHIDCallback, NULL, 0);
    if (hs) ((void (*)(IOHIDEventSystemClientRef, CFRunLoopRef, CFStringRef))hs)(
        gMon, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    SBLog(@"monitor installed");
}

- (void)start {
    [self installMonitor];
    [_steps removeAllObjects];
    _recording = YES;
    _paused = NO;
    _pausedTotal = 0;
    _startedAt = [NSDate date].timeIntervalSince1970;
}

- (void)resume {
    if (_paused) { _pausedTotal += [NSDate date].timeIntervalSince1970 - _pauseAt; _paused = NO; }
}

- (void)pause {
    if (!_paused) { _pauseAt = [NSDate date].timeIntervalSince1970; _paused = YES; }
}

- (double)elapsed {
    if (!_recording) return 0;
    return [NSDate date].timeIntervalSince1970 - _startedAt - _pausedTotal;
}

- (void)cancel {
    _recording = NO;
    [_steps removeAllObjects];
}

- (void)finish {
    if (!_recording) return;
    double dur = [self elapsed];   // 必须在清 _recording 之前算
    _recording = NO;
    NSMutableArray *steps = [_steps mutableCopy];
    if (!steps.count) { SBLog(@"finish: no steps"); return; }
    NSDictionary *last = steps.lastObject;
    [steps addObject:@{ @"x": last[@"x"], @"y": last[@"y"], @"touch": @0, @"delayMs": @16 }];

    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"MM月dd日 HH:mm";
    NSDictionary *body = @{ @"name": [df stringFromDate:[NSDate date]] ?: @"录制",
                            @"steps": steps,
                            @"duration": @(dur) };
    NSData *d = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"http://127.0.0.1:65325/record/save"]];
    r.HTTPMethod = @"POST";
    r.HTTPBody = d;
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:r
        completionHandler:^(NSData *x, NSURLResponse *y, NSError *e) {
        SBLog(@"saved steps=%lu err=%@", (unsigned long)steps.count, e.localizedDescription);
    }] resume];
}

@end

// 监视器回调（全局所有 App 的触摸）
static void YKBallHIDCallback(void *target, void *refcon, void *service, void *event) {
    YKBallRecorder *rec = [YKBallRecorder shared];
    if (!rec.recording || rec.steps == NULL) return;
    void *ft = SBSym("IOHIDEventGetType");
    if (!ft) return;
    uint32_t t = ((uint32_t (*)(void *))ft)(event);
    if (t != 11) return;

    void *ff = SBSym("IOHIDEventGetFloatValue");
    void *fg = SBSym("IOHIDEventGetIntegerValue");
    void *fch = SBSym("IOHIDEventGetChildren");
    if (!ff) return;

    // 手指坐标在子事件里：父事件只有 range/touch 标志
    void *finger = event;
    if (fch) {
        CFArrayRef kids = ((CFArrayRef (*)(void *))fch)(event);
        if (kids && CFArrayGetCount(kids) > 0) {
            finger = (void *)CFArrayGetValueAtIndex(kids, 0);
        }
    }
    double nx = ((double (*)(void *, uint32_t))ff)(finger, 0xB0000);
    double ny = ((double (*)(void *, uint32_t))ff)(finger, 0xB0001);
    if (nx == 0 && ny == 0) {
        nx = ((double (*)(void *, uint32_t))ff)(event, 0xB0000);
        ny = ((double (*)(void *, uint32_t))ff)(event, 0xB0001);
    }

    int range = 1;
    if (fg) {
        int64_t r = ((int64_t (*)(void *, uint32_t))fg)(event, 0xB0008);
        range = r ? 1 : 0;
    }
    // 合成事件（我们自己的注入器）range/touch 标志不可靠，统一按「按住移动」记录，
    // 收尾的抬起点在 finish 里补一个，回放时按拖动轨迹注入。
    if (nx == 0 && ny == 0) return;   // 无坐标的噪声帧丢弃
    [rec.steps addObject:@{ @"x": @(nx * 750), @"y": @(ny * 1334),
                            @"touch": @1, @"delayMs": @16 }];
    (void)range;
}

#pragma mark - 悬浮球 UI

@interface YKBallWindow : UIWindow
@end

@interface YKBallController : NSObject
+ (instancetype)shared;
- (void)show;
- (void)hide;
- (BOOL)isVisible;
@end

@implementation YKBallController {
    YKBallWindow *_win;
    UIView *_ball;
    UIView *_menu;
    UILabel *_hint;
    BOOL _menuOpen;
    BOOL _recording;
    NSTimer *_timer;
}

+ (instancetype)shared {
    static YKBallController *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [YKBallController new]; });
    return s;
}

- (BOOL)isVisible { return _win && !_win.hidden; }

- (void)show {
    if (_win) { _win.hidden = NO; [self bringUp]; return; }
    UIWindowScene *scene = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)sc; break; }
    }
    if (scene) _win = [[YKBallWindow alloc] initWithWindowScene:scene];
    else _win = [[YKBallWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _win.frame = [UIScreen mainScreen].bounds;
    _win.windowLevel = UIWindowLevelAlert + 100;
    _win.backgroundColor = [UIColor clearColor];
    _win.rootViewController = [UIViewController new];
    _win.hidden = NO;

    UIView *host = _win.rootViewController.view;
    host.backgroundColor = [UIColor clearColor];

    CGFloat H = _win.bounds.size.height;
    _ball = [[UIView alloc] initWithFrame:CGRectMake(_win.bounds.size.width - 64, H * 0.45, 48, 48)];
    _ball.backgroundColor = [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0];
    _ball.layer.cornerRadius = 24;
    _ball.layer.shadowColor = [UIColor blackColor].CGColor;
    _ball.layer.shadowOpacity = 0.35;
    _ball.layer.shadowRadius = 10;
    _ball.layer.shadowOffset = CGSizeMake(0, 4);
    [host addSubview:_ball];

    UIView *ring = [[UIView alloc] initWithFrame:CGRectMake(14, 14, 20, 20)];
    ring.layer.borderWidth = 3;
    ring.layer.borderColor = [UIColor whiteColor].CGColor;
    ring.layer.cornerRadius = 10;
    ring.userInteractionEnabled = NO;
    [_ball addSubview:ring];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [_ball addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)];
    [_ball addGestureRecognizer:tap];

    // 展开菜单：开始/暂停/完成/取消
    _menu = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 56, 214)];
    _menu.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
    _menu.layer.cornerRadius = 28;
    _menu.hidden = YES;
    [host addSubview:_menu];

    NSArray *items = @[ @[@"play.fill", @"开始"], @[@"pause.fill", @"暂停"],
                        @[@"stop.fill", @"完成"], @[@"xmark", @"取消"] ];
    for (NSInteger i = 0; i < items.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(4, 6 + i * 52, 48, 44);
        [b setImage:[UIImage systemImageNamed:items[i][0]] forState:UIControlStateNormal];
        b.tintColor = [UIColor whiteColor];
        b.tag = 100 + i;
        [b addTarget:self action:@selector(menuTap:) forControlEvents:UIControlEventTouchUpInside];
        [_menu addSubview:b];
    }

    _hint = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 22)];
    _hint.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _hint.textColor = [UIColor whiteColor];
    _hint.textAlignment = NSTextAlignmentCenter;
    _hint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    _hint.layer.cornerRadius = 11;
    _hint.clipsToBounds = YES;
    _hint.hidden = YES;
    [host addSubview:_hint];
    SBLog(@"ball shown");
}

- (void)bringUp {
    [_win.rootViewController.view bringSubviewToFront:_ball];
    [_win.rootViewController.view bringSubviewToFront:_menu];
}

- (void)hide {
    _win.hidden = YES;
    [[YKBallRecorder shared] cancel];
    _recording = NO;
    [_timer invalidate]; _timer = nil;
    _hint.hidden = YES;
    SBLog(@"ball hidden");
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint p = [g translationInView:_win];
    CGPoint c = _ball.center;
    _ball.center = CGPointMake(c.x + p.x, c.y + p.y);
    [g setTranslation:CGPointZero inView:_win];
    [self layoutMenu];
}

- (void)layoutMenu {
    CGRect f = _ball.frame;
    CGFloat W = _win.bounds.size.width, H = _win.bounds.size.height;
    CGFloat cx = f.origin.x + 24;
    if (cx + 28 > W - 6) cx = W - 34;             // 靠右时贴边
    CGFloat cy = f.origin.y - 110;
    if (cy - 107 < 40) cy = f.origin.y + 110 + 48; // 顶部放不下就放下方
    if (cy + 107 > H - 40) cy = H - 120;
    _menu.center = CGPointMake(cx, cy);

    CGFloat hw = _hint.bounds.size.width;
    CGFloat hx = MAX(hw / 2 + 6, MIN(f.origin.x + 24, W - hw / 2 - 6));
    _hint.center = CGPointMake(hx, f.origin.y + 62);
}

- (void)toggleMenu {
    _menuOpen = !_menuOpen;
    _menu.hidden = !_menuOpen;
    [self layoutMenu];
    [self bringUp];
}

- (void)menuTap:(UIButton *)b {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self menuTap:b]; });
        return;
    }
    NSInteger i = b.tag - 100;
    YKBallRecorder *rec = [YKBallRecorder shared];
    if (i == 0) {            // 开始
        [rec start];
        _recording = YES;
        _hint.hidden = NO;
        _hint.text = @"录制中 0s · 点球结束";
        [_timer invalidate];
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
            self->_hint.text = [NSString stringWithFormat:@"录制中 %.0fs · 点球结束",
                                [rec elapsed]];
        }];
    } else if (i == 1) {     // 暂停
        [rec pause];
        _hint.text = [NSString stringWithFormat:@"已暂停 %.0fs", [rec elapsed]];
    } else if (i == 2) {     // 完成
        [rec finish];
        _recording = NO;
        [_timer invalidate]; _timer = nil;
        _hint.text = @"已保存，回到 App 查看";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ self->_hint.hidden = YES; });
    } else {                 // 取消
        [rec cancel];
        _recording = NO;
        [_timer invalidate]; _timer = nil;
        _hint.hidden = YES;
    }
    _menuOpen = NO;
    _menu.hidden = YES;
}

@end


// 回放结束：把 Lite App 拉回前台（Darwin 通知，daemon 用 notify_post 触发）
static void YKOpenAppInit(void) {
    int token = 0;
    notify_register_dispatch("com.yk.openapp", &token, dispatch_get_main_queue(), ^(int t) {
        Class ws = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = ws ? ((id (*)(id, SEL))objc_msgSend)(ws, sel_registerName("defaultWorkspace")) : nil;
        if (!workspace) { SBLog(@"openapp: no LSApplicationWorkspace"); return; }
        ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace,
            sel_registerName("openApplicationWithBundleID:"), @"com.yk.engine.ui");
        SBLog(@"openapp: requested");
    });
}

@implementation YKBallWindow
// 关键：整窗 750x1334 覆盖桌面时不能吃掉普通点击，否则桌面/其它 App 全部失灵
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

// ---- App 指令通道 ----

static CFDataRef YKBallPortCallback(CFMessagePortRef port, SInt32 msgid, CFDataRef data, void *info) {
    NSString *line = @"{}";
    if (data && CFDataGetLength(data) > 0) {
        NSData *d = (__bridge NSData *)data;
        line = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"{}";
    }
    NSDictionary *req = [NSJSONSerialization JSONObjectWithData:
                         [line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] ?: @{};
    NSString *action = req[@"action"] ?: @"status";
    YKBallController *bc = [YKBallController shared];
    NSMutableDictionary *resp = [NSMutableDictionary dictionary];
    // 端口回调跑在自建线程上，SpringBoard 开了 CA_ASSERT_MAIN_THREAD_TRANSACTIONS，
    // 任何 UIWindow/UIView 操作必须回主线程，否则直接 abort。
    void (^work)(void) = ^{
        if ([action isEqualToString:@"show"]) { [bc show]; resp[@"ok"] = @YES; }
        else if ([action isEqualToString:@"hide"]) { [bc hide]; resp[@"ok"] = @YES; }
        else if ([action isEqualToString:@"toggle"]) {
            if ([bc isVisible]) [bc hide]; else [bc show];
            resp[@"ok"] = @YES;
        }
        resp[@"visible"] = @([bc isVisible]);
    };
    if ([NSThread isMainThread]) work();
    else dispatch_sync(dispatch_get_main_queue(), work);
    NSData *out = [NSJSONSerialization dataWithJSONObject:resp options:0 error:NULL];
    return (__bridge_retained CFDataRef)out;
}

static void YKBallPortThread(void) {
    @autoreleasepool {
        CFMessagePortRef local = CFMessagePortCreateLocal(kCFAllocatorDefault,
                                                          CFSTR("com.yk.ball"),
                                                          YKBallPortCallback, NULL, NULL);
        if (!local) { SBLog(@"port create failed"); return; }
        CFRunLoopSourceRef src = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, local, 0);
        if (src) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
            CFRelease(src);
        }
        SBLog(@"ball port ready");
        CFRunLoopRun();
    }
}

__attribute__((constructor))
static void YKBallInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSThread *t = [[NSThread alloc] initWithBlock:^{ YKBallPortThread(); }];
        t.name = @"YKBallPort";
        t.stackSize = 512 * 1024;
        [t start];
        YKOpenAppInit();
        SBLog(@"ball tweak loaded");
    });
}
