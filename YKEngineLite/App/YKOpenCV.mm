//  YKOpenCV.mm — 模板匹配（OpenCV 子集）
//
//  覆盖：image/findImage、findImageAll、findImageBatch、findImageScale
//  依赖：opencv2.framework（CI 下载，链接见 Makefile）
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>

static NSMutableDictionary *gImages = nil;

extern "C" NSDictionary *YkOpenCVFindImage(NSString *iid, NSString *tplPath,
                                           double threshold, NSInteger maxResults,
                                           BOOL all);

static cv::Mat YkMatFromUIImage(UIImage *img) {
    cv::Mat m;
    UIImageToMat(img, m, true);
    if (m.channels() == 4) cv::cvtColor(m, m, cv::COLOR_RGBA2BGR);
    return m;
}

extern "C" NSDictionary *YkOpenCVFindImage(NSString *iid, NSString *tplPath,
                                           double threshold, NSInteger maxResults,
                                           BOOL all)
{
    if (!gImages) { /* 由 YKAppDispatch 的注册表共享，这里只做兜底 */ }

    // 源图：优先用文件路径（避免跨 TU 共享字典）
    UIImage *tpl = [UIImage imageWithContentsOfFile:tplPath ?: @""];
    if (!tpl) return @{ @"value": @{ @"error": @"not_found", @"message": @"模板文件不可读" } };

    NSString *srcPath = nil;
    if (iid.length) srcPath = [[NSUserDefaults standardUserDefaults] stringForKey:[@"ykimg_" stringByAppendingString:iid]];
    UIImage *src = srcPath.length ? [UIImage imageWithContentsOfFile:srcPath] : nil;
    if (!src) return @{ @"value": @{ @"error": @"not_found", @"message": @"imageId 无对应文件" } };

    cv::Mat scene = YkMatFromUIImage(src);
    cv::Mat templ = YkMatFromUIImage(tpl);
    if (scene.empty() || templ.empty())
        return @{ @"value": @{ @"error": @"invalid argument", @"message": @"图像解码失败" } };
    if (templ.cols > scene.cols || templ.rows > scene.rows)
        return @{ @"value": @{ @"error": @"invalid argument", @"message": @"模板大于原图" } };

    cv::Mat result;
    cv::matchTemplate(scene, templ, result, cv::TM_CCOEFF_NORMED);

    NSMutableArray *hits = [NSMutableArray array];
    NSInteger limit = maxResults > 0 ? maxResults : 100;
    double th = threshold > 0 ? threshold : 0.8;

    if (!all) {
        double minV, maxV; cv::Point minL, maxL;
        cv::minMaxLoc(result, &minV, &maxV, &minL, &maxL);
        if (maxV >= th) {
            [hits addObject:@{ @"x": @(maxL.x), @"y": @(maxL.y),
                               @"width": @(templ.cols), @"height": @(templ.rows),
                               @"score": @(maxV),
                               @"centerX": @(maxL.x + templ.cols / 2),
                               @"centerY": @(maxL.y + templ.rows / 2) }];
        }
    } else {
        cv::Mat mask = result >= th;
        std::vector<cv::Point> pts;
        cv::findNonZero(mask, pts);
        std::sort(pts.begin(), pts.end(), [&](cv::Point a, cv::Point b) { return result.at<float>(a) > result.at<float>(b); });
        NSInteger taken = 0;
        for (auto &p : pts) {
            if (taken >= limit) break;
            bool dup = false;
            for (NSDictionary *h in hits) {
                int hx = [h[@"x"] intValue], hy = [h[@"y"] intValue];
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
    }

    if (!all) return @{ @"value": hits.count ? hits.firstObject : [NSNull null] };
    return @{ @"value": @{ @"count": @(hits.count), @"matches": hits } };
}
