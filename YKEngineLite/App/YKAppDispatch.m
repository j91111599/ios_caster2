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
extern NSDictionary *YkMatchTemplate(UIImage *scene, UIImage *tpl, double threshold);
extern NSDictionary *YkTouchTap(double x, double y);
extern NSDictionary *YkTouchLongPress(double x, double y, double d);
extern NSDictionary *YkTouchSwipe(double x1, double y1, double x2, double y2, double d, NSInteger steps);
extern NSDictionary *YkTouchMulti(int fingers, double x1, double y1, double x2, double y2, double d);
extern NSArray *YkMatchTemplateAll(UIImage *scene, UIImage *tpl, double threshold, NSInteger maxResults);
extern NSDictionary *YkMatchTemplateScale(UIImage *scene, UIImage *tpl, double threshold, NSArray *scales, double *usedScale);

static NSString *YkPathForImage(NSString *iid) {
    UIImage *img = iid ? gImages[iid] : nil;
    if (!img) return nil;
    NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"ykimg_%@.png", iid]];
    NSData *d = UIImagePNGRepresentation(img);
    if (![d writeToFile:p atomically:YES]) return nil;
    return p;
}

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

// 像素扫描（纯 C，无 OpenCV）
static BOOL YkPixelAt(UIImage *img, NSInteger x, NSInteger y, int out[4]) {
    CGImageRef cg = img.CGImage;
    if (!cg || x < 0 || y < 0 || x >= (NSInteger)CGImageGetWidth(cg) || y >= (NSInteger)CGImageGetHeight(cg))
        return NO;
    unsigned char px[4] = {0};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, 1, 1, 8, 4, cs, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(ctx, CGRectMake(-x, -y, CGImageGetWidth(cg), CGImageGetHeight(cg)), cg);
    CGContextRelease(ctx); CGColorSpaceRelease(cs);
    out[0] = px[0]; out[1] = px[1]; out[2] = px[2]; out[3] = px[3];
    return YES;
}

static int YkHexColor(id v) {
    if (![v isKindOfClass:[NSString class]]) return -1;
    NSString *hex = [(NSString *)v stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int n = 0;
    NSScanner *sc = [NSScanner scannerWithString:hex];
    if (![sc scanHexInt:&n]) return -1;
    return (int)(n & 0xFFFFFF);
}

// 视图树转 JSON（自检用）
static NSDictionary *YkDumpView(UIView *v, int depth) {
    if (!v || depth > 14) return nil;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"cls"] = NSStringFromClass([v class]);
    d[@"frame"] = NSStringFromCGRect(v.frame);
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        if (l.text.length) d[@"text"] = l.text;
        d[@"font"] = @(l.font.pointSize);
    }
    if ([v isKindOfClass:[UIButton class]]) {
        NSString *t = [((UIButton *)v) titleForState:UIControlStateNormal];
        if (t.length) d[@"title"] = t;
    }
    if ([v isKindOfClass:[UISegmentedControl class]]) {
        UISegmentedControl *sc = (UISegmentedControl *)v;
        d[@"selected"] = @(sc.selectedSegmentIndex);
        d[@"items"] = @(sc.numberOfSegments);
        d[@"actions"] = @([sc actionsForTarget:nil forControlEvent:UIControlEventValueChanged].count);
    }
    if ([v isKindOfClass:[UISwitch class]]) d[@"on"] = @(((UISwitch *)v).isOn);
    if (v.hidden) d[@"hidden"] = @YES;
    if (v.alpha < 0.99) d[@"alpha"] = @(v.alpha);
    if (v.subviews.count) {
        NSMutableArray *kids = [NSMutableArray array];
        for (UIView *c in v.subviews) {
            NSDictionary *cd = YkDumpView(c, depth + 1);
            if (cd) [kids addObject:cd];
        }
        d[@"sub"] = kids;
    }
    return d;
}

static NSDictionary *YkDumpWindow(void) {
    __block NSDictionary *out = nil;
    void (^blk)(void) = ^{
        UIWindow *w = nil;
        for (UIWindow *win in UIApplication.sharedApplication.windows) {
            if (win.isKeyWindow) { w = win; break; }
        }
        if (!w) w = UIApplication.sharedApplication.windows.firstObject;
        if (w) out = YkDumpView(w, 0);
    };
    if ([NSThread isMainThread]) blk();
    else dispatch_sync(dispatch_get_main_queue(), blk);
    return out ?: @{ @"error": @"无窗口" };
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


    // ---- debug（视图树自检）----
    if ([head isEqualToString:@"debug"]) {
        NSString *verb = seg.count > 1 ? seg[1] : @"ui";
        if ([verb isEqualToString:@"ui"]) return @{ @"value": YkDumpWindow() };
        return YKErr(@"not_found", verb);
    }

    // ---- touch（IOHID 注入）----
    if ([head isEqualToString:@"touch"]) {
        NSString *verb = seg.count > 1 ? seg[1] : @"";
        double x = [body[@"x"] doubleValue], y = [body[@"y"] doubleValue];
        if ([verb isEqualToString:@"ping"]) {
            extern NSDictionary *YkTouchPing(void);
            return YkTouchPing();
        }
        if ([verb isEqualToString:@"tap"] || [verb isEqualToString:@"tapAt"])
            return YkTouchTap(x, y);
        if ([verb isEqualToString:@"down"]) {
            return YkTouchLongPress(x, y, 0.05);
        }
        if ([verb isEqualToString:@"longPress"] || [verb isEqualToString:@"longTap"])
            return YkTouchLongPress(x, y, [body[@"duration"] doubleValue] ?: 1.0);
        if ([verb isEqualToString:@"swipe"] || [verb isEqualToString:@"drag"]) {
            double x2 = [body[@"toX"] doubleValue] ?: [body[@"x2"] doubleValue];
            double y2 = [body[@"toY"] doubleValue] ?: [body[@"y2"] doubleValue];
            return YkTouchSwipe(x, y, x2, y2, [body[@"duration"] doubleValue] ?: 0.3,
                                [body[@"steps"] integerValue] ?: 12);
        }
        if ([verb isEqualToString:@"multi"] || [verb isEqualToString:@"pinch"])
            return YkTouchMulti((int)([body[@"fingers"] integerValue] ?: 2),
                                x, y,
                                [body[@"x2"] doubleValue], [body[@"y2"] doubleValue],
                                [body[@"duration"] doubleValue] ?: 0.3);
        return YKErr(@"not_found", verb);
    }

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
            __block UIImage *img = nil;
            void (^doCap)(void) = ^{
                UIWindow *w = nil;
                for (UIWindow *win in UIApplication.sharedApplication.windows) {
                    if (win.isKeyWindow) { w = win; break; }
                }
                if (!w) w = UIApplication.sharedApplication.windows.firstObject;
                if (!w) return;
                CGSize sz = w.bounds.size;
                if (sz.width < 1 || sz.height < 1) sz = [UIScreen mainScreen].bounds.size;
                UIGraphicsBeginImageContextWithOptions(sz, NO, 0);
                CGContextRef ctx = UIGraphicsGetCurrentContext();
                // 先试 drawViewHierarchy，失败再退到 layer 渲染
                BOOL drew = NO;
                @try {
                    drew = [w drawViewHierarchyInRect:CGRectMake(0, 0, sz.width, sz.height)
                                   afterScreenUpdates:YES];
                } @catch (__unused NSException *e) { drew = NO; }
                if (!drew) {
                    @try { [w.layer renderInContext:ctx]; }
                    @catch (__unused NSException *e) { }
                }
                img = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            };
            if ([NSThread isMainThread]) doCap();
            else dispatch_sync(dispatch_get_main_queue(), doCap);
            if (!img) return YKErr(@"capture_failed", @"无可用窗口");
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

        // ---- findColor 系列（纯像素扫描）----
        if ([verb hasPrefix:@"findColor"] || [verb isEqualToString:@"countColor"]) {
            NSInteger maxN = [body[@"maxResults"] integerValue] ?: 100;
            NSArray *colors = body[@"colors"];
            int hex = -1;
            if ([colors isKindOfClass:[NSArray class]] && colors.count) hex = YkHexColor(colors.firstObject);
            else hex = YkHexColor(body[@"color"]);
            if (hex < 0) return YKErr(@"invalid argument", @"缺少 color/colors");
            NSInteger tol = [body[@"tolerance"] integerValue] ?: 0;
            int tr = (hex >> 16) & 0xFF, tg = (hex >> 8) & 0xFF, tb = hex & 0xFF;

            CGRect rect = CGRectZero;
            BOOL hasRect = NO;
            if (body[@"x"] != nil) {
                rect = CGRectMake([body[@"x"] doubleValue], [body[@"y"] doubleValue],
                                  [body[@"width"] doubleValue], [body[@"height"] doubleValue]);
                hasRect = YES;
            }
            if (!src) return YKErr(@"not_found", @"imageId");
            CGImageRef cg = src.CGImage;
            NSInteger W = CGImageGetWidth(cg), H = CGImageGetHeight(cg);
            if (!hasRect || rect.size.width <= 0 || rect.size.height <= 0)
                rect = CGRectMake(0, 0, W, H);

            unsigned char *buf = malloc(W * H * 4);
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = CGBitmapContextCreate(buf, W, H, 8, W * 4, cs, kCGImageAlphaPremultipliedLast);
            CGContextDrawImage(ctx, CGRectMake(0, 0, W, H), cg);
            CGContextRelease(ctx); CGColorSpaceRelease(cs);

            NSMutableArray *hits = [NSMutableArray array];
            NSInteger count = 0;
            NSInteger x0 = MAX(0, (NSInteger)rect.origin.x), x1 = MIN(W, (NSInteger)(rect.origin.x + rect.size.width));
            NSInteger y0 = MAX(0, (NSInteger)rect.origin.y), y1 = MIN(H, (NSInteger)(rect.origin.y + rect.size.height));
            for (NSInteger y = y0; y < y1; y++) {
                for (NSInteger x = x0; x < x1; x++) {
                    unsigned char *p = buf + (y * W + x) * 4;
                    if (abs((int)p[0] - tr) <= tol && abs((int)p[1] - tg) <= tol && abs((int)p[2] - tb) <= tol) {
                        count++;
                        if ([verb isEqualToString:@"countColor"]) continue;
                        if ((NSInteger)hits.count < maxN)
                            [hits addObject:@{ @"x": @(x), @"y": @(y),
                                               @"r": @(p[0]), @"g": @(p[1]), @"b": @(p[2]) }];
                        else if (![verb hasSuffix:@"All"]) { y = y1; break; }
                    }
                }
            }
            free(buf);
            if ([verb isEqualToString:@"countColor"]) return @{ @"value": @(count) };
            if ([verb isEqualToString:@"findColor"])
                return @{ @"value": hits.count ? hits.firstObject : [NSNull null] };
            return @{ @"value": @{ @"count": @(hits.count), @"points": hits } };
        }


        // ---- 多点找色 / 颜色比对 ----
        if ([verb hasPrefix:@"findMultiColor"] || [verb hasPrefix:@"cmpColor"] ||
            [verb isEqualToString:@"colorDiff"] || [verb isEqualToString:@"countMultiColor"]) {
            if (!src) return YKErr(@"not_found", @"imageId");
            NSInteger tol = [body[@"tolerance"] integerValue] ?: 0;
            NSInteger maxN = [body[@"maxResults"] integerValue] ?: 100;

            // 单点比对
            if ([verb hasPrefix:@"cmpColor"]) {
                NSInteger px = [body[@"x"] integerValue], py = [body[@"y"] integerValue];
                NSArray *cArr = [body[@"colors"] isKindOfClass:[NSArray class]] ? body[@"colors"] : nil;
                int hex = YkHexColor(cArr.count ? cArr[0] : body[@"color"]);
                if (hex < 0) return YKErr(@"invalid argument", @"缺少 color");
                int p4[4] = {0};
                if (!YkPixelAt(src, px, py, p4)) return YKErr(@"invalid argument", @"坐标越界");
                int dr = abs(p4[0] - ((hex >> 16) & 0xFF));
                int dg = abs(p4[1] - ((hex >> 8) & 0xFF));
                int db = abs(p4[2] - (hex & 0xFF));
                BOOL ok = (dr <= tol && dg <= tol && db <= tol);
                if ([verb hasSuffix:@"Ex"])
                    return @{ @"value": @{ @"match": @(ok), @"r": @(p4[0]), @"g": @(p4[1]),
                                           @"b": @(p4[2]), @"dr": @(dr), @"dg": @(dg), @"db": @(db) } };
                return @{ @"value": @(ok) };
            }

            // 多点找色：anchor + points[{dx,dy,color}]
            NSArray *pts = body[@"points"];
            if (![pts isKindOfClass:[NSArray class]] || !pts.count)
                return YKErr(@"invalid argument", @"缺少 points");
            NSInteger ax = [body[@"anchorX"] integerValue] ?: [body[@"x"] integerValue];
            NSInteger ay = [body[@"anchorY"] integerValue] ?: [body[@"y"] integerValue];
            CGRect rect = CGRectMake(0, 0, CGImageGetWidth(src.CGImage), CGImageGetHeight(src.CGImage));
            if (body[@"region"] && [body[@"region"] isKindOfClass:[NSDictionary class]]) {
                NSDictionary *rg = body[@"region"];
                rect = CGRectMake([rg[@"x"] doubleValue], [rg[@"y"] doubleValue],
                                  [rg[@"width"] doubleValue], [rg[@"height"] doubleValue]);
            }
            NSMutableArray *hits = [NSMutableArray array];
            NSInteger count = 0;
            for (NSInteger y = (NSInteger)rect.origin.y; y < (NSInteger)(rect.origin.y + rect.size.height); y++) {
                for (NSInteger x = (NSInteger)rect.origin.x; x < (NSInteger)(rect.origin.x + rect.size.width); x++) {
                    BOOL all = YES;
                    for (NSDictionary *pt in pts) {
                        NSInteger qx = x + [pt[@"dx"] integerValue];
                        NSInteger qy = y + [pt[@"dy"] integerValue];
                        int hex = YkHexColor(pt[@"color"]);
                        if (hex < 0) { all = NO; break; }
                        int p4[4] = {0};
                        if (!YkPixelAt(src, qx, qy, p4)) { all = NO; break; }
                        if (abs(p4[0] - ((hex >> 16) & 0xFF)) > tol ||
                            abs(p4[1] - ((hex >> 8) & 0xFF)) > tol ||
                            abs(p4[2] - (hex & 0xFF)) > tol) { all = NO; break; }
                    }
                    if (!all) continue;
                    count++;
                    if ([verb isEqualToString:@"countMultiColor"]) continue;
                    if ((NSInteger)hits.count < maxN)
                        [hits addObject:@{ @"x": @(x), @"y": @(y) }];
                    if ((NSInteger)hits.count >= maxN && ![verb hasSuffix:@"All"]) { y = (NSInteger)(rect.origin.y + rect.size.height); break; }
                }
            }
            if ([verb isEqualToString:@"countMultiColor"]) return @{ @"value": @(count) };
            if ([verb hasSuffix:@"All"]) return @{ @"value": @{ @"count": @(hits.count), @"points": hits } };
            return @{ @"value": hits.count ? hits.firstObject : [NSNull null] };
        }

        // ---- findImage（OpenCV 模板匹配）----
        if ([verb hasPrefix:@"findImage"] || [verb hasPrefix:@"opencvFindImage"]) {
            if (!src) return YKErr(@"not_found", @"imageId");
            NSString *srcPath = YkPathForImage(iid);
            id tplObj = body[@"template"] ?: body[@"templatePath"] ?: body[@"imageId2"];
            NSString *tplPath = nil;
            if ([tplObj isKindOfClass:[NSString class]] && [(NSString *)tplObj hasPrefix:@"/"]) {
                tplPath = tplObj;
            } else {
                tplPath = YkPathForImage((NSString *)tplObj);
            }
            if (!srcPath || !tplPath) return YKErr(@"invalid argument", @"模板需为本地路径或已加载的 imageId");
            double th = [body[@"threshold"] doubleValue] ?: 0.8;
            NSInteger maxN = [body[@"maxResults"] integerValue] ?: 100;
            BOOL all = [verb hasSuffix:@"All"];
            UIImage *tplImg = [UIImage imageWithContentsOfFile:tplPath];
            if (!tplImg) return YKErr(@"not_found", @"模板文件不可读");
            if ([verb hasPrefix:@"findImageScale"]) {
                double used = 1.0;
                NSDictionary *hit = YkMatchTemplateScale(src, tplImg, th, body[@"scales"], &used);
                if (hit) { NSMutableDictionary *m = [hit mutableCopy]; m[@"scale"] = @(used); return @{ @"value": m }; }
                return @{ @"value": [NSNull null] };
            }
            if ([verb hasSuffix:@"All"]) {
                NSArray *hits = YkMatchTemplateAll(src, tplImg, th, maxN);
                return @{ @"value": @{ @"count": @(hits.count), @"matches": hits } };
            }
            NSDictionary *hit = YkMatchTemplate(src, tplImg, th);
            return @{ @"value": hit ?: [NSNull null] };
        }
        if ([verb isEqualToString:@"releaseAll"]) { [gImages removeAllObjects]; return @{ @"value": @YES }; }
        if ([verb isEqualToString:@"activeCount"]) return @{ @"value": @(gImages.count) };
        return YKErr(@"not_ported", [NSString stringWithFormat:@"image/%@ 需要 OpenCV", verb]);
    }

    return YKErr(@"not_found", path);
}

