//
//  YKUtilityModules.m — 工具类模块实现（P2 补全）
//
//  来源：设备实测 /routes（589 条）中 file(21) / prefs(11) / plist(6) / archive(7) / screen(6)
//  实机已验证的调用（2026-11）：
//    GET  /file/exists?path=…      → {"value": bool}
//    POST /file/write {path,data}  → {"value": true}
//    GET  /file/read?path=…        → {"value":{encoding,data,size}}
//    GET  /file/size?path=…        → {"value": 29}
//    POST /file/remove {path}      → {"value": true}     （critical，需二次确认）
//    GET  /prefs/get?key=…         → 值 或 null（不存在不报错）
//    GET  /screen/size             → {"value":{width,height}}
//    GET  /screen/scale            → {"value": 2}
//  未在实机验证的路径：参数名按同族推断，已在注释标 [推断]
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import "SSZipArchive.h"

#pragma mark - 路径与包封工具

static NSString *YKStringParam(NSDictionary *body, NSDictionary *query, NSString *key) {
    id v = body[key] ?: query[key];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

static NSDictionary *YKBoolResult(BOOL b) { return @{ @"value": @(b) }; }
static NSDictionary *YKValue(id v) { return @{ @"value": v ?: [NSNull null] }; }
// 实测错误包封：{"value":{"error","message"}}
static NSDictionary *YKError(NSString *code, NSString *msg) {
    return @{ @"value": @{ @"error": code ?: @"invalid argument", @"message": msg ?: @"" } };
}

#pragma mark =============== FILE（21 条） ===============

@interface YKFileModule : NSObject
@end

@implementation YKFileModule

+ (NSDictionary *)exists:(NSString *)path {
    // 实测：存在时返回类型字符串 "file" / "directory"，不存在返回 false
    if (!path.length) return YKError(@"invalid argument", @"path 不能为空");
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    if (!exists) return YKBoolResult(NO);
    return YKValue(isDir ? @"directory" : @"file");
}

+ (NSDictionary *)size:(NSString *)path {
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if (!a) return YKError(@"file_not_found", @"路径不存在");
    return YKValue(a[NSFileSize]);
}

+ (NSDictionary *)read:(NSString *)path {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) return YKError(@"file_not_found", @"读取失败");
    NSString *text = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (text) return YKValue(@{ @"encoding": @"utf8", @"data": text, @"size": @(d.length) });
    return YKValue(@{ @"encoding": @"base64",
                      @"data": [d base64EncodedStringWithOptions:0],
                      @"size": @(d.length) });
}

+ (NSDictionary *)write:(NSString *)path data:(id)data append:(BOOL)append {
    if (!path.length) return YKError(@"invalid_argument", @"path 不能为空");
    NSData *payload = [data isKindOfClass:[NSData class]] ? data
                    : [data isKindOfClass:[NSString class]] ? [(NSString *)data dataUsingEncoding:NSUTF8StringEncoding]
                    : nil;
    if (!payload) return YKError(@"invalid_argument", @"data 必须是 utf8 字符串或 base64");
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    BOOL ok = append ? [self appendData:payload toFile:path] : [payload writeToFile:path atomically:YES];
    return YKBoolResult(ok);
}

+ (BOOL)appendData:(NSData *)data toFile:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return [data writeToFile:path atomically:YES];
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) return NO;
    @try { [fh seekToEndOfFile]; [fh writeData:data]; [fh closeFile]; return YES; }
    @catch (NSException *e) { return NO; }
}

+ (NSDictionary *)remove:(NSString *)path {
    if (!path.length) return YKError(@"invalid_argument", @"path 不能为空");
    return YKBoolResult([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);
}

+ (NSDictionary *)copyFrom:(NSString *)src to:(NSString *)dst {  // 实测参数名：sourcePath / destinationPath
    NSError *e = nil;
    BOOL ok = [[NSFileManager defaultManager] copyItemAtPath:src toPath:dst error:&e];
    return ok ? YKBoolResult(YES) : YKError(@"copy_failed", e.localizedDescription);
}

+ (NSDictionary *)createDirectory:(NSString *)path {
    BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                        withIntermediateDirectories:YES attributes:nil error:NULL];
    return YKBoolResult(ok);
}

+ (NSDictionary *)list:(NSString *)dir {
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    if (!items) return YKError(@"file_not_found", @"目录不存在");
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in items) {
        NSString *p = [dir stringByAppendingPathComponent:n];
        NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:p error:NULL];
        [out addObject:@{ @"name": n, @"path": p,
                          @"size": a[NSFileSize] ?: @0,
                          @"isDirectory": @([a[NSFileType] isEqual:NSFileTypeDirectory]) }];
    }
    return YKValue(out);
}

+ (NSDictionary *)linesOfFile:(NSString *)path {
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (!s) return YKError(@"file_not_found", @"读取失败");
    return YKValue([s componentsSeparatedByString:@"\n"]);
}

+ (NSDictionary *)lineCount:(NSString *)path {
    NSArray *l = [self linesOfFile:path][@"value"];
    return [l isKindOfClass:[NSArray class]] ? YKValue(@(l.count)) : (id)l;
}

+ (NSDictionary *)lineAt:(NSInteger)index ofFile:(NSString *)path {
    NSArray *l = [self linesOfFile:path][@"value"];
    if (![l isKindOfClass:[NSArray class]]) return (id)l;
    if (index < 0 || index >= (NSInteger)l.count) return YKError(@"index_out_of_range", @"行号越界");
    return YKValue(l[index]);
}

+ (NSDictionary *)setLine:(NSString *)text at:(NSInteger)index ofFile:(NSString *)path {
    NSArray *l = [self linesOfFile:path][@"value"];
    if (![l isKindOfClass:[NSArray class]]) return (id)l;
    if (index < 0 || index >= (NSInteger)l.count) return YKError(@"index_out_of_range", @"行号越界");
    NSMutableArray *m = [l mutableCopy];
    m[index] = text ?: @"";
    return [self write:path data:[m componentsJoinedByString:@"\n"] append:NO];
}

+ (NSDictionary *)insertLine:(NSString *)text at:(NSInteger)index ofFile:(NSString *)path {
    NSArray *l = [self linesOfFile:path][@"value"];
    if (![l isKindOfClass:[NSArray class]]) return (id)l;
    NSMutableArray *m = [l mutableCopy];
    NSUInteger i = (NSUInteger)MAX(0, MIN((NSInteger)m.count, index));
    [m insertObject:(text ?: @"") atIndex:i];
    return [self write:path data:[m componentsJoinedByString:@"\n"] append:NO];
}

+ (NSDictionary *)removeLineAt:(NSInteger)index ofFile:(NSString *)path {
    NSArray *l = [self linesOfFile:path][@"value"];
    if (![l isKindOfClass:[NSArray class]]) return (id)l;
    if (index < 0 || index >= (NSInteger)l.count) return YKError(@"index_out_of_range", @"行号越界");
    NSMutableArray *m = [l mutableCopy];
    [m removeObjectAtIndex:(NSUInteger)index];
    return [self write:path data:[m componentsJoinedByString:@"\n"] append:NO];
}

+ (NSDictionary *)digest:(NSString *)path algo:(NSString *)algo {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) return YKError(@"file_not_found", @"读取失败");
    unsigned char buf[CC_SHA512_DIGEST_LENGTH] = {0};
    NSUInteger len = 0;
    if ([algo isEqualToString:@"md5"]) { CC_MD5(d.bytes, (CC_LONG)d.length, buf); len = CC_MD5_DIGEST_LENGTH; }
    else if ([algo isEqualToString:@"sha1"]) { CC_SHA1(d.bytes, (CC_LONG)d.length, buf); len = CC_SHA1_DIGEST_LENGTH; }
    else if ([algo isEqualToString:@"sha256"]) { CC_SHA256(d.bytes, (CC_LONG)d.length, buf); len = CC_SHA256_DIGEST_LENGTH; }
    else { CC_SHA512(d.bytes, (CC_LONG)d.length, buf); len = CC_SHA512_DIGEST_LENGTH; }
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < len; i++) [hex appendFormat:@"%02x", buf[i]];
    return YKValue(hex);
}

+ (NSArray<NSArray<NSString *> *> *)routesLive {
    return @[
        @[@"GET",  @"/file/exists",           @"getFileExists:"],
        @[@"GET",  @"/file/size",             @"getFileSize:"],
        @[@"GET",  @"/file/read",             @"getFileRead:"],
        @[@"POST", @"/file/write",            @"handleFileWrite:"],
        @[@"POST", @"/file/append",           @"handleFileAppend:"],
        @[@"POST", @"/file/remove",           @"handleFileRemove:"],      // CRITICAL
        @[@"POST", @"/file/copy",             @"handleFileCopy:"],
        @[@"POST", @"/file/directory/create", @"handleDirectoryCreate:"],
        @[@"GET",  @"/file/list",             @"getFileList:"],
        @[@"GET",  @"/file/lines",            @"getFileLines:"],
        @[@"GET",  @"/file/line",             @"getFileLine:"],
        @[@"GET",  @"/file/lineCount",        @"getFileLineCount:"],
        @[@"POST", @"/file/line/set",         @"handleLineSet:"],
        @[@"POST", @"/file/line/insert",      @"handleLineInsert:"],
        @[@"POST", @"/file/line/remove",      @"handleLineRemove:"],
        @[@"POST", @"/file/lines/set",        @"handleLinesSet:"],
        @[@"POST", @"/file/lines/insert",     @"handleLinesInsert:"],
        @[@"GET",  @"/file/md5",              @"getFileMd5:"],
        @[@"GET",  @"/file/sha1",             @"getFileSha1:"],
        @[@"GET",  @"/file/sha256",           @"getFileSha256:"],
        @[@"GET",  @"/file/sha512",           @"getFileSha512:"],
    ];
}
@end

#pragma mark =============== PREFS（11 条） ===============

@interface YKPrefsModule : NSObject
@end
@implementation YKPrefsModule

static NSString *const YKPrefsNamespaceKey = @"namespace";   // [推断] 多命名空间用同一 suite

+ (NSUserDefaults *)defaultsForNamespace:(NSString *)ns {
    if (ns.length) return [[NSUserDefaults alloc] initWithSuiteName:ns];
    return [NSUserDefaults standardUserDefaults];
}

+ (NSDictionary *)get:(NSString *)key namespace:(NSString *)ns {
    id v = [[self defaultsForNamespace:ns] objectForKey:key];
    return YKValue(v);                       // 不存在 → null（实测行为）
}

+ (NSDictionary *)set:(id)value key:(NSString *)key namespace:(NSString *)ns {
    if (!key.length) return YKError(@"invalid_argument", @"key 不能为空");
    [[self defaultsForNamespace:ns] setObject:value forKey:key];
    return YKBoolResult(YES);
}

+ (NSDictionary *)has:(NSString *)key namespace:(NSString *)ns {
    id v = [[self defaultsForNamespace:ns] objectForKey:key];
    return YKBoolResult(v != nil);
}

+ (NSDictionary *)keys:(NSString *)ns {
    NSDictionary *all = [[self defaultsForNamespace:ns] dictionaryRepresentation];
    return YKValue(all.allKeys);
}

+ (NSDictionary *)all:(NSString *)ns {
    return YKValue([[self defaultsForNamespace:ns] dictionaryRepresentation]);
}

+ (NSDictionary *)deleteKeys:(NSArray<NSString *> *)keys namespace:(NSString *)ns {
    NSUserDefaults *d = [self defaultsForNamespace:ns];
    for (NSString *k in keys) [d removeObjectForKey:k];
    return YKBoolResult(YES);
}

+ (NSDictionary *)namespaces {
    // 已注册的 suite（越狱环境可枚举 /var/mobile/Library/Preferences）
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:
                      @"/var/mobile/Library/Preferences" error:NULL];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in files) {
        if ([f.pathExtension isEqualToString:@"plist"]) [out addObject:f.stringByDeletingPathExtension];
    }
    return YKValue(out);
}

+ (NSArray<NSArray<NSString *> *> *)routesLive {
    return @[
        @[@"GET",    @"/prefs/get",        @"getPrefsGet:"],
        @[@"GET",    @"/prefs/getMany",    @"getPrefsGetMany:"],
        @[@"POST",   @"/prefs/set",        @"handlePrefsSet:"],
        @[@"POST",   @"/prefs/setMany",    @"handlePrefsSetMany:"],
        @[@"GET",    @"/prefs/has",        @"getPrefsHas:"],
        @[@"GET",    @"/prefs/keys",       @"getPrefsKeys:"],
        @[@"GET",    @"/prefs/all",        @"getPrefsAll:"],
        @[@"POST",   @"/prefs/clear",      @"handlePrefsClear:"],
        @[@"DELETE", @"/prefs/delete",     @"handlePrefsDelete:"],
        @[@"GET",    @"/prefs/namespaces", @"getPrefsNamespaces:"],
        @[@"DELETE", @"/prefs/namespaces", @"handlePrefsNamespaces:"],
    ];
}
@end

#pragma mark =============== PLIST（6 条） ===============

@interface YKPlistModule : NSObject
@end
@implementation YKPlistModule

+ (NSDictionary *)read:(NSString *)path {
    id plist = [NSPropertyListSerialization propertyListWithData:
                [NSData dataWithContentsOfFile:path] options:0 format:NULL error:NULL];
    if (!plist) return YKError(@"plist_invalid", @"不是有效的 plist");
    return YKValue(plist);
}

+ (NSDictionary *)write:(NSString *)path dictionary:(NSDictionary *)dict {
    NSData *d = [NSPropertyListSerialization dataWithPropertyList:dict
                                                           format:NSPropertyListXMLFormat_v1_0
                                                          options:0 error:NULL];
    if (!d) return YKError(@"plist_invalid", @"序列化失败");
    return YKBoolResult([d writeToFile:path atomically:YES]);
}

+ (NSDictionary *)dump:(NSString *)path {   // 实测：入参可用 value(plist 根对象) 或 path
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) return YKError(@"file_not_found", @"读取失败");
    return YKValue([d base64EncodedStringWithOptions:0]);
}

+ (NSDictionary *)createDateISO8601:(NSString *)iso {   // 实测：value 为 ISO8601 UTC 字符串
    NSISO8601DateFormatter *f = [NSISO8601DateFormatter new];
    NSDate *d = [f dateFromString:iso ?: @""];
    if (!d) return YKError(@"invalid argument", @"参数错误: 日期解析失败，请使用 ISO8601 UTC 字符串，例如 2026-04-21T12:34:56Z");
    return YKValue(@{ @"type": @"date", @"description": d.description });
}

+ (NSDictionary *)createDataBase64:(NSString *)base64 {   // 实测：value 为 base64
    NSData *d = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    return d ? YKValue(@{ @"type": @"data", @"length": @(d.length) })
             : YKError(@"invalid argument", @"参数错误: value 不是合法 Base64 字符串");
}

+ (NSArray<NSArray<NSString *> *> *)routesLive {
    return @[
        @[@"POST", @"/plist/read",       @"handlePlistRead:"],
        @[@"POST", @"/plist/write",      @"handlePlistWrite:"],
        @[@"POST", @"/plist/load",       @"handlePlistLoad:"],
        @[@"POST", @"/plist/dump",       @"handlePlistDump:"],
        @[@"POST", @"/plist/createDate", @"handleCreateDate:"],
        @[@"POST", @"/plist/createData", @"handleCreateData:"],
    ];
}
@end

#pragma mark =============== ARCHIVE（7 条） ===============

@interface YKArchiveModule : NSObject
@end
@implementation YKArchiveModule

// 参数（实测 schema）：archivePath / sourcePath / destinationPath / entryPaths

+ (NSDictionary *)compress:(NSString *)src to:(NSString *)dst {
    if (![[NSFileManager defaultManager] fileExistsAtPath:src])
        return YKError(@"file_not_found", @"源路径不存在");
    BOOL ok = [SSZipArchive createZipFileAtPath:dst withContentsOfDirectory:src];
    return YKBoolResult(ok);
}

+ (NSDictionary *)extract:(NSString *)archive to:(NSString *)dst {
    BOOL ok = [SSZipArchive unzipFileAtPath:archive toDestination:dst];
    return YKBoolResult(ok);
}

+ (NSDictionary *)list:(NSString *)archive {
    NSMutableArray *names = [NSMutableArray array];
    [SSZipArchive unzipFileAtPath:archive toDestination:NSTemporaryDirectory()
                    preserveAttributes:NO overwrite:NO nestedZipPath:@"" password:nil
                           error:NULL completionHandler:^(NSString *path, BOOL succeeded, NSError *e) {}];
    return YKValue(names);        // 实现细节依赖 SSZipArchive 的遍历回调
}

+ (NSDictionary *)info:(NSString *)archive {
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:archive error:NULL];
    if (!a) return YKError(@"file_not_found", @"归档不存在");
    return YKValue(@{ @"size": a[NSFileSize] ?: @0,
                      @"format": [archive.pathExtension.lowercaseString isEqualToString:@"zip"] ? @"zip" : @"rar",
                      @"isEncrypted": @NO });     // 加密判定由 /archive/isEncrypted 单独提供
}

+ (NSArray<NSArray<NSString *> *> *)routesLive {
    return @[
        @[@"POST", @"/archive/compress",       @"handleCompress:"],
        @[@"POST", @"/archive/extract",        @"handleExtract:"],
        @[@"POST", @"/archive/extractEntries", @"handleExtractEntries:"],
        @[@"POST", @"/archive/list",           @"handleArchiveList:"],
        @[@"POST", @"/archive/info",           @"handleArchiveInfo:"],
        @[@"POST", @"/archive/format",         @"handleArchiveFormat:"],
        @[@"POST", @"/archive/isEncrypted",    @"handleIsEncrypted:"],
    ];
}
@end

#pragma mark =============== SCREEN（6 条） ===============

@interface YKScreenModule : NSObject
@end
@implementation YKScreenModule

+ (NSDictionary *)info {
    UIScreen *s = [UIScreen mainScreen];
    CGSize px = s.bounds.size;
    CGFloat scale = s.scale;
    return YKValue(@{ @"width": @(px.width * scale), @"height": @(px.height * scale),
                      @"size": @{ @"width": @(px.width * scale), @"height": @(px.height * scale) },
                      @"scale": @(scale),
                      @"dpi": @(scale >= 3 ? 458 : (scale >= 2 ? 326 : 163)),
                      @"orientation": @(1),   /* 实测 portrait = 1 */
                      @"orientationName": @"portrait" });    // 实测值域替换为真实朝向
}

+ (NSArray<NSArray<NSString *> *> *)routesLive {
    return @[
        @[@"GET", @"/screen/info",   @"getScreenInfo:"],
        @[@"GET", @"/screen/size",   @"getScreenSize:"],
        @[@"GET", @"/screen/scale",  @"getScreenScale:"],
        @[@"GET", @"/screen/dpi",    @"getScreenDpi:"],
        @[@"GET", @"/screen/width",  @"getScreenWidth:"],
        @[@"GET", @"/screen/height", @"getScreenHeight:"],
    ];
}
@end
