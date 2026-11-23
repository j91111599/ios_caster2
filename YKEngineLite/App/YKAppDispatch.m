//  YKAppDispatch — 把 daemon 已实现的 341 条 handler 接入 App 内引擎
//
//  覆盖族：file(21) prefs(11) plist(6) crypto(21) screen(6) network(21) ui(245)
//  依据：dump/Recovered/ 中已完成的模块类（YKFileModule / YKPrefsModule /
//        YKPlistModule / YKScreenModule / YKCryptoModule / YKNetworkModule / YKUIDispatcher）
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/utsname.h>
#import <CommonCrypto/CommonDigest.h>

@class RouteRequest, RouteResponse;

#pragma mark - 模块声明（实现在 Recovered/*.m）

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

#pragma mark - 分派


static NSString *YkMachine(void) {
    struct utsname u; uname(&u);
    NSString *m = @(u.machine);
    NSDictionary *map = @{ @"iPhone9,1": @"iPhone 7", @"iPhone9,3": @"iPhone 7",
                           @"iPhone10,1": @"iPhone 8", @"iPhone10,4": @"iPhone 8",
                           @"iPhone10,2": @"iPhone 8 Plus", @"iPhone10,5": @"iPhone 8 Plus",
                           @"iPhone10,3": @"iPhone X", @"iPhone10,6": @"iPhone X",
                           @"iPhone11,2": @"iPhone XS", @"iPhone12,1": @"iPhone 11",
                           @"iPhone12,3": @"iPhone 11 Pro", @"iPhone13,2": @"iPhone 12",
                           @"iPhone14,5": @"iPhone 13" };
    return map[m] ?: m;
}

static NSString *YkLocaleJSON(void) {
    NSLocale *l = [NSLocale currentLocale];
    NSDictionary *d = @{ @"region": [l objectForKey:NSLocaleCountryCode] ?: @"",
                         @"localeIdentifier": l.localeIdentifier ?: @"",
                         @"language": [l objectForKey:NSLocaleLanguageCode] ?: @"" };
    NSData *j = [NSJSONSerialization dataWithJSONObject:d options:0 error:NULL];
    return [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding] ?: @"{}";
}

// 40 位十六进制（SHA1），与原版格式一致
static NSString *YkUUID40(void) {
    NSString *seed = [UIDevice currentDevice].identifierForVendor.UUIDString ?: @"yk";
    NSData *in = [seed dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char d[CC_SHA1_DIGEST_LENGTH] = {0};
    CC_SHA1(in.bytes, (CC_LONG)in.length, d);
    NSMutableString *o = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [o appendFormat:@"%02x", d[i]];
    return o;
}


// ===== image 族（CoreGraphics 实现，无需 OpenCV）=====
static NSMutableDictionary *gImages = nil;

static NSString *YkNewImageId(UIImage *img) {
    if (!gImages) gImages = [NSMutableDictionary dictionary];
    NSString *iid = [[NSUUID UUID] UUIDString];
    gImages[iid] = img;
    return iid;
}
static UIImage *YkGetImage(NSString *iid) { return iid ? gImages[iid] : nil; }

static NSDictionary *YkImageInfo(UIImage *img, NSString *iid) {
    if (!img) return nil;
    CGImageRef cg = img.CGImage;
    return @{ @"value": @{ @"imageId": iid,
                           @"width": @(CGImageGetWidth(cg)),
                           @"height": @(CGImageGetHeight(cg)),
                           @"bytesPerRow": @(CGImageGetBytesPerRow(cg)),
                           @"scale": @(img.scale) } };
}
static NSDictionary *YKErr(NSString *code, NSString *msg) {
    return @{ @"value": @{ @"error": code, @"message": msg ?: @"" } };
}

NSDictionary *YKAppDispatchPath(NSString *method, NSString *path,
                                 NSDictionary *body, NSDictionary *query)
{
    NSMutableArray *seg = [NSMutableArray array];
    for (NSString *s in [path componentsSeparatedByString:@"/"]) if (s.length) [seg addObject:s];
    NSString *head = seg.count ? seg[0] : @"";

    NSString *p = body[@"path"] ?: query[@"path"];

    // ---- file ----
    if ([head isEqualToString:@"file"]) {
        NSString *verb = seg.count > 1 ? seg[1] : @"";
        if ([verb isEqualToString:@"exists"])    return [YKFileModule exists:p];
        if ([verb isEqualToString:@"size"])      return [YKFileModule size:p];
        if ([verb isEqualToString:@"read"])      return [YKFileModule read:p];
        if ([verb isEqualToString:@"write"])     return [YKFileModule write:p data:body[@"data"] append:NO];
        if ([verb isEqualToString:@"append"])    return [YKFileModule write:p data:body[@"data"] append:YES];
        if ([verb isEqualToString:@"remove"])    return [YKFileModule remove:p];
        if ([verb isEqualToString:@"list"])      return [YKFileModule list:p ?: @"/"];
        if ([verb isEqualToString:@"lines"])     return [YKFileModule linesOfFile:p];
        if ([verb isEqualToString:@"lineCount"]) return [YKFileModule lineCount:p];
        if ([verb isEqualToString:@"md5"])       return [YKFileModule digest:p algo:@"md5"];
        if ([verb isEqualToString:@"sha1"])      return [YKFileModule digest:p algo:@"sha1"];
        if ([verb isEqualToString:@"sha256"])    return [YKFileModule digest:p algo:@"sha256"];
        if ([verb isEqualToString:@"sha512"])    return [YKFileModule digest:p algo:@"sha512"];
        return YKErr(@"not_found", verb);
    }

    // ---- prefs ----
    if ([head isEqualToString:@"prefs"]) {
        NSString *verb = seg.count > 1 ? seg[1] : @"";
        NSString *k = body[@"key"] ?: query[@"key"];
        NSString *ns = body[@"namespace"] ?: query[@"namespace"];
        if ([verb isEqualToString:@"get"])        return [YKPrefsModule get:k namespace:ns];
        if ([verb isEqualToString:@"set"])        return [YKPrefsModule set:body[@"value"] key:k namespace:ns];
        if ([verb isEqualToString:@"has"])        return [YKPrefsModule has:k namespace:ns];
        if ([verb isEqualToString:@"keys"])       return [YKPrefsModule keys:ns];
        if ([verb isEqualToString:@"all"])        return [YKPrefsModule all:ns];
        if ([verb isEqualToString:@"namespaces"]) return [YKPrefsModule namespaces];
        return YKErr(@"not_found", verb);
    }

    // ---- plist ----
    if ([head isEqualToString:@"plist"]) {
        if ([seg containsObject:@"dump"]) return [YKPlistModule dump:p];
        if ([seg containsObject:@"read"]) return [YKPlistModule read:p];
        return YKErr(@"not_found", path);
    }

    // ---- screen ----
    if ([head isEqualToString:@"screen"]) {
        NSString *verb = seg.count > 1 ? seg[1] : @"info";
        NSDictionary *info = [YKScreenModule info];
        NSDictionary *v = info[@"value"] ?: info;
        if ([verb isEqualToString:@"size"])
            return @{ @"value": @{ @"width": v[@"width"] ?: @0, @"height": v[@"height"] ?: @0 } };
        if ([verb isEqualToString:@"width"])  return @{ @"value": v[@"width"] ?: @0 };
        if ([verb isEqualToString:@"height"]) return @{ @"value": v[@"height"] ?: @0 };
        if ([verb isEqualToString:@"scale"])  return @{ @"value": v[@"scale"] ?: @1 };
        if ([verb isEqualToString:@"dpi"])    return @{ @"value": v[@"dpi"] ?: @163 };
        return info;
    }

    // ---- crypto ----
    if ([head isEqualToString:@"crypto"]) {
        NSRange r = NSMakeRange(1, seg.count > 1 ? seg.count - 1 : 0);
        NSString *verb = seg.count > 1 ? [[seg subarrayWithRange:r] componentsJoinedByString:@"/"] : @"";
        return [YKCryptoModule dispatch:verb body:body ?: @{}];
    }

    // ---- network ----
    if ([head isEqualToString:@"network"]) {
        NSString *verb = seg.count > 1 ? seg[1] : @"";
        if ([verb isEqualToString:@"get"])  return [YKNetworkModule request:body method:@"GET"];
        if ([verb isEqualToString:@"postJSON"] || [verb isEqualToString:@"postForm"] ||
            [verb isEqualToString:@"request"])  return [YKNetworkModule request:body method:@"POST"];
        if ([verb isEqualToString:@"cookies"]) return [YKNetworkModule cookies];
        if ([verb isEqualToString:@"proxy"])   return [YKNetworkModule proxy];
        return YKErr(@"not_found", verb);
    }

    // ---- ui ----
    if ([head isEqualToString:@"ui"]) {
        NSString *e = nil;
        NSDictionary *r = [[YKUIDispatcher shared] dispatchMethod:method path:path body:body error:&e];
        return r ?: YKErr(@"ui_error", e ?: @"派发失败");
    }

    // ---- device（只读，无私有 API）----
    if ([head isEqualToString:@"device"]) {
        UIDevice *d = [UIDevice currentDevice];
        NSString *verb = seg.count > 1 ? seg[1] : @"info";
        if ([verb isEqualToString:@"model"]) return @{ @"value": YkMachine() };
        if ([verb isEqualToString:@"name"])    return @{ @"value": d.name ?: @"" };
        if ([verb isEqualToString:@"systemVersion"] || [verb isEqualToString:@"version"])
            return @{ @"value": d.systemVersion ?: @"" };
        if ([verb isEqualToString:@"uuid"]) return @{ @"value": YkUUID40() };
        if ([verb isEqualToString:@"locale"]) return @{ @"value": YkLocaleJSON() };
        if ([verb isEqualToString:@"isScreenLocked"])
            return @{ @"value": @(NO) };
        if ([verb isEqualToString:@"info"]) {
            CGRect b = [UIScreen mainScreen].bounds;
            return @{ @"value": @{ @"model": YkMachine(),
                                   @"name": d.name ?: @"",
                                   @"systemName": d.systemName ?: @"iOS",
                                   @"systemVersion": d.systemVersion ?: @"",
                                   @"identifier": YkUUID40(),
                                   @"screenWidth": @(b.size.width),
                                   @"screenHeight": @(b.size.height),
                                   @"scale": @([UIScreen mainScreen].scale),
                                   @"locale": YkLocaleJSON() } };
        }
        return YKErr(@"not_found", verb);
    }


    // ---- image（CoreGraphics 子集）----
    if ([head isEqualToString:@"image"]) {
        NSString *verb = seg.count > 1 ? seg[1] : @"info";
        NSString *iid = body[@"imageId"] ?: query[@"imageId"];

        if ([verb isEqualToString:@"create"]) {
            CGFloat w = [body[@"width"] doubleValue] ?: 100, h = [body[@"height"] doubleValue] ?: 100;
            UIGraphicsBeginImageContext(CGSizeMake(w, h));
            UIColor *c = [UIColor whiteColor];
            if ([body[@"color"] isKindOfClass:[NSString class]]) {
                NSString *hex = [body[@"color"] stringByReplacingOccurrencesOfString:@"#" withString:@""];
                unsigned int v = 0; NSScanner *sc = [NSScanner scannerWithString:hex];
                if ([sc scanHexInt:&v]) {
                    c = [UIColor colorWithRed:((v>>16)&0xFF)/255.0 green:((v>>8)&0xFF)/255.0
                                        blue:(v&0xFF)/255.0 alpha:1];
                }
            }
            [c setFill]; UIRectFill(CGRectMake(0,0,w,h));
            UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            NSString *nid = YkNewImageId(img);
            return YkImageInfo(img, nid);
        }

        if ([verb isEqualToString:@"info"]) return YkImageInfo(YkGetImage(iid), iid) ?: YKErr(@"not_found", @"imageId");

        if ([verb isEqualToString:@"capture"]) {
            CGSize sz = [UIScreen mainScreen].bounds.size;
            UIGraphicsBeginImageContextWithOptions(sz, NO, 0);
            UIWindow *w = UIApplication.sharedApplication.keyWindow ?: UIApplication.sharedApplication.windows.firstObject;
            [w drawViewHierarchyInRect:CGRectMake(0,0,sz.width,sz.height) afterScreenUpdates:NO];
            UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            NSString *nid = YkNewImageId(img);
            return YkImageInfo(img, nid);
        }

        UIImage *src = YkGetImage(iid);

        if ([verb isEqualToString:@"getPixel"]) {
            if (!src) return YKErr(@"not_found", @"imageId");
            NSInteger x = [body[@"x"] integerValue], y = [body[@"y"] integerValue];
            CGImageRef cg = src.CGImage;
            if (x < 0 || y < 0 || x >= CGImageGetWidth(cg) || y >= CGImageGetHeight(cg))
                return YKErr(@"invalid argument", @"坐标越界");
            unsigned char px[4] = {0};
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = CGBitmapContextCreate(px, 1, 1, 8, 4, cs, kCGImageAlphaPremultipliedLast);
            CGContextDrawImage(ctx, CGRectMake(-x, -y, CGImageGetWidth(cg), CGImageGetHeight(cg)), cg);
            CGContextRelease(ctx); CGColorSpaceRelease(cs);
            return @{ @"value": @{ @"r": @(px[0]), @"g": @(px[1]), @"b": @(px[2]), @"a": @(px[3]),
                                   @"rgb": @((px[0]<<16)|(px[1]<<8)|px[2]) } };
        }

        if ([verb isEqualToString:@"colorToRGB"]) {
            NSString *hex = [body[@"color"] ?: @"" stringByReplacingOccurrencesOfString:@"#" withString:@""];
            unsigned int v = 0; NSScanner *sc = [NSScanner scannerWithString:hex];
            [sc scanHexInt:&v];
            return @{ @"value": @{ @"r": @((v>>16)&0xFF), @"g": @((v>>8)&0xFF), @"b": @(v&0xFF), @"a": @255,
                                   @"hex": [NSString stringWithFormat:@"#%06X", v & 0xFFFFFF] } };
        }

        if ([verb isEqualToString:@"crop"] || [verb isEqualToString:@"resize"] || [verb isEqualToString:@"rotate"]) {
            if (!src) return YKErr(@"not_found", @"imageId");
            CGSize out;
            CGRect drawRect;
            CGImageRef cg = src.CGImage;
            CGFloat W = CGImageGetWidth(cg), H = CGImageGetHeight(cg);
            if ([verb isEqualToString:@"crop"]) {
                CGFloat x = [body[@"x"] doubleValue], y = [body[@"y"] doubleValue];
                CGFloat w = [body[@"width"] doubleValue] ?: W, h = [body[@"height"] doubleValue] ?: H;
                CGImageRef sub = CGImageCreateWithImageInRect(cg, CGRectMake(x, y, w, h));
                if (!sub) return YKErr(@"invalid argument", @"裁剪区域无效");
                UIImage *img = [UIImage imageWithCGImage:sub scale:src.scale orientation:src.imageOrientation];
                CGImageRelease(sub);
                NSString *nid = YkNewImageId(img);
                return YkImageInfo(img, nid);
            }
            if ([verb isEqualToString:@"resize"]) {
                out = CGSizeMake([body[@"width"] doubleValue] ?: W, [body[@"height"] doubleValue] ?: H);
            } else {
                CGFloat deg = [body[@"degrees"] doubleValue] ?: 90;
                BOOL r = fabs(fmod(deg, 180.0)) == 90.0;
                out = r ? CGSizeMake(H, W) : CGSizeMake(W, H);
            }
            UIGraphicsBeginImageContext(out);
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            if ([verb isEqualToString:@"rotate"]) {
                CGFloat deg = [body[@"degrees"] doubleValue] ?: 90;
                CGContextTranslateCTM(ctx, out.width/2, out.height/2);
                CGContextRotateCTM(ctx, deg * M_PI / 180.0);
                CGContextTranslateCTM(ctx, -W/2, -H/2);
                drawRect = CGRectMake(0, 0, W, H);
            } else {
                drawRect = CGRectMake(0, 0, out.width, out.height);
            }
            CGContextDrawImage(ctx, drawRect, cg);
            UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            NSString *nid = YkNewImageId(img);
            return YkImageInfo(img, nid);
        }

        if ([verb isEqualToString:@"toBase64"] || [verb isEqualToString:@"save"]) {
            if (!src) return YKErr(@"not_found", @"imageId");
            NSData *png = UIImagePNGRepresentation(src);
            if ([verb isEqualToString:@"toBase64"])
                return @{ @"value": @{ @"encoding": @"base64",
                                        @"data": [png base64EncodedStringWithOptions:0],
                                        @"size": @(png.length) } };
            NSString *to = body[@"path"];
            if (!to.length) return YKErr(@"invalid argument", @"缺少 path");
            BOOL ok = [png writeToFile:to atomically:YES];
            return @{ @"value": @(ok) };
        }

        if ([verb isEqualToString:@"release"]) {
            if (iid) [gImages removeObjectForKey:iid];
            return @{ @"value": @YES };
        }
        if ([verb isEqualToString:@"loadBase64"]) {
            NSData *d = [[NSData alloc] initWithBase64EncodedString:body[@"data"] ?: @"" options:0];
            UIImage *img = d ? [UIImage imageWithData:d] : nil;
            if (!img) return YKErr(@"invalid argument", @"不是合法图片");
            NSString *nid = YkNewImageId(img);
            return YkImageInfo(img, nid);
        }
        if ([verb isEqualToString:@"load"]) {
            UIImage *img = [UIImage imageWithContentsOfFile:body[@"path"] ?: @""];
            if (!img) return YKErr(@"not_found", @"文件不可读");
            NSString *nid = YkNewImageId(img);
            return YkImageInfo(img, nid);
        }
        if ([verb isEqualToString:@"releaseAll"]) { [gImages removeAllObjects]; return @{ @"value": @YES }; }
        if ([verb isEqualToString:@"activeCount"]) return @{ @"value": @(gImages.count) };
        return YKErr(@"not_ported", [NSString stringWithFormat:@"image/%@ 需要 OpenCV", verb]);
    }

    return YKErr(@"not_found", path);
}
