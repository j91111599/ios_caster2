//
//  YKHTTPServerCompat.h — 最小可用 HTTP 服务器 + Route 抽象（替代 RoutingHTTPServer）
//
//  为什么需要：重建出来的 YKHTTPRouter.m 依赖 RoutingHTTPServer 的
//  HTTPServer / RouteRequest / RouteResponse 三个类。本文件给出等价实现，
//  使重建代码无需改动即可编译；行为对齐设备实测（见 PROTOCOL_FINAL.md）：
//    · 成功包封 {"value": …}   失败 {"value.error","value.message"}
//    · 受保护路由需 X-YK-Session-Id
//    · OPTIONS /* 统一 CORS
//    · 审计日志 HTTP_AUDIT ...
//
#import <Foundation/Foundation.h>

#pragma mark - 请求 / 响应

@interface RouteRequest : NSObject
@property (nonatomic, copy)   NSString *method;
@property (nonatomic, copy)   NSString *path;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *query;
@property (nonatomic, strong) NSData *body;
- (NSString *)header:(NSString *)name;
- (id)jsonBody;
@end

@interface RouteResponse : NSObject
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *headers;
@property (nonatomic, strong) NSMutableData *body;
- (void)setHeader:(NSString *)name value:(NSString *)value;
- (void)respondWithData:(NSData *)data;
- (void)respondWithString:(NSString *)text;
- (void)respondWithJSON:(id)json;
- (void)respondWithError:(NSString *)code message:(NSString *)message status:(NSInteger)status;
@end

#pragma mark - 服务器

typedef void (^YKRouteHandler)(RouteRequest *req, RouteResponse *res);

@interface HTTPServer : NSObject
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, copy)   NSString *type;        // 兼容字段（不使用 Bonjour）
@property (nonatomic, copy)   NSString *interface;   // "loopback" / "all"
@property (nonatomic, copy)   NSString *documentRoot;
@property (nonatomic, assign) BOOL requiresSessionHeader;   // 非公开路由是否校验 X-YK-Session-Id
@property (nonatomic, strong) NSMutableDictionary<NSString *, YKRouteHandler> *routes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *sessions;

- (void)get:(NSString *)path withBlock:(YKRouteHandler)block;
- (void)post:(NSString *)path withBlock:(YKRouteHandler)block;
- (void)delete:(NSString *)path withBlock:(YKRouteHandler)block;
- (void)setDefaultHandler:(YKRouteHandler)handler;

- (BOOL)start:(NSError **)error;
- (void)stop;
@end
