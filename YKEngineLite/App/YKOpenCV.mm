//  YKOpenCV.mm — 模板匹配（最小依赖：core + imgproc）
//
//  必须在任何 Apple 头之前 include OpenCV 的 C++ 头，
//  且不要用 opencv.hpp 伞头（会拉进 stitching/*，与 Apple 的 NO 宏冲突）。
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// UIImage -> BGR cv::Mat（自实现，避开 imgcodecs/ios.h 的头文件顺序问题）
static cv::Mat YkMatFromUIImage(UIImage *img) {
    CGImageRef cg = img.CGImage;
    if (!cg) return cv::Mat();
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    cv::Mat rgba((int)h, (int)w, CV_8UC4);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgba.data, w, h, 8, rgba.step[0], cs,
                                             kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    cv::Mat bgr;
    cv::cvtColor(rgba, bgr, cv::COLOR_RGBA2BGR);
    return bgr;
}

extern "C" NSDictionary *YkOpenCVFindImage(NSString *srcPath, NSString *tplPath,
                                           double threshold, NSInteger maxResults,
                                           BOOL all)
{
    UIImage *src = srcPath.length ? [UIImage imageWithContentsOfFile:srcPath] : nil;
    UIImage *tpl = tplPath.length ? [UIImage imageWithContentsOfFile:tplPath] : nil;
    if (!src) return @{ @"value": @{ @"error": @"not_found", @"message": @"原图不可读" } };
    if (!tpl) return @{ @"value": @{ @"error": @"not_found", @"message": @"模板不可读" } };

    cv::Mat scene = YkMatFromUIImage(src);
    cv::Mat templ = YkMatFromUIImage(tpl);
    if (scene.empty() || templ.empty())
        return @{ @"value": @{ @"error": @"invalid argument", @"message": @"解码失败" } };
    if (templ.cols > scene.cols || templ.rows > scene.rows)
        return @{ @"value": @{ @"error": @"invalid argument", @"message": @"模板大于原图" } };

    cv::Mat result;
    cv::matchTemplate(scene, templ, result, cv::TM_CCOEFF_NORMED);

    NSMutableArray *hits = [NSMutableArray array];
    NSInteger limit = maxResults > 0 ? maxResults : 100;
    double th = threshold > 0 ? threshold : 0.8;

    if (!all) {
        double minV = 0, maxV = 0;
        cv::Point minL, maxL;
        cv::minMaxLoc(result, &minV, &maxV, &minL, &maxL);
        if (maxV >= th) {
            [hits addObject:@{ @"x": @(maxL.x), @"y": @(maxL.y),
                               @"width": @(templ.cols), @"height": @(templ.rows),
                               @"score": @(maxV),
                               @"centerX": @(maxL.x + templ.cols / 2),
                               @"centerY": @(maxL.y + templ.rows / 2) }];
        }
        return @{ @"value": hits.count ? hits.firstObject : [NSNull null] };
    }

    cv::Mat mask = result >= th;
    std::vector<cv::Point> pts;
    cv::findNonZero(mask, pts);
    std::sort(pts.begin(), pts.end(),
              [&](cv::Point a, cv::Point b) { return result.at<float>(a) > result.at<float>(b); });
    NSInteger taken = 0;
    for (size_t i = 0; i < pts.size() && taken < limit; i++) {
        cv::Point p = pts[i];
        bool dup = false;
        for (NSDictionary *hb in hits) {
            int hx = [hb[@"x"] intValue], hy = [hb[@"y"] intValue];
            if (abs(hx - p.x) < templ.cols / 2 && abs(hy - p.y) < templ.rows / 2) { dup = true; break; }
        }
        if (dup) continue;
        [hits addObject:@{ @"x": @(p.x), @"y": @(p.y),
                           @"width": @(templ.cols), @"height": @(templ.rows),
                           @"score": @(result.at<float>(p)),
                           @"centerX": @(p.x + templ.cols / 2),
                           @"centerY": @(p.y + templ.rows / 2) }];
        taken++;
    }
    return @{ @"value": @{ @"count": @(hits.count), @"matches": hits } };
}
