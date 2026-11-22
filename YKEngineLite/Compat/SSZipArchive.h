//
//  SSZipArchive / 转发头 — Lite 工程兼容层
//
#import <Foundation/Foundation.h>

// ---- 转发：让重建代码里的原始 import 生效 ----
// HTTPServer.h / RouteRequest.h / RouteResponse.h 都指向 YKHTTPServerCompat.h
// （见同目录下的三个一行转发头）

@interface SSZipArchive : NSObject
+ (BOOL)createZipFileAtPath:(NSString *)path withContentsOfDirectory:(NSString *)dir;
+ (BOOL)unzipFileAtPath:(NSString *)path toDestination:(NSString *)destination;
+ (BOOL)unzipFileAtPath:(NSString *)path
          toDestination:(NSString *)destination
       preserveAttributes:(BOOL)preserve
                overwrite:(BOOL)overwrite
            nestedZipPath:(NSString *)nested
                 password:(NSString *)password
                    error:(NSError **)error
        completionHandler:(void (^)(NSString *entry, BOOL succeeded, NSError *error))handler;
@end
