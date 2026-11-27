//  YKHTTPServerCompat.m — 最小 HTTP 服务器（POSIX socket 实现）
//
//  替代 RoutingHTTPServer 的 HTTPServer / RouteRequest / RouteResponse。
//  行为对齐设备实测（PROTOCOL_FINAL.md）：
//    · 成功包封 {"value": …}；失败 {"value":{"error","message"}}
//    · 受保护路由可选校验 X-YK-Session-Id
//    · OPTIONS 统一 CORS
//    · 审计日志 [HTTP_AUDIT] method=… path=… status=… durationMs=…

#import "YKHTTPServerCompat.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>
#import <fcntl.h>
#import <string.h>

static NSError *YKSocketError(NSString *operation, int code, NSString *interface, uint16_t port) {
    NSString *message = [NSString stringWithFormat:@"%@ %@:%u errno=%d (%s)",
                         operation, interface, port, code, strerror(code)];
    NSLog(@"[YKEngineLite] %@", message);
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:code
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

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
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *routeIndex;
@property (nonatomic, copy)   YKRouteHandler defaultHandler;
- (void)processRaw:(NSData *)raw into:(NSMutableData *)out;
- (void)writeResponse:(RouteResponse *)res into:(NSMutableData *)out;
- (void)serveClient:(int)cfd;
@end

@implementation HTTPServer {
    int  _listenFD;
    BOOL _running;
    dispatch_source_t _acceptSource;
}

- (instancetype)init {
    if ((self = [super init])) {
        _port = 65323;
        _interface = @"loopback";
        _routes = [NSMutableDictionary dictionary];
        _routeIndex = [NSMutableDictionary dictionary];
        _sessions = [NSMutableDictionary dictionary];
        _requiresSessionHeader = NO;
        _listenFD = -1;
    }
    return self;
}

- (void)register:(NSString *)method path:(NSString *)path block:(YKRouteHandler)block {
    NSString *key = [NSString stringWithFormat:@"%@ %@", method, path];
    self.routes[key] = [block copy];
    self.routeIndex[path.lowercaseString] = key;
}
- (void)get:(NSString *)path withBlock:(YKRouteHandler)block    { [self register:@"GET" path:path block:block]; }
- (void)post:(NSString *)path withBlock:(YKRouteHandler)block   { [self register:@"POST" path:path block:block]; }
- (void)delete:(NSString *)path withBlock:(YKRouteHandler)block { [self register:@"DELETE" path:path block:block]; }
- (void)setDefaultHandler:(YKRouteHandler)handler               { _defaultHandler = [handler copy]; }

- (BOOL)start:(NSError **)error {
    @synchronized (self) {
    if (error) *error = nil;
    if (_running) return YES;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        int e = errno;
        if (error) *error = YKSocketError(@"socket", e, self.interface, self.port);
        return NO;
    }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in addr = {0};
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(self.port);
    addr.sin_addr.s_addr = [self.interface isEqualToString:@"loopback"]
        ? htonl(INADDR_LOOPBACK) : htonl(INADDR_ANY);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        int e = errno;
        close(fd);
        if (error) *error = YKSocketError(@"bind", e, self.interface, self.port);
        return NO;
    }
    if (listen(fd, 16) != 0) {
        int e = errno;
        close(fd);
        if (error) *error = YKSocketError(@"listen", e, self.interface, self.port);
        return NO;
    }
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
        int e = errno;
        close(fd);
        if (error) *error = YKSocketError(@"fcntl", e, self.interface, self.port);
        return NO;
    }
    _listenFD = fd;
    _running = YES;

    __weak typeof(self) weakSelf = self;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0,
        dispatch_queue_create("com.yk.http.accept", DISPATCH_QUEUE_SERIAL));
    _acceptSource = source;
    dispatch_source_set_event_handler(source, ^{
        HTTPServer *strong = weakSelf;
        if (!strong) return;
        @synchronized (strong) {
        if (!strong->_running || strong->_listenFD != fd) return;
        while (YES) {
            struct sockaddr_in cli = {0};
            socklen_t len = sizeof(cli);
            int cfd = accept(fd, (struct sockaddr *)&cli, &len);
            if (cfd < 0) {
                if (errno == EINTR) continue;
                if (errno != EAGAIN && errno != EWOULDBLOCK)
                    YKSocketError(@"accept", errno, strong.interface, strong.port);
                break;
            }
            int clientFlags = fcntl(cfd, F_GETFL, 0);
            if (clientFlags < 0 || fcntl(cfd, F_SETFL, clientFlags & ~O_NONBLOCK) < 0) {
                close(cfd);
                continue;
            }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                HTTPServer *s2 = weakSelf;
                if (s2) [s2 serveClient:cfd]; else close(cfd);
            });
        }
        }
    });
    // The cancel handler owns this descriptor, even across stop/start cycles.
    dispatch_source_set_cancel_handler(source, ^{ close(fd); });
    dispatch_resume(source);

    NSLog(@"[YKEngineLite] listening on %@:%u (fd=%d)", self.interface, self.port, fd);
    return YES;
    }
}

- (BOOL)isRunning {
    @synchronized (self) { return _running; }
}

- (void)stop {
    @synchronized (self) {
    _running = NO;
    if (_listenFD >= 0) shutdown(_listenFD, SHUT_RDWR);
    if (_acceptSource) dispatch_source_cancel(_acceptSource);
    _acceptSource = nil;
    _listenFD = -1;
    }
}

- (void)dealloc { [self stop]; }

- (void)serveClient:(int)cfd {
    struct timeval tv = { 10, 0 };
    setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(cfd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    int one = 1;
    setsockopt(cfd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));

    NSMutableData *buf = [NSMutableData data];
    char chunk[8192];
    NSInteger contentLength = -1;
    NSUInteger headerEnd = NSNotFound;

    while (YES) {
        ssize_t n = read(cfd, chunk, sizeof(chunk));
        if (n <= 0) break;
        [buf appendBytes:chunk length:(NSUInteger)n];

        if (headerEnd == NSNotFound) {
            NSRange r = [buf rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]
                                 options:0 range:NSMakeRange(0, buf.length)];
            if (r.location != NSNotFound) {
                headerEnd = r.location + r.length;
                NSString *head = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(0, headerEnd)]
                                                       encoding:NSUTF8StringEncoding];
                for (NSString *line in [head componentsSeparatedByString:@"\r\n"]) {
                    if ([line.lowercaseString hasPrefix:@"content-length:"]) {
                        contentLength = [[line substringFromIndex:15]
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].integerValue;
                    }
                }
                if (contentLength < 0) contentLength = 0;
            }
        }
        if (headerEnd != NSNotFound && buf.length >= headerEnd + (NSUInteger)contentLength) break;
        if (buf.length > (16 << 20)) break;
    }

    NSMutableData *out = [NSMutableData data];
    if (buf.length) [self processRaw:buf into:out];

    NSUInteger sent = 0;
    while (sent < out.length) {
        ssize_t n = write(cfd, (const char *)out.bytes + sent, out.length - sent);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        sent += (NSUInteger)n;
    }
    close(cfd);
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
        NSUInteger start = hdrEnd.location + hdrEnd.length;
        if (start < raw.length) body = [raw subdataWithRange:NSMakeRange(start, raw.length - start)];
    }

    req.method = method;
    req.path = path;
    req.headers = headers;
    req.query = query;
    req.body = body;

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

    if (self.requiresSessionHeader) {
        NSString *sid = [req header:@"X-YK-Session-Id"];
        if (!sid.length && ![path isEqualToString:@"/health"] && ![path isEqualToString:@"/routes"]) {
            [res respondWithError:@"unauthorized"
                          message:@"缺少 X-YK-Session-Id，请先调用 POST /session/create 创建任务"
                           status:401];
            [self writeResponse:res into:out];
            return;
        }
    }

    YKRouteHandler handler = self.routes[[NSString stringWithFormat:@"%@ %@", method, path]];
    if (!handler) handler = self.routes[[NSString stringWithFormat:@"%@ %@", method, path.lowercaseString]];
    if (!handler) handler = self.defaultHandler;

    if (handler) {
        @try { handler(req, res); }
        @catch (NSException *e) {
            [res respondWithError:@"exception" message:e.reason ?: @"handler 异常" status:500];
        }
    } else {
        [res respondWithError:@"not_found"
                      message:[NSString stringWithFormat:@"未处理的路由 %@ %@", method, path]
                       status:404];
    }
    [self writeResponse:res into:out];

    NSLog(@"[HTTP_AUDIT] method=%@ path=%@ status=%ld durationMs=%.2f session=%@",
          method, path, (long)res.statusCode,
          [[NSDate date] timeIntervalSinceDate:t0] * 1000.0,
          [req header:@"X-YK-Session-Id"] ?: @"-");
}

- (void)writeResponse:(RouteResponse *)res into:(NSMutableData *)out {
    [res setHeader:@"Access-Control-Allow-Origin" value:@"*"];
    NSMutableString *h = [NSMutableString stringWithFormat:
        @"HTTP/1.1 %ld %@\r\nContent-Length: %lu\r\nConnection: close\r\n",
        (long)res.statusCode, res.statusCode < 400 ? @"OK" : @"ERR",
        (unsigned long)res.body.length];
    for (NSString *k in res.headers) [h appendFormat:@"%@: %@\r\n", k, res.headers[k]];
    [h appendString:@"\r\n"];
    [out appendData:[h dataUsingEncoding:NSUTF8StringEncoding]];
    [out appendData:res.body];
}

@end
