#import "YKHTTPServerCompat.h"
#import <Network/Network.h>

#pragma mark - RouteRequest

@implementation RouteRequest
- (NSString *)header:(NSString *)name {
    for (NSString *k in self.headers) {
        if ([k caseInsensitiveCompare:name] == NSOrderedSame) return self.headers[k];
    }
    return nil;
}
- (id)jsonBody {
    if (!self.body.length) return nil;
    return [NSJSONSerialization JSONObjectWithData:self.body options:0 error:NULL];
}
@end

#pragma mark - RouteResponse

@implementation RouteResponse
- (instancetype)init {
    if ((self = [super init])) {
        _statusCode = 200;
        _headers = [NSMutableDictionary dictionary];
        _body = [NSMutableData data];
    }
    return self;
}
- (void)setHeader:(NSString *)name value:(NSString *)value {
    if (name.length && value) self.headers[name] = value;
}
- (void)respondWithData:(NSData *)data {
    self.body = [data mutableCopy] ?: [NSMutableData data];
}
- (void)respondWithString:(NSString *)text {
    [self setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    [self respondWithData:[(text ?: @"") dataUsingEncoding:NSUTF8StringEncoding]];
}
- (void)respondWithJSON:(id)json {
    NSData *d = [NSJSONSerialization dataWithJSONObject:json ?: @{} options:0 error:NULL];
    [self setHeader:@"Content-Type" value:@"application/json; charset=utf-8"];
    [self respondWithData:d ?: [NSMutableData data]];
}
- (void)respondWithError:(NSString *)code message:(NSString *)message status:(NSInteger)status {
    self.statusCode = status;
    // 实测包封：{"value":{"error","message"}}
    [self respondWithJSON:@{ @"value": @{ @"error": code ?: @"invalid argument",
                                          @"message": message ?: @"" } }];
}
@end

#pragma mark - HTTPServer

@interface HTTPServer ()
@property (nonatomic, strong) nw_listener_t listener;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *routeIndex;  // "GET /path" -> key
@property (nonatomic, copy)   YKRouteHandler defaultHandler;
@end

@implementation HTTPServer

- (instancetype)init {
    if ((self = [super init])) {
        _port = 65323;
        _interface = @"loopback";
        _routes = [NSMutableDictionary dictionary];
        _routeIndex = [NSMutableDictionary dictionary];
        _sessions = [NSMutableDictionary dictionary];
        _requiresSessionHeader = NO;   // Lite 版默认不强制（与设备默认行为区分）
    }
    return self;
}

- (void)register:(NSString *)method path:(NSString *)path block:(YKRouteHandler)block {
    NSString *key = [NSString stringWithFormat:@"%@ %@", method, path];
    self.routes[key] = [block copy];
    self.routeIndex[[path lowercaseString]] = key;
}

- (void)get:(NSString *)path withBlock:(YKRouteHandler)block    { [self register:@"GET" path:path block:block]; }
- (void)post:(NSString *)path withBlock:(YKRouteHandler)block   { [self register:@"POST" path:path block:block]; }
- (void)delete:(NSString *)path withBlock:(YKRouteHandler)block { [self register:@"DELETE" path:path block:block]; }
- (void)setDefaultHandler:(YKRouteHandler)handler               { _defaultHandler = [handler copy]; }

- (BOOL)start:(NSError **)error {
    nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                             NW_PARAMETERS_DEFAULT_CONFIGURATION);
    if ([self.interface isEqualToString:@"loopback"]) {
        nw_parameters_set_local_endpoint(params,
            nw_endpoint_create_host("127.0.0.1", [[NSString stringWithFormat:@"%u", self.port] UTF8String]));
    }
    nw_listener_t l = nw_listener_create_with_port([[NSString stringWithFormat:@"%u", self.port] UTF8String],
                                                    params);
    if (!l) {
        if (error) *error = [NSError errorWithDomain:@"HTTPServer" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"listener 创建失败"}];
        return NO;
    }
    __weak typeof(self) weakSelf = self;
    nw_listener_set_new_connection_handler(l, ^(nw_connection_t conn) {
        nw_connection_set_queue(conn, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
        nw_connection_set_state_changed_handler(conn, ^(nw_connection_state_t st, nw_error_t e) {
            if (st == nw_connection_state_ready) [weakSelf handleConnection:conn];
            else if (st == nw_connection_state_failed || st == nw_connection_state_cancelled)
                nw_connection_cancel(conn);
        });
        nw_connection_start(conn);
    });
    nw_listener_start(l);
    self.listener = l;
    NSLog(@"[YKEngineLite] listening on %@:%u", self.interface, self.port);
    return YES;
}

- (void)stop {
    if (self.listener) nw_listener_cancel(self.listener);
    self.listener = nil;
}

#pragma mark 请求处理

- (void)handleConnection:(nw_connection_t)conn {
    __weak typeof(self) weakSelf = self;
    nw_connection_receive(conn, 1, 1 << 20, ^(dispatch_data_t content, nw_content_context_t ctx,
                                              bool complete, nw_error_t err) {
        NSData *raw = nil;
        if (content) {
            const void *buf = NULL; size_t len = 0;
            dispatch_data_t flat = dispatch_data_create_map(content, &buf, &len);
            if (buf && len) raw = [NSData dataWithBytes:buf length:len];
            (void)flat;
        }
        NSMutableData *respData = [NSMutableData data];
        [weakSelf processRaw:raw into:respData];
        dispatch_data_t out = dispatch_data_create(respData.bytes, respData.length,
                                                   dispatch_get_main_queue(), ^{});
        nw_connection_send(conn, out, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t e) {
            nw_connection_cancel(conn);
        });
    });
}

- (void)processRaw:(NSData *)raw into:(NSMutableData *)out {
    NSDate *t0 = [NSDate date];
    RouteRequest *req = [RouteRequest new];
    RouteResponse *res = [RouteResponse new];

    NSString *head = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding] ?: @"";
    NSRange hdrEnd = [head rangeOfString:@"\r\n\r\n"];
    NSString *headerPart = hdrEnd.location == NSNotFound ? head : [head substringToIndex:hdrEnd.location];
    NSArray<NSString *> *lines = [headerPart componentsSeparatedByString:@"\r\n"];
    NSArray<NSString *> *first = lines.count ? [lines[0] componentsSeparatedByString:@" "] : @[];
    NSString *method = first.count > 0 ? first[0] : @"GET";
    NSString *rawPath = first.count > 1 ? first[1] : @"/";

    NSRange q = [rawPath rangeOfString:@"?"];
    NSString *path = q.location == NSNotFound ? rawPath : [rawPath substringToIndex:q.location];
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    if (q.location != NSNotFound) {
        for (NSString *pair in [[rawPath substringFromIndex:q.location + 1] componentsSeparatedByString:@"&"]) {
            NSArray *kv = [pair componentsSeparatedByString:@"="];
            if (kv.count == 2) query[kv[0]] = [kv[1] stringByRemovingPercentEncoding] ?: kv[1];
        }
    }
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSRange c = [lines[i] rangeOfString:@":"];
        if (c.location == NSNotFound) continue;
        headers[[lines[i] substringToIndex:c.location]] =
            [[lines[i] substringFromIndex:c.location + 1]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    NSData *body = nil;
    if (hdrEnd.location != NSNotFound) {
        NSUInteger bodyStart = hdrEnd.location + hdrEnd.length;
        if (bodyStart < raw.length) body = [raw subdataWithRange:NSMakeRange(bodyStart, raw.length - bodyStart)];
    }

    req.method = method;
    req.path = path;
    req.headers = headers;
    req.query = query;
    req.body = body;

    // CORS preflight
    if ([method isEqualToString:@"OPTIONS"]) {
        res.statusCode = 204;
        [res setHeader:@"Access-Control-Allow-Origin" value:@"*"];
        [res setHeader:@"Access-Control-Allow-Headers"
                 value:@"Content-Type, X-Requested-With, X-YK-Session-Id, X-YK-Request-Id, "
                       @"X-YK-Executor-Job-Id, X-YK-Remote-Authorization"];
        [res setHeader:@"Access-Control-Allow-Methods" value:@"GET, POST, DELETE, OPTIONS"];
        [self writeResponse:res into:out];
        return;
    }

    // 会话鉴权（Lite 版可选）
    if (self.requiresSessionHeader) {
        NSString *sid = [req header:@"X-YK-Session-Id"];
        if (!sid.length && ![path isEqualToString:@"/health"] && ![path isEqualToString:@"/routes"]) {
            [res respondWithError:@"session_required" message:@"缺少 X-YK-Session-Id" status:401];
            [self writeResponse:res into:out];
            return;
        }
    }

    YKRouteHandler handler = self.routes[[NSString stringWithFormat:@"%@ %@", method, path]];
    if (!handler) handler = self.routes[[NSString stringWithFormat:@"%@ %@", method, path.lowercaseString]];
    if (!handler && [path hasPrefix:@"/session/create"]) {
        handler = ^(RouteRequest *r, RouteResponse *s) {
            NSString *sid = [NSString stringWithFormat:@"sess_%.0f_%@",
                             [[NSDate date] timeIntervalSince1970] * 1000,
                             [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""]];
            [s respondWithJSON:@{ @"value": @{ @"sessionId": sid, @"state": @"active", @"name": @"default" } }];
        };
    }
    if (!handler) {
        if (self.defaultHandler) handler = self.defaultHandler;
    }
    if (handler) {
        @try { handler(req, res); }
        @catch (NSException *e) {
            [res respondWithError:@"exception" message:e.reason ?: @"handler 异常" status:500];
        }
    } else {
        [res respondWithError:@"not_found" message:[NSString stringWithFormat:@"未处理的路由 %@ %@", method, path]
                       status:404];
    }
    [self writeResponse:res into:out];

    // 审计日志（对齐设备格式）
    NSLog(@"[HTTP_AUDIT] method=%@ path=%@ status=%ld durationMs=%.2f session=%@",
          method, path, (long)res.statusCode,
          [[NSDate date] timeIntervalSinceDate:t0] * 1000.0,
          [req header:@"X-YK-Session-Id"] ?: @"-");
}

- (void)writeResponse:(RouteResponse *)res into:(NSMutableData *)out {
    [res setHeader:@"Access-Control-Allow-Origin" value:@"*"];
    NSString *head = [NSString stringWithFormat:
        @"HTTP/1.1 %ld %@\r\nContent-Length: %lu\r\nConnection: close\r\n%@\r\n",
        (long)res.statusCode, @"OK", (unsigned long)res.body.length,
        [[res.headers allKeys] componentsJoinedByString:@""] ?: @""];
    NSMutableString *h = [NSMutableString stringWithFormat:
        @"HTTP/1.1 %ld %@\r\nContent-Length: %lu\r\nConnection: close\r\n",
        (long)res.statusCode, res.statusCode == 200 ? @"OK" : @"ERR", (unsigned long)res.body.length];
    for (NSString *k in res.headers) [h appendFormat:@"%@: %@\r\n", k, res.headers[k]];
    [h appendString:@"\r\n"];
    (void)head;
    [out appendData:[h dataUsingEncoding:NSUTF8StringEncoding]];
    [out appendData:res.body];
}

@end
