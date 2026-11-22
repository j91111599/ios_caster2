//
//  main.m — YKEngineLite 入口（重建引擎的自托管版本）
//
//  设计：
//    · 监听 127.0.0.1:65323（避开原版 65322），可改 /var/mobile/Library/YKEngineLite/config.plist
//    · 复用 Recovered/ 里的重建模块：HTTP 路由 / 文件 / 偏好 / plist / 屏幕 / 加密 / UI / 录制
//    · 未移植模块（触控注入、元素树、OCR、装包）返回 501 并给出原因
//    · 响应包封与鉴权对齐设备实测（见 PROTOCOL_FINAL.md）
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <signal.h>
#import "YKHTTPServerCompat.h"

// 模块入口（来自 Recovered/*.m）
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

    // ---- 屏幕 ----
    if ([head isEqualToString:@"screen"]) return [YKScreenModule info];

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
    @autoreleasepool {
        NSLog(@"[YKEngineLite] boot, port=%u", YKListenPort());

        HTTPServer *server = [HTTPServer new];
        server.port = YKListenPort();
        server.interface = @"loopback";
        server.requiresSessionHeader = NO;

        // 逐模块注册（路由表来自 Recovered/YKRoutesLive.m 的实测清单；
        // 这里用通配 handler 统一分派，避免 589 个 block）
        NSArray *modules = @[@"file", @"prefs", @"plist", @"screen", @"crypto", @"network",
                             @"ui", @"touch", @"element", @"image", @"ocr", @"yolo",
                             @"device", @"system", @"app", @"record", @"vpn", @"keyboard",
                             @"archive", @"internal", @"wda", @"executor", @"session"];
        for (NSString *m in modules) {
            [server post:[NSString stringWithFormat:@"/%@/*", m] withBlock:^(RouteRequest *req, RouteResponse *res) {
                NSDictionary *out = YKDispatch(req.method, req.path, [req jsonBody] ?: req.query ?: @{},
                                               req.query, NULL);
                if (out[@"value.error"]) {
                    res.statusCode = 400;
                    [res respondWithJSON:out];
                } else {
                    [res respondWithJSON:out];
                }
            }];
            [server get:[NSString stringWithFormat:@"/%@/*", m] withBlock:^(RouteRequest *req, RouteResponse *res) {
                NSDictionary *out = YKDispatch(req.method, req.path, @{}, req.query, NULL);
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
            [res respondWithJSON:out];
        }];

        NSError *err = nil;
        if (![server start:&err]) {
            NSLog(@"[YKEngineLite] start failed: %@", err);
            return 1;
        }
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
