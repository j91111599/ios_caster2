//
//  YKHTTPRouter.m — 本地 HTTP 路由层重建（P0 模块 #2）
//
//  来源：com.sky.ykpro 3.9.5 / YKEngine
//  证据：
//    1. 路由协议类 `pQWnQWv7JVoV6VzVB0lwD1BY5MykxMMo` 的类方法：
//       +routes / +shouldRegisterAutomatically / +unhandledHandler:
//       其协议名（混淆）kOysH9cDGTxtrzmsMlyLBWHoVlqejBxT → 本文件命名为 YKRouteModule
//    2. 各模块类（如 app 模块 `LCc5TApSdFmJYaMM9Vei9kCHgGBYpWci`）的 +routes 返回
//       (HTTP 方法, 路径, 处理 selector) 三元组；app 模块共 14 条，全部 POST
//    3. 参数解析辅助方法（selector 原文）：
//       +trimmedRequiredStringForKey:request:response:emptyMessage:
//       +optionalStringForKey:request:response:emptyAllowed:
//       +optionalIntegerForKey:request:response:
//       +requiredIntegerForKey:request:response:
//       +requiredIdentifierForRequest:response:
//       +requiredPathTypeForRequest:response:      // 取值 none / application_manager
//       +requiredURLStringForRequest:response:
//    4. 响应构造：+operationResultWithSuccess:message: / +invalidArgument:
//       JSON 形状：{"success": bool, "message": "..."}（常量 success / message 可见）
//    5. 服务器实现为 RoutingHTTPServer 派生（HTTPServer / RouteRequest / RouteResponse）
//    6. 自定义头（CORS allow-list 原文）：
//       X-YK-Session-Id, X-YK-Request-Id, X-YK-Executor-Job-Id, X-YK-Remote-Authorization
//
//  说明：路由表、参数键、响应形状来自二进制；方法体为按语义重建（标 [推断] 处为推断）。
//

#import <Foundation/Foundation.h>
#import "HTTPServer.h"
#import "RouteRequest.h"
#import "RouteResponse.h"

@class YKRouteResponse;

#pragma mark - 路由协议（原 kOysH9cDGTxtrzmsMlyLBWHoVlqejBxT）

@protocol YKRouteModule <NSObject>
+ (BOOL)shouldRegisterAutomatically;
+ (NSArray<NSArray<NSString *> *> *)routes;      // @[ @[method, path, handlerSel], ... ]
+ (id)unhandledHandler:(id)request;
@end

#pragma mark - 参数解析错误

@interface YKArgumentError : NSObject
@property (nonatomic, copy) NSString *message;
+ (instancetype)withMessage:(NSString *)msg;
@end
@implementation YKArgumentError
+ (instancetype)withMessage:(NSString *)msg {
    YKArgumentError *e = [YKArgumentError new];
    e.message = msg;
    return e;
}
@end

#pragma mark - 响应构造（原 +operationResultWithSuccess:message: / +invalidArgument:）

static NSDictionary *YKOperationResult(BOOL ok, NSString *message) {
    return @{ @"success": @(ok), @"message": message ?: @"" };
}

static void YKRespondJSON(RouteResponse *response, NSDictionary *payload) {
    response.statusCode = 200;
    [response setHeader:@"Content-Type" value:@"application/json; charset=utf-8"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    [response respondWithData:data];
}

static void YKRespondError(RouteResponse *response, NSString *message) {
    NSString *m = message.length ? message : @"参数错误";
    YKRespondJSON(response, YKOperationResult(NO, m));
}

#pragma mark - 请求上下文（封装 X-YK-* 头）

@interface YKRequestContext : NSObject
@property (nonatomic, copy)   NSString *sessionId;
@property (nonatomic, copy)   NSString *requestId;
@property (nonatomic, copy)   NSString *executorJobId;
@property (nonatomic, copy)   NSString *remoteAuthorization;
@property (nonatomic, strong) RouteRequest *request;
@property (nonatomic, strong) RouteResponse *response;
@property (nonatomic, strong) NSDictionary *body;      // JSON body（GET 时为 query）
@end

@implementation YKRequestContext
+ (instancetype)contextWithRequest:(RouteRequest *)req response:(RouteResponse *)res {
    YKRequestContext *c = [YKRequestContext new];
    c.request = req;
    c.response = res;
    c.sessionId           = [req header:@"X-YK-Session-Id"];
    c.requestId           = [req header:@"X-YK-Request-Id"];
    c.executorJobId       = [req header:@"X-YK-Executor-Job-Id"];
    c.remoteAuthorization = [req header:@"X-YK-Remote-Authorization"];
    NSData *body = [req body];
    if (body.length) {
        id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
        if ([json isKindOfClass:[NSDictionary class]]) {
            c.body = json;
        }
    }
    if (!c.body) {
        c.body = [req query] ?: @{};                   // [推断] query 作为兜底
    }
    return c;
}
@end

#pragma mark - app 模块（原 LCc5TApSdFmJYaMM9Vei9kCHgGBYpWci）

@interface YKAppRouteModule : NSObject <YKRouteModule>
@end

@implementation YKAppRouteModule

+ (BOOL)shouldRegisterAutomatically { return YES; }

+ (NSArray<NSArray<NSString *> *> *)routes {
    // 原文顺序（字符串常量顺序即为注册顺序）
    return @[
        @[@"POST", @"/app/install",        @"handleInstall:"],
        @[@"POST", @"/app/uninstall",      @"handleUninstall:"],
        @[@"POST", @"/app/shake",          @"handleShake:"],
        @[@"GET", @"/app/info",           @"handleInfo:"],
        @[@"POST", @"/app/run",            @"handleRun:"],
        @[@"POST", @"/app/close",          @"handleClose:"],
        @[@"GET", @"/app/list",           @"handleList:"],
        @[@"POST", @"/app/clearSandbox",   @"handleClearSandbox:"],
        @[@"POST", @"/app/clearKeychain",  @"handleClearKeychain:"],
        @[@"GET", @"/app/path",           @"handlePath:"],
        @[@"GET", @"/app/frontBid",       @"handleFrontBid:"],
        @[@"GET", @"/app/frontInfo",      @"handleFrontInfo:"],
        @[@"GET", @"/app/pid",            @"handlePid:"],
        @[@"GET", @"/app/usedMemory",     @"handleUsedMemory:"],
    ];
}

+ (id)unhandledHandler:(id)request {
    return YKOperationResult(NO, @"未处理的接口");
}

#pragma mark 参数辅助（与二进制里的 selector 一一对应）

+ (NSString *)trimmedRequiredStringForKey:(NSString *)key
                                  request:(YKRequestContext *)ctx
                                 response:(RouteResponse *)response
                             emptyMessage:(NSString *)emptyMsg {
    id v = ctx.body[key];
    NSString *s = [v isKindOfClass:[NSString class]] ? [v stringByTrimmingCharactersInSet:
                                                       [NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
    if (!s.length) {
        YKRespondError(response, emptyMsg ?: [NSString stringWithFormat:@"缺少参数 %@", key]);
        return nil;
    }
    return s;
}

+ (NSString *)optionalStringForKey:(NSString *)key
                           request:(YKRequestContext *)ctx
                          response:(RouteResponse *)response
                      emptyAllowed:(BOOL)allowed {
    id v = ctx.body[key];
    if (!v) return nil;
    if (![v isKindOfClass:[NSString class]]) {
        YKRespondError(response, [NSString stringWithFormat:@"参数 %@ 类型错误", key]);
        return nil;
    }
    return v;
}

+ (NSNumber *)requiredIntegerForKey:(NSString *)key
                            request:(YKRequestContext *)ctx
                           response:(RouteResponse *)response {
    id v = ctx.body[key];
    if (![v respondsToSelector:@selector(integerValue)] || [v isKindOfClass:[NSString class]]) {
        YKRespondError(response, [NSString stringWithFormat:@"参数 %@ 必须是整数", key]);
        return nil;
    }
    return @([v integerValue]);
}

+ (NSNumber *)optionalIntegerForKey:(NSString *)key
                            request:(YKRequestContext *)ctx
                           response:(RouteResponse *)response {
    id v = ctx.body[key];
    return [v respondsToSelector:@selector(integerValue)] ? @([v integerValue]) : nil;
}

// 取值 evidence: none / application_manager
+ (NSString *)requiredPathTypeForRequest:(YKRequestContext *)ctx response:(RouteResponse *)response {
    NSString *t = [self optionalStringForKey:@"type" request:ctx response:response emptyAllowed:NO];
    if (!t) return nil;
    if (![t isEqualToString:@"none"] && ![t isEqualToString:@"application_manager"]) {
        YKRespondError(response, @"type 仅支持 none / application_manager");
        return nil;
    }
    return t;
}

+ (NSString *)requiredURLStringForRequest:(YKRequestContext *)ctx response:(RouteResponse *)response {
    return [self trimmedRequiredStringForKey:@"url" request:ctx response:response
                               emptyMessage:@"url 不能为空"];
}

+ (NSString *)requiredIdentifierForRequest:(YKRequestContext *)ctx response:(RouteResponse *)response {
    return [self trimmedRequiredStringForKey:@"bundleId" request:ctx response:response
                               emptyMessage:@"bundleId 不能为空"];
}

#pragma mark 业务处理（调用引擎原语；标 [推断] 的为按语义重建）

+ (void)handleInfo:(YKRequestContext *)ctx {
    NSString *bid = [self requiredIdentifierForRequest:ctx response:ctx.response];
    if (!bid) return;
    NSDictionary *info = YKAppInformationForBundle(bid);          // 引擎侧原语
    if (!info) { YKRespondError(ctx.response, @"应用不存在"); return; }
    NSMutableDictionary *r = [YKOperationResult(YES, @"") mutableCopy];
    [r addEntriesFromDictionary:info];
    YKRespondJSON(ctx.response, r);
}

+ (void)handleRun:(YKRequestContext *)ctx {
    NSString *bid = [self requiredIdentifierForRequest:ctx response:ctx.response];
    if (!bid) return;
    NSString *pathType = [self requiredPathTypeForRequest:ctx response:ctx.response];
    if (!pathType) return;
    BOOL ok = YKOpenApplication(bid, pathType);                    // LSApplicationWorkspace
    YKRespondJSON(ctx.response, YKOperationResult(ok, ok ? @"已启动" : @"启动失败"));
}

+ (void)handleClose:(YKRequestContext *)ctx {
    NSString *bid = [self requiredIdentifierForRequest:ctx response:ctx.response];
    if (!bid) return;
    BOOL ok = YKTerminateApplication(bid);
    YKRespondJSON(ctx.response, YKOperationResult(ok, ok ? @"已关闭" : @"关闭失败"));
}

+ (void)handleList:(YKRequestContext *)ctx {
    NSArray *apps = YKInstalledApplications();                     // 引擎侧原语
    NSMutableDictionary *r = [YKOperationResult(YES, @"") mutableCopy];
    r[@"apps"] = apps ?: @[];
    YKRespondJSON(ctx.response, r);
}

+ (void)handleInstall:(YKRequestContext *)ctx {
    NSString *path = [self trimmedRequiredStringForKey:@"path" request:ctx response:ctx.response
                                          emptyMessage:@"path 不能为空"];
    if (!path) return;
    // 常量证据：deb / ipa / tipa；状态回流见 YKPackageInstallerKit
    NSString *ext = path.pathExtension.lowercaseString;
    if (![@[@"deb", @"ipa", @"tipa"] containsObject:ext]) {
        YKRespondError(ctx.response, @"不支持该软件");
        return;
    }
    [YKPackageInstaller enqueueInstallAtPath:path
                                        type:ext
                                  completion:^(BOOL ok, NSString *msg) {
        YKRespondJSON(ctx.response, YKOperationResult(ok, msg));
    }];
}

+ (void)handleUninstall:(YKRequestContext *)ctx {
    NSString *bid = [self requiredIdentifierForRequest:ctx response:ctx.response];
    if (!bid) return;
    [YKPackageInstaller uninstallBundle:bid completion:^(BOOL ok, NSString *msg) {
        YKRespondJSON(ctx.response, YKOperationResult(ok, msg));
    }];
}

+ (void)handleShake:(YKRequestContext *)ctx {
    YKPostShakeEvent();                                            // UIEvent shake 合成
    YKRespondJSON(ctx.response, YKOperationResult(YES, @""));
}

+ (void)handleClearSandbox:(YKRequestContext *)ctx {
    NSString *bid = [self requiredIdentifierForRequest:ctx response:ctx.response];
    if (!bid) return;
    BOOL ok = YKClearContainerForBundle(bid);
    YKRespondJSON(ctx.response, YKOperationResult(ok, ok ? @"已清理" : @"清理失败"));
}

+ (void)handleClearKeychain:(YKRequestContext *)ctx {
    NSString *bid = [self requiredIdentifierForRequest:ctx response:ctx.response];
    if (!bid) return;
    BOOL ok = YKClearKeychainForBundle(bid);
    YKRespondJSON(ctx.response, YKOperationResult(ok, ok ? @"已清理" : @"清理失败"));
}

+ (void)handlePath:(YKRequestContext *)ctx {
    NSString *bid = [self requiredIdentifierForRequest:ctx response:ctx.response];
    if (!bid) return;
    NSString *p = YKDataContainerPathForBundle(bid);               // [推断] 返回沙盒路径
    NSMutableDictionary *r = [YKOperationResult(YES, @"") mutableCopy];
    r[@"path"] = p ?: @"";
    YKRespondJSON(ctx.response, r);
}

+ (void)handleFrontBid:(YKRequestContext *)ctx {
    NSMutableDictionary *r = [YKOperationResult(YES, @"") mutableCopy];
    r[@"frontBid"] = YKFrontmostBundleIdentifier() ?: @"";         // 前台 App
    YKRespondJSON(ctx.response, r);
}

+ (void)handleFrontInfo:(YKRequestContext *)ctx {
    NSMutableDictionary *r = [YKOperationResult(YES, @"") mutableCopy];
    // 常量证据：cachedFrontPid / display_layout / monitor_fallback / frontBid / pidSource
    r[@"frontBid"]        = YKFrontmostBundleIdentifier() ?: @"";
    r[@"cachedFrontPid"]  = @(YKFrontmostPID());
    r[@"display_layout"]  = YKDisplayLayoutDescription();
    r[@"monitor_fallback"] = @NO;
    YKRespondJSON(ctx.response, r);
}

+ (void)handlePid:(YKRequestContext *)ctx {
    NSString *bid = [self requiredIdentifierForRequest:ctx response:ctx.response];
    if (!bid) return;
    NSMutableDictionary *r = [YKOperationResult(YES, @"") mutableCopy];
    r[@"pid"] = @(YKPIDForBundle(bid));
    r[@"pidSource"] = @"application_manager";                      // 常量证据
    YKRespondJSON(ctx.response, r);
}

+ (void)handleUsedMemory:(YKRequestContext *)ctx {
    NSString *bid = [self requiredIdentifierForRequest:ctx response:ctx.response];
    if (!bid) return;
    NSMutableDictionary *r = [YKOperationResult(YES, @"") mutableCopy];
    // 常量证据：usedMemory / unit / MB
    r[@"usedMemory"] = @(YKResidentMemoryForBundle(bid));
    r[@"unit"]       = @"MB";
    YKRespondJSON(ctx.response, r);
}

@end

#pragma mark - 服务器装配

@interface YKHTTPRouter : NSObject
+ (void)startWithPort:(uint16_t)port;
@end

@implementation YKHTTPRouter

+ (void)startWithPort:(uint16_t)port {
    HTTPServer *server = [[HTTPServer alloc] init];
    server.type = @"_http._tcp.";
    server.port = port;
    server.interface = @"loopback";                                // 仅 127.0.0.1

    static NSMutableDictionary *handlers;                           // path -> handler block
    handlers = [NSMutableDictionary dictionary];

    Class modules[] = { [YKAppRouteModule class], /* 其余模块：app/element/touch/image/… */ };
    for (int i = 0; i < sizeof(modules) / sizeof(modules[0]); i++) {
        Class m = modules[i];
        if (![m respondsToSelector:@selector(shouldRegisterAutomatically)] ||
            ![m shouldRegisterAutomatically]) continue;
        for (NSArray<NSString *> *r in [m routes]) {
            handlers[[r[0] stringByAppendingFormat:@" %@", r[1]]] = ^{
                // [推断] 反射调用 +<handlerSel>:，实际实现为 block 直接捕获
            };
        }
    }

    [server setConnectionClass:[RouteRequest class]];
    [server setDefaultHandler:^(RouteRequest *req, RouteResponse *res) {
        YKRequestContext *ctx = [YKRequestContext contextWithRequest:req response:res];
        NSString *key = [req.method stringByAppendingFormat:@" %@", req.path];
        id h = handlers[key];
        if (h) {
            // [推断] 通过 NSInvocation 调 +[module handler:ctx]
        } else {
            YKRespondError(res, @"未处理的接口");
        }
        (void)ctx;
    }];
    [server start:NULL];

    // 端口落盘：/var/mobile/Library/YKApp/Config/http_port（二进制里的固定路径）
    [[NSString stringWithFormat:@"%d", port]
        writeToFile:@"/var/mobile/Library/YKApp/Config/http_port"
         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

@end
