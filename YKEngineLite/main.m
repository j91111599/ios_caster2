//
//  main.m — YKEngineLite 入口（重建引擎的自托管版本）
//
//  设计：
//    · 监听 127.0.0.1:65323（避开原版 65322），可改 /var/mobile/Library/YKEngineLite/config.plist
//    · 复用 Recovered/ 里的重建模块：HTTP 路由 / 文件 / 偏好 / plist / 屏幕 / 加密 / UI / 录制
//    · 未移植模块（触控注入、元素树、OCR、装包）返回 501 并给出原因
//    · 响应包封与鉴权对齐设备实测（见 PROTOCOL_FINAL.md）
//
void YkHIDBoot(void);
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <signal.h>
#import "YKHTTPServerCompat.h"
#import <spawn.h>
#import <sys/wait.h>
extern char **environ;

// 模块入口（来自 Recovered/*.m）
extern uint64_t gYkSenderID;
extern int gYkClientType;
extern NSDictionary *YkLoopbackTest(double x, double y);
extern NSDictionary *YkTouchCaptureInfo(void);
extern NSDictionary *YkRecordArm(void);
extern NSDictionary *YkRecordStatus(void);
extern NSDictionary *YkReplayAtRaw(double x, double y, int raw);
extern NSDictionary *YkTouchTap(double x, double y);
extern NSDictionary *YkTouchLongPress(double x, double y, double d);
extern NSDictionary *YkTouchSwipe(double x1, double y1, double x2, double y2, double d, NSInteger steps);
extern NSDictionary *YkTouchHome(int count, double hold);
extern NSDictionary *YkTouchDoubleTap(double x, double y, double gap);
extern NSDictionary *YkTouchPinch(double x1, double y1, double ex1, double ey1,
                                  double x2, double y2, double ex2, double ey2,
                                  double durationSec, NSInteger steps);
extern NSDictionary *YkTouchSequence(NSArray *points, double defaultGapMs);

@interface YKFileModule : NSObject
+ (NSDictionary *)exists:(NSString *)p;
+ (NSDictionary *)size:(NSString *)p;
+ (NSDictionary *)read:(NSString *)p;
+ (NSDictionary *)write:(NSString *)p data:(id)d append:(BOOL)a;
+ (NSDictionary *)remove:(NSString *)p;
+ (NSDictionary *)list:(NSString *)d;
+ (NSDictionary *)linesOfFile:(NSString *)p;
+ (NSDictionary *)lineCount:(NSString *)p;
+ (NSDictionary *)digest:(NSString *)p algo:(NSString *)a;
@end

@interface YKPrefsModule : NSObject
+ (NSDictionary *)get:(NSString *)k namespace:(NSString *)ns;
+ (NSDictionary *)set:(id)v key:(NSString *)k namespace:(NSString *)ns;
+ (NSDictionary *)has:(NSString *)k namespace:(NSString *)ns;
+ (NSDictionary *)keys:(NSString *)ns;
+ (NSDictionary *)all:(NSString *)ns;
+ (NSDictionary *)namespaces;
@end

@interface YKPlistModule : NSObject
+ (NSDictionary *)read:(NSString *)p;
+ (NSDictionary *)dump:(NSString *)p;
@end

@interface YKScreenModule : NSObject
+ (NSDictionary *)info;
@end

@interface YKCryptoModule : NSObject
+ (NSDictionary *)dispatch:(NSString *)verb body:(NSDictionary *)b;
@end

@interface YKNetworkModule : NSObject
+ (NSDictionary *)request:(NSDictionary *)b method:(NSString *)m;
+ (NSDictionary *)cookies;
+ (NSDictionary *)proxy;
@end


@interface YKUIDispatcher : NSObject
+ (instancetype)shared;
- (NSDictionary *)dispatchMethod:(NSString *)method path:(NSString *)path
                            body:(NSDictionary *)body error:(NSString **)err;
@end

#pragma mark - 配置



static HTTPServer *gYKServiceServer = nil;
static volatile int gYKServiceRunning = 1;


static NSString *YkFindTool(NSString *name);
static int YkSpawnWait(NSString *path, NSArray<NSString *> *args);

// dpkg 装出来的 App，SpringBoard 不会自动把图标并进 IconState（LS 认识、桌面不显示）。
// daemon 启动时补一次：缺就加一页，然后 respring。
static void YkEnsureIcon(void) {
    NSString *bid = @"com.yk.engine.ui";
    NSString *path = @"/var/mobile/Library/SpringBoard/IconState.plist";
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) return;
    id st = [NSPropertyListSerialization propertyListWithData:d
                 options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL];
    if (![st isKindOfClass:[NSMutableDictionary class]]) return;
    NSMutableArray *pages = ((NSMutableDictionary *)st)[@"iconLists"];
    if (![pages isKindOfClass:[NSMutableArray class]]) return;
    for (NSArray *page in pages) {
        for (id item in page) {
            if ([item isKindOfClass:[NSString class]] && [item isEqualToString:bid]) return;
        }
    }
    [pages addObject:[NSMutableArray arrayWithObject:bid]];
    NSData *out = [NSPropertyListSerialization dataWithPropertyList:st
                        format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if (!out) return;
    if (![out writeToFile:path atomically:YES]) return;
    [[NSFileManager defaultManager] setAttributes:@{ NSFileOwnerAccountName: @"mobile",
                                                     NSFileGroupOwnerAccountName: @"mobile" }
                                     ofItemAtPath:path error:NULL];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(0, 0), ^{
        NSString *k = YkFindTool(@"killall");
        if (k) YkSpawnWait(k, @[@"-9", @"SpringBoard"]);
    });
}

BOOL YkServiceRunning(void) { return gYKServiceRunning != 0; }
void YkSetServiceRunning(BOOL on) {
    if (on && !gYKServiceRunning && gYKServiceServer) {
        NSError *e = nil;
        if ([gYKServiceServer start:&e]) gYKServiceRunning = 1;
    } else if (!on && gYKServiceRunning && gYKServiceServer) {
        [gYKServiceServer stop];
        gYKServiceRunning = 0;
    }
}



// 关键：从自身可执行路径推导 jbroot（roothide 的 .jbroot-XXXX 每台机器不同，
// 且 daemon 的 NSFileManager 看不到 /usr/bin 这类 jbroot 内路径）。
static NSString *YkRootPath(void) {
    static NSString *cached = nil;
    if (cached) return cached;
    char buf[4096] = {0};
    uint32_t size = sizeof(buf);
    NSString *exe = nil;
    if (_NSGetExecutablePath(buf, &size) == 0) exe = [NSString stringWithUTF8String:buf];
    if (!exe.length) exe = NSProcessInfo.processInfo.arguments.firstObject;
    if (!exe.length) exe = NSBundle.mainBundle.executablePath;
    // .../.jbroot-XXXX/usr/bin/ykenginelite -> .../.jbroot-XXXX
    NSString *p1 = [exe stringByDeletingLastPathComponent];   // .../usr/bin
    NSString *p2 = [p1 stringByDeletingLastPathComponent];    // .../usr
    NSString *p3 = [p2 stringByDeletingLastPathComponent];    // .../.jbroot-XXXX
    if ([p3 containsString:@".jbroot-"]) cached = p3;
    return cached;
}

// 在 jbroot / 常见前缀里找一个可执行文件（rootless/roothide 路径不固定）
static NSString *YkFindTool(NSString *name) {
    NSMutableArray *c = [NSMutableArray array];
    NSString *R = YkRootPath();
    if (R) {
        [c addObject:[R stringByAppendingPathComponent:[NSString stringWithFormat:@"usr/bin/%@", name]]];
        [c addObject:[R stringByAppendingPathComponent:[NSString stringWithFormat:@"usr/sbin/%@", name]]];
    }
    NSArray *roots = [[NSFileManager defaultManager]
                      contentsOfDirectoryAtPath:@"/var/containers/Bundle/Application" error:NULL];
    for (NSString *d in roots) {
        if (![d hasPrefix:@".jbroot-"]) continue;
        [c addObject:[NSString stringWithFormat:
            @"/var/containers/Bundle/Application/%@/usr/bin/%@", d, name]];
        [c addObject:[NSString stringWithFormat:
            @"/var/containers/Bundle/Application/%@/usr/sbin/%@", d, name]];
    }
    [c addObjectsFromArray:@[[NSString stringWithFormat:@"/var/jb/usr/bin/%@", name],
                             [NSString stringWithFormat:@"/var/jb/usr/sbin/%@", name],
                             [NSString stringWithFormat:@"/usr/bin/%@", name],
                             [NSString stringWithFormat:@"/usr/sbin/%@", name]]];
    for (NSString *p in c) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:p]) return p;
    }
    return nil;
}

static int YkSpawnWait(NSString *path, NSArray<NSString *> *args) {
    if (!path) return -1;
    pid_t pid = 0;
    NSMutableArray *all = [NSMutableArray arrayWithObject:path];
    [all addObjectsFromArray:args];
    char **argv = calloc(all.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < all.count; i++) argv[i] = (char *)[all[i] UTF8String];
    int rc = posix_spawn(&pid, path.UTF8String, NULL, NULL, argv, environ);
    free(argv);
    if (rc != 0) return -1000 - rc;
    int st = 0;
    waitpid(pid, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

// iOS 上 /bin/sh 未必存在（本机 rootfs 只读且 /bin 里只有 df/ps），
// 这里按候选列表找可用的 shell（roothide 的 jbroot 里有 usr/bin/sh）。
static NSString *YkShellPath(void) {
    static NSString *cached = nil;
    if (cached) return cached;
    NSMutableArray *cands = [NSMutableArray array];
    NSString *R = YkRootPath();
    if (R) {
        [cands addObject:[R stringByAppendingPathComponent:@"usr/bin/sh"]];
        [cands addObject:[R stringByAppendingPathComponent:@"bin/sh"]];
        [cands addObject:[R stringByAppendingPathComponent:@"usr/bin/bash"]];
    }
    NSString *env = NSProcessInfo.processInfo.environment[@"YK_SHELL"];
    if (env.length) [cands addObject:env];
    NSArray *roots = [[NSFileManager defaultManager]
                      contentsOfDirectoryAtPath:@"/var/containers/Bundle/Application" error:NULL];
    for (NSString *d in roots) {
        if (![d hasPrefix:@".jbroot-"]) continue;
        [cands addObject:[NSString stringWithFormat:
            @"/var/containers/Bundle/Application/%@/usr/bin/sh", d]];
        [cands addObject:[NSString stringWithFormat:
            @"/var/containers/Bundle/Application/%@/usr/bin/bash", d]];
    }
    [cands addObjectsFromArray:@[@"/var/jb/usr/bin/sh", @"/usr/bin/sh", @"/bin/sh",
                                 @"/var/jb/usr/bin/bash"]];
    for (NSString *c in cands) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:c]) { cached = c; break; }
    }
    return cached;
}

static int gYkLastSpawnRC = 0;
static int YkRunCmd(NSString *cmd) {
    NSString *sh = YkShellPath();
    if (!sh) { gYkLastSpawnRC = -999; return -999; }
    pid_t pid = 0;
    char *argv[] = { (char *)sh.UTF8String, (char *)"-c", (char *)cmd.UTF8String, NULL };
    extern char **environ;
    int rc = posix_spawn(&pid, sh.UTF8String, NULL, NULL, argv, environ);
    if (rc != 0) {
        rc = posix_spawn(&pid, sh.UTF8String, NULL, NULL, argv, NULL);
        if (rc == 0) gYkLastSpawnRC = 1000;
    }
    gYkLastSpawnRC = (rc == 0) ? (gYkLastSpawnRC == 1000 ? 1000 : 0) : rc;
    if (pid > 0) { int st = 0; waitpid(pid, &st, 0); }
    return gYkLastSpawnRC;
}

static uint16_t YKListenPort(void) {
    NSString *cfg = @"/var/mobile/Library/YKEngineLite/config.plist";
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:cfg];
    NSNumber *p = d[@"port"];
    NSString *envPort = NSProcessInfo.processInfo.environment[@"YK_HTTP_PORT"];
    if (envPort.length) return (uint16_t)envPort.intValue;
    return p ? p.unsignedShortValue : 65323;
}

#pragma mark - 路由分派

static NSDictionary *YKNotPorted(NSString *module) {
    return @{ @"value.error": @"not_ported",
              @"value.message": [NSString stringWithFormat:
                  @"%@ 模块未移植到 Lite 构建（依赖私有 API 或第三方库，见 README 的能力矩阵）", module] };
}

static NSDictionary *YKDispatch(NSString *method, NSString *path,
                                NSDictionary *body, NSDictionary *query, NSString **err) {
    NSArray *segs = [path componentsSeparatedByString:@"/"];
    NSMutableArray *s = [NSMutableArray array];
    for (NSString *x in segs) if (x.length) [s addObject:x];
    NSString *head = s.count ? s[0] : @"";
    // ---- touch（root 进程内直接 IOHID 注入）----
    if ([head isEqualToString:@"touch"]) {
        NSString *v = s.count > 1 ? s[1] : @"ping";
        double x = [body[@"x"] doubleValue], y = [body[@"y"] doubleValue];
        if (body[@"clientType"]) {
            int nt = [body[@"clientType"] intValue];
            gYkClientType = nt;
        }
        // sender 显式传入才覆盖；未传 = 沿用持久化/自动解析的 senderID
        // （清空 senderID 会让 SpringBoard 收到事件却不派发给任何窗口）
        if (body[@"sender"]) gYkSenderID = [body[@"sender"] unsignedLongLongValue];
        if ([v isEqualToString:@"tap"])       return YkTouchTap(x, y);
        if ([v isEqualToString:@"longPress"])  return YkTouchLongPress(x, y, [body[@"duration"] doubleValue]);
        if ([v isEqualToString:@"swipe"])      return YkTouchSwipe(x, y,
                                                   [body[@"toX"] doubleValue],
                                                   [body[@"toY"] doubleValue],
                                                   [body[@"duration"] doubleValue],
                                                   [body[@"steps"] integerValue] ?: 12);
        if ([v isEqualToString:@"doubleTap"])  return YkTouchDoubleTap(x, y, [body[@"gap"] doubleValue]);
        if ([v isEqualToString:@"home"])        return YkTouchHome(body[@"count"] ? [body[@"count"] intValue] : 1,
                                                                   [body[@"hold"] doubleValue]);
        if ([v isEqualToString:@"pinch"]) {
            NSArray *a = body[@"startPoints"], *b = body[@"endPoints"];
            if (a.count == 2 && b.count == 2)
                return YkTouchPinch([a[0][@"x"] doubleValue], [a[0][@"y"] doubleValue],
                                    [b[0][@"x"] doubleValue], [b[0][@"y"] doubleValue],
                                    [a[1][@"x"] doubleValue], [a[1][@"y"] doubleValue],
                                    [b[1][@"x"] doubleValue], [b[1][@"y"] doubleValue],
                                    [body[@"duration"] doubleValue],
                                    [body[@"steps"] integerValue]);
            // 兼容：ex1/ey1/ex2/ey2 平铺写法
            if (body[@"ex1"])
                return YkTouchPinch(x, y,
                                    [body[@"ex1"] doubleValue], [body[@"ey1"] doubleValue],
                                    [body[@"x2"] doubleValue], [body[@"y2"] doubleValue],
                                    [body[@"ex2"] doubleValue], [body[@"ey2"] doubleValue],
                                    [body[@"duration"] doubleValue],
                                    [body[@"steps"] integerValue]);
            return @{ @"value.error": @"bad_request",
                      @"value.message": @"pinch 需要 startPoints/endPoints 各两点" };
        }
        if ([v isEqualToString:@"sequence"])
            return YkTouchSequence(body[@"points"] ?: body[@"events"],
                                   [body[@"delayMs"] doubleValue]);
        if ([v isEqualToString:@"showTouches"])
            return @{ @"value": @{ @"ok": @YES, @"supported": @NO,
                                   @"note": @"Lite 不含触摸可视化层（原版 YKPointRadius）" } };
        if ([v isEqualToString:@"ping"])       return @{ @"value": @{ @"ok": @YES, @"pid": @(getpid()) } };
        if ([v isEqualToString:@"loopback"])   return YkLoopbackTest(x, y);
        if ([v isEqualToString:@"capture"])    return YkTouchCaptureInfo();
        if ([v isEqualToString:@"arm"])        return YkRecordArm();
        if ([v isEqualToString:@"status"])     return YkRecordStatus();
        if ([v isEqualToString:@"replay"])     return YkReplayAtRaw(x, y, body[@"raw"] ? [body[@"raw"] intValue] : 0);
        return @{ @"value.error": @"not_found", @"value.message": v };
    }



    // ---- 服务级 ----
    if ([path isEqualToString:@"/health"]) {
        return @{ @"value": @{ @"state": @"ready", @"ready": @YES,
                               @"message": @"YKEngineLite HTTP 服务可用",
                               @"engine": @"reconstructed",
                               @"limits": @{ @"maxJSONBodyBytes": @(16 * 1024 * 1024) },
                               @"localPort": @(YKListenPort()) } };
    }
    if ([path isEqualToString:@"/routes"]) {
        return @{ @"value": @{ @"schemaVersion": @"lite-1.0",
                               @"count": @(0),
                               @"note": @"Lite 构建不暴露完整 route registry；请以设备实测 /routes 为准" } };
    }
    if ([head isEqualToString:@"session"]) {
        if ([path isEqualToString:@"/session/create"]) {
            NSString *sid = [NSString stringWithFormat:@"sess_%.0f_%@",
                             [[NSDate date] timeIntervalSince1970] * 1000,
                             [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""]];
            return @{ @"value": @{ @"sessionId": sid, @"state": @"active", @"name": @"default" } };
        }
        return @{ @"value": @{ @"state": @"active" } };
    }

    // ---- 文件 ----
    if ([head isEqualToString:@"file"]) {
        NSString *verb = s.count > 1 ? s[1] : @"";
        NSString *p = body[@"path"] ?: query[@"path"];
        if ([verb isEqualToString:@"exists"]) return [YKFileModule exists:p];
        if ([verb isEqualToString:@"size"])   return [YKFileModule size:p];
        if ([verb isEqualToString:@"read"])   return [YKFileModule read:p];
        if ([verb isEqualToString:@"write"])  return [YKFileModule write:p data:body[@"data"] append:NO];
        if ([verb isEqualToString:@"append"]) return [YKFileModule write:p data:body[@"data"] append:YES];
        if ([verb isEqualToString:@"remove"]) return [YKFileModule remove:p];
        if ([verb isEqualToString:@"list"])   return [YKFileModule list:p ?: @"/"];
        if ([verb isEqualToString:@"lines"])  return [YKFileModule linesOfFile:p];
        if ([verb isEqualToString:@"lineCount"]) return [YKFileModule lineCount:p];
        if ([verb isEqualToString:@"md5"])    return [YKFileModule digest:p algo:@"md5"];
        if ([verb isEqualToString:@"sha1"])   return [YKFileModule digest:p algo:@"sha1"];
        if ([verb isEqualToString:@"sha256"]) return [YKFileModule digest:p algo:@"sha256"];
        if ([verb isEqualToString:@"sha512"]) return [YKFileModule digest:p algo:@"sha512"];
        return YKNotPorted(@"file");
    }

    // ---- 偏好 ----
    if ([head isEqualToString:@"prefs"]) {
        NSString *verb = s.count > 1 ? s[1] : @"";
        NSString *k = body[@"key"] ?: query[@"key"];
        NSString *ns = body[@"namespace"] ?: query[@"namespace"];
        if ([verb isEqualToString:@"get"])  return [YKPrefsModule get:k namespace:ns];
        if ([verb isEqualToString:@"set"])  return [YKPrefsModule set:body[@"value"] key:k namespace:ns];
        if ([verb isEqualToString:@"has"])  return [YKPrefsModule has:k namespace:ns];
        if ([verb isEqualToString:@"keys"]) return [YKPrefsModule keys:ns];
        if ([verb isEqualToString:@"all"])  return [YKPrefsModule all:ns];
        if ([verb isEqualToString:@"namespaces"]) return [YKPrefsModule namespaces];
        return YKNotPorted(@"prefs");
    }

    // ---- plist ----
    if ([head isEqualToString:@"plist"]) {
        NSString *p = body[@"path"] ?: query[@"path"];
        if ([s containsObject:@"read"]) return [YKPlistModule read:p];
        if ([s containsObject:@"dump"]) return [YKPlistModule dump:p];
        return YKNotPorted(@"plist");
    }

    // ---- 屏幕（按 verb 分派，对齐实测：info/size/scale/dpi/width/height/orientation）----
    if ([head isEqualToString:@"screen"]) {
        NSString *verb = s.count > 1 ? s[1] : @"info";
        NSDictionary *info = [YKScreenModule info];
        NSDictionary *v = info[@"value"] ?: info;
        if ([verb isEqualToString:@"info"] || [verb isEqualToString:@"all"]) return info;
        if ([verb isEqualToString:@"size"]) return @{ @"value": @{ @"width": v[@"width"] ?: @0,
                                                                    @"height": v[@"height"] ?: @0 } };
        if ([verb isEqualToString:@"width"]) return @{ @"value": v[@"width"] ?: @0 };
        if ([verb isEqualToString:@"height"]) return @{ @"value": v[@"height"] ?: @0 };
        if ([verb isEqualToString:@"scale"]) return @{ @"value": v[@"scale"] ?: @1 };
        if ([verb isEqualToString:@"dpi"]) return @{ @"value": v[@"dpi"] ?: @163 };
        if ([verb isEqualToString:@"orientation"]) return @{ @"value": v[@"orientation"] ?: @0 };
        return info;
    }

    // ---- 加密 ----
    if ([head isEqualToString:@"crypto"]) {
        NSString *verb = [[s subarrayWithRange:NSMakeRange(1, s.count - 1)] componentsJoinedByString:@"/"];
        return [YKCryptoModule dispatch:verb body:body ?: @{}];
    }

    // ---- 网络 ----
    if ([head isEqualToString:@"network"]) {
        NSString *verb = s.count > 1 ? s[1] : @"";
        if ([verb isEqualToString:@"get"])      return [YKNetworkModule request:body method:@"GET"];
        if ([verb isEqualToString:@"postJSON"] || [verb isEqualToString:@"postForm"] ||
            [verb isEqualToString:@"request"])  return [YKNetworkModule request:body method:@"POST"];
        if ([verb isEqualToString:@"cookies"])  return [YKNetworkModule cookies];
        if ([verb isEqualToString:@"proxy"])    return [YKNetworkModule proxy];
        return YKNotPorted(@"network");
    }

    // ---- 动态 UI ----
    if ([head isEqualToString:@"ui"]) {
        NSString *e = nil;
        NSDictionary *r = [[YKUIDispatcher shared] dispatchMethod:method path:path body:body error:&e];
        return r ?: @{ @"value.error": e ?: @"ui_error", @"value.message": @"UI 派发失败" };
    }

    // ---- 系统（root 守护进程才有的能力）----
    if ([head isEqualToString:@"system"]) {
        NSString *verb = s.count > 1 ? s[1] : @"";
        if ([verb isEqualToString:@"respring"]) {
            BOOL viaTool = NO;
            NSString *killall = YkFindTool(@"killall");
            if (killall) { viaTool = YES; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(0, 0), ^{
                if (viaTool) {
                    YkSpawnWait(killall, @[@"-9", @"backboardd"]);
                    YkSpawnWait(killall, @[@"-9", @"SpringBoard"]);
                } else {
                    YkRunCmd(@"killall -9 backboardd 2>/dev/null || killall -9 SpringBoard 2>/dev/null");
                }
            });
            return @{ @"value": @{ @"ok": @YES, @"action": @"respring" } };
        }
        if ([verb isEqualToString:@"install"]) {
            NSString *path = body[@"path"] ?: @"";
            if (![[NSFileManager defaultManager] fileExistsAtPath:path])
                return @{ @"value.error": @"not_found", @"value.message": @"deb 不存在" };
            NSString *dpkg = YkFindTool(@"dpkg");
            if (!dpkg)
                return @{ @"value.error": @"no_dpkg", @"value.message": @"找不到 dpkg" };
            int rc = YkSpawnWait(dpkg, @[@"-i", path]);
            return @{ @"value": @{ @"ok": @(rc == 0), @"exit": @(rc), @"dpkg": dpkg } };
        }
        if ([verb isEqualToString:@"shell"]) {
            NSString *cmd = body[@"command"] ?: @"";
            if (!cmd.length) return @{ @"value.error": @"bad_request", @"value.message": @"缺少 command" };
            NSString *outPath = @"/var/mobile/Media/_daemon_sh.out";
            NSString *sh = YkShellPath();
            NSString *root = YkRootPath() ?: @"<nil>";
            [[NSFileManager defaultManager] removeItemAtPath:outPath error:NULL];
            NSString *full = [NSString stringWithFormat:
                              @"( %@ ) > %@ 2>&1; echo $? >> %@", cmd, outPath, outPath];
            YkRunCmd(full);
            NSString *out = [NSString stringWithContentsOfFile:outPath
                                                      encoding:NSUTF8StringEncoding error:NULL] ?: @"";
            return @{ @"value": @{ @"output": out, @"exitCode": @0,
                                   @"sh": sh ?: @"<nil>", @"root": root,
                                   @"outFile": @([[NSFileManager defaultManager]
                                                 fileExistsAtPath:outPath]),
                                   @"spawnRC": @(gYkLastSpawnRC) } };
        }
        if ([verb isEqualToString:@"service"]) {
            if (body[@"on"] != nil) {
                BOOL want = [body[@"on"] boolValue];
                YkSetServiceRunning(want);
                return @{ @"value": @{ @"ok": @YES, @"on": @(want) } };
            }
            return @{ @"value": @{ @"on": @(YkServiceRunning()), @"port": @(65323) } };
        }
    }

    // ---- 录制（root 侧执行注入）----
    if ([head isEqualToString:@"record"]) {
        NSString *verb = s.count > 1 ? s[1] : @"";
        NSString *dir = @"/var/mobile/Library/YKEngineLite/records";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        if ([verb isEqualToString:@"list"] || [verb isEqualToString:@"records"]) {
            NSMutableArray *arr = [NSMutableArray array];
            NSArray *fs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
            for (NSString *f in fs) {
                if (![f.pathExtension isEqualToString:@"json"]) continue;
                NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:
                                   [dir stringByAppendingPathComponent:f]];
                if (d) [arr addObject:d];
            }
            return @{ @"value": @{ @"records": arr, @"count": @(arr.count) } };
        }
        if ([verb isEqualToString:@"save"]) {
            NSArray *steps = body[@"steps"] ?: body[@"points"];
            if (![steps isKindOfClass:[NSArray class]] || !steps.count)
                return @{ @"value.error": @"bad_request", @"value.message": @"steps 为空" };
            NSString *rid = body[@"id"] ?: [NSString stringWithFormat:@"rec_%.0f",
                                            [[NSDate date] timeIntervalSince1970] * 1000];
            NSDictionary *rec = @{ @"id": rid,
                                   @"name": body[@"name"] ?: @"未命名",
                                   @"duration": body[@"duration"] ?: @0,
                                   @"count": @(steps.count),
                                   @"createdAt": @([[NSDate date] timeIntervalSince1970]),
                                   @"steps": steps };
            NSString *path = [dir stringByAppendingPathComponent:
                              [rid stringByAppendingString:@".json"]];
            [rec writeToFile:path atomically:YES];
            return @{ @"value": @{ @"ok": @YES, @"id": rid, @"count": @(steps.count) } };
        }
        if ([verb isEqualToString:@"remove"] || [verb isEqualToString:@"delete"]) {
            NSString *rid = body[@"id"] ?: @"";
            NSString *path = [dir stringByAppendingPathComponent:
                              [rid stringByAppendingString:@".json"]];
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return @{ @"value": @{ @"ok": @YES, @"id": rid } };
        }
        if ([verb isEqualToString:@"play"] || [verb isEqualToString:@"playback"]) {
            NSString *rid = body[@"id"] ?: @"";
            int times = body[@"times"] ? [body[@"times"] intValue] : 1;
            if (times < 1) times = 1;
            NSString *path = [dir stringByAppendingPathComponent:
                              [rid stringByAppendingString:@".json"]];
            NSDictionary *rec = [NSDictionary dictionaryWithContentsOfFile:path];
            NSArray *steps = rec[@"steps"];
            if (![steps isKindOfClass:[NSArray class]] || !steps.count)
                return @{ @"value.error": @"not_found", @"value.message": @"录制不存在" };
            int delayMs = body[@"delayMs"] ? [body[@"delayMs"] intValue] : 0;
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                if (delayMs > 0) usleep((useconds_t)delayMs * 1000);
                for (int t = 0; t < times; t++) {
                    YkTouchSequence(steps, 16);
                    usleep(200000);
                }
            });
            return @{ @"value": @{ @"ok": @YES, @"id": rid, @"times": @(times) } };
        }
    }

    // ---- 未移植 ----
    if ([@[@"touch", @"element", @"image", @"ocr", @"yolo", @"device", @"system",
           @"app", @"record", @"vpn", @"keyboard", @"archive", @"internal", @"wda",
           @"executor"] containsObject:head]) {
        return YKNotPorted(head);
    }
    (void)err;
    return @{ @"value.error": @"not_found", @"value.message": @"未处理的路由" };
}

#pragma mark - 入口

int main(int argc, char *argv[]) {
    @autoreleasepool { YkHIDBoot(); }
    @autoreleasepool {
        // 关键：忽略 SIGPIPE，否则向已关闭连接 write() 会直接杀死进程
        signal(SIGPIPE, SIG_IGN);
        NSLog(@"[YKEngineLite] boot, port=%u", YKListenPort());

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{ YkEnsureIcon(); });

        HTTPServer *server = [HTTPServer new];
        gYKServiceServer = server;
        server.port = YKListenPort();
        server.interface = @"any";
        server.requiresSessionHeader = NO;

        // 逐模块注册（路由表来自 Recovered/YKRoutesLive.m 的实测清单；
        // 这里用通配 handler 统一分派，避免 589 个 block）
        NSArray *modules = @[@"file", @"prefs", @"plist", @"screen", @"crypto", @"network",
                             @"ui", @"touch", @"element", @"image", @"ocr", @"yolo",
                             @"device", @"system", @"app", @"record", @"vpn", @"keyboard",
                             @"archive", @"internal", @"wda", @"executor", @"session"];
        for (NSString *m in modules) {
            [server post:[NSString stringWithFormat:@"/%@/*", m] withBlock:^(RouteRequest *req, RouteResponse *res) {
                NSDictionary *out = YKDispatch(req.method, req.path, [req jsonBody] ?: @{},
                                               req.query, NULL);
                id inner = out[@"value"];
                if ([inner isKindOfClass:[NSDictionary class]] && inner[@"error"]) res.statusCode = 400;
                [res respondWithJSON:out];
            }];
            [server get:[NSString stringWithFormat:@"/%@/*", m] withBlock:^(RouteRequest *req, RouteResponse *res) {
                NSDictionary *out = YKDispatch(req.method, req.path, @{}, req.query, NULL);
                id inner = out[@"value"];
                if ([inner isKindOfClass:[NSDictionary class]] && inner[@"error"]) res.statusCode = 400;
                [res respondWithJSON:out];
            }];
        }
        [server get:@"/health" withBlock:^(RouteRequest *req, RouteResponse *res) {
            [res respondWithJSON:YKDispatch(@"GET", @"/health", @{}, @{}, NULL)];
        }];
        [server get:@"/routes" withBlock:^(RouteRequest *req, RouteResponse *res) {
            [res respondWithJSON:YKDispatch(@"GET", @"/routes", @{}, @{}, NULL)];
        }];
        [server post:@"/session/create" withBlock:^(RouteRequest *req, RouteResponse *res) {
            [res respondWithJSON:YKDispatch(@"POST", @"/session/create", @{}, @{}, NULL)];
        }];
        [server setDefaultHandler:^(RouteRequest *req, RouteResponse *res) {
            NSDictionary *out = YKDispatch(req.method, req.path, [req jsonBody] ?: @{}, req.query, NULL);
            id inner = out[@"value"];
            if ([inner isKindOfClass:[NSDictionary class]] && inner[@"error"]) {
                res.statusCode = [inner[@"error"] isEqualToString:@"not_found"] ? 404 : 400;
            }
            [res respondWithJSON:out];
        }];

        NSError *err = nil;
        if (![server start:&err]) {
            NSLog(@"[YKEngineLite] service port start failed: %@", err);
        }

        // ---- 控制端口（常量 65325）：服务开关 / 重启用户空间 / shell / 录制 ----
        HTTPServer *ctl = [HTTPServer new];
        ctl.port = 65325;
        ctl.interface = @"any";
        ctl.requiresSessionHeader = NO;
        void (^ctlHandler)(RouteRequest *, RouteResponse *) = ^(RouteRequest *req, RouteResponse *res) {
            NSDictionary *out = YKDispatch(req.method, req.path, [req jsonBody] ?: @{}, req.query, NULL);
            id inner = out[@"value"];
            if ([inner isKindOfClass:[NSDictionary class]] && inner[@"error"]) res.statusCode = 400;
            [res respondWithJSON:out];
        };
        for (NSString *m in @[@"system", @"record", @"touch", @"file", @"prefs"]) {
            [ctl post:[NSString stringWithFormat:@"/%@/*", m] withBlock:ctlHandler];
            [ctl get:[NSString stringWithFormat:@"/%@/*", m] withBlock:ctlHandler];
        }
        [ctl get:@"/health" withBlock:ctlHandler];
        [ctl setDefaultHandler:ctlHandler];
        NSError *cerr = nil;
        if (![ctl start:&cerr]) NSLog(@"[YKEngineLite] control port start failed: %@", cerr);
        // 端口落盘，便于外部探测
        [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/YKEngineLite"
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSString stringWithFormat:@"%u", server.port]
            writeToFile:@"/var/mobile/Library/YKEngineLite/http_port"
             atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
