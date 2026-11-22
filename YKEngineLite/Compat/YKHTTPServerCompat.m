#import "YKHTTPServerCompat.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>

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

@implementation HTTPServer {
    int _listenFD;
    BOOL _running;
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
    self.routeIndex[[path lowercaseString]] = key;
}

- (void)get:(NSString *)path withBlock:(YKRouteHandler)block    { [self register:@"GET" path:path block:block]; }
- (void)post:(NSString *)path withBlock:(YKRouteHandler)block   { [self register:@"POST" path:path block:block]; }
- (void)delete:(NSString *)path withBlock:(YKRouteHandler)block { [self register:@"DELETE" path:path block:block]; }
- (void)setDefaultHandler:(YKRouteHandler)handler               { _defaultHandler = [handler copy]; }

- (BOOL)start:(NSError **)error {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:@"HTTPServer" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"socket() 失败"}];
        return NO;
    }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(self.port);
    addr.sin_addr.s_addr = [self.interface isEqualToString:@"loopback"]
        ? htonl(INADDR_LOOPBACK) : htonl(INADDR_ANY);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        int e = errno;
        close(fd);
        if (error) *error = [NSError errorWithDomain:@"HTTPServer" code:e
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"bind 失败 errno=%d", e]}];
        return NO;
    }
    if (listen(fd, 16) != 0) {
        int e = errno;
        close(fd);
        if (error) *error = [NSError errorWithDomain:@"HTTPServer" code:e
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"listen 失败 errno=%d", e]}];
        return NO;
    }
    _listenFD = fd;
    _running = YES;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        while (weakSelf && weakSelf->_running) {
            struct sockaddr_in cli = {0};
            socklen_t len = sizeof(cli);
            int cfd = accept(weakSelf->_listenFD, (struct sockaddr *)&cli, &len);
            if (cfd < 0) {
                if (!weakSelf->_running) break;
                usleep(50000);
                continue;
            }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                [weakSelf serveClient:cfd];
            });
        }
    });

    NSLog(@"[YKEngineLite] listening on %@:%u (fd=%d)", self.interface, self.port, fd);
    return YES;
}

- (void)stop {
    _running = NO;
    if (_listenFD >= 0) { close(_listenFD); _listenFD = -1; }
}

- (void)serveClient:(int)cfd {
    struct timeval tv = { 10, 0 };
    setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    NSMutableData *buf = [NSMutableData data];
    char chunk[8192];
    NSInteger contentLength = -1;
    NSUInteger headerEnd = NSNotFound;

    while (true) {
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

    ssize_t ignored = write(cfd, out.bytes, out.length);
    (void)ignored;
    close(cfd);
}

@end
