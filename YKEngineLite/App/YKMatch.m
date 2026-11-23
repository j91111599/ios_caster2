//  YKMatch.m — 纯 C 模板匹配（替代 OpenCV）
//
//  算法：灰度下采样 → ZNCC（零均值归一化互相关）粗搜 → 全分辨率精修
//  复杂度：O(粗搜位置数 × 模板面积 / f²) + O(精修窗口 × 模板面积)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// 文件日志（设备上可直接 /file/read 读取）
static void YkLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[%.3f] %@\n",
                      [[NSDate date] timeIntervalSince1970], msg];
    NSString *path = @"/tmp/yk_match.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]; return; }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

typedef struct { int w, h; unsigned char *g; } YkGray;

static YkGray YkGrayFromImage(UIImage *img) {
    YkGray r = {0, 0, NULL};
    CGImageRef cg = img.CGImage;
    if (!cg) return r;

    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    size_t bpr = CGImageGetBytesPerRow(cg);
    size_t bpp = CGImageGetBitsPerPixel(cg) / 8;
    if (w == 0 || h == 0 || bpp < 3) return r;

    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(cg));
    if (!data) return r;
    const uint8_t *p = CFDataGetBytePtr(data);
    size_t len = CFDataGetLength(data);
    if (!p || len < bpr * h) { CFRelease(data); return r; }

    // 判断通道顺序（BGRA 最常见）
    CGBitmapInfo info = CGImageGetBitmapInfo(cg);
    BOOL bgra = ((info & kCGBitmapByteOrder32Little) == kCGBitmapByteOrder32Little);

    unsigned char *g = malloc(w * h);
    size_t nonzero = 0;
    for (size_t y = 0; y < h; y++) {
        const uint8_t *row = p + y * bpr;
        for (size_t x = 0; x < w; x++) {
            const uint8_t *px = row + x * bpp;
            int R, G, B;
            if (bgra) { B = px[0]; G = px[1]; R = px[2]; }
            else      { R = px[0]; G = px[1]; B = px[2]; }
            unsigned char v = (unsigned char)((R * 77 + G * 150 + B * 29) >> 8);
            g[y * w + x] = v;
            if (v) nonzero++;
        }
    }
    CFRelease(data);

    YkLog(@"gray %zux%zu bpr=%zu bpp=%zu bgra=%d nonzero=%zu", w, h, bpr, bpp, bgra, nonzero);
    r.w = (int)w; r.h = (int)h; r.g = g;
    return r;
}

static void YkGrayFree(YkGray *a) { if (a->g) { free(a->g); a->g = NULL; } }

// 按整数因子下采样（盒式平均）
static YkGray YkDownsample(YkGray src, int f) {
    if (f <= 1) {
        YkGray c = src; c.g = malloc(src.w * src.h); memcpy(c.g, src.g, src.w * src.h); return c;
    }
    int w = src.w / f, h = src.h / f;
    YkGray r = {w, h, malloc(w * h)};
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            int sum = 0;
            for (int dy = 0; dy < f; dy++)
                for (int dx = 0; dx < f; dx++)
                    sum += src.g[(y * f + dy) * src.w + (x * f + dx)];
            r.g[y * w + x] = (unsigned char)(sum / (f * f));
        }
    }
    return r;
}

// ZNCC 单点打分，返回 [-1, 1]
static double YkZNCC(YkGray s, YkGray t, int ox, int oy) {
    double sumS = 0, sumT = 0, sumSS = 0, sumTT = 0, sumST = 0;
    int n = t.w * t.h;
    for (int y = 0; y < t.h; y++) {
        const unsigned char *sp = s.g + (oy + y) * s.w + ox;
        const unsigned char *tp = t.g + y * t.w;
        for (int x = 0; x < t.w; x++) {
            int a = sp[x], b = tp[x];
            sumS += a; sumT += b; sumSS += a * a; sumTT += b * b; sumST += a * b;
        }
    }
    double num = n * sumST - sumS * sumT;
    double d1 = n * sumSS - sumS * sumS;
    double d2 = n * sumTT - sumT * sumT;
    double den = sqrt(d1 * d2);
    if (den < 1e-9) return 0;
    return num / den;
}

// 返回 @{x,y,score} 或 nil
NSDictionary *YkMatchTemplate(UIImage *sceneImg, UIImage *tplImg, double threshold)
{
    YkLog(@"enter scene=%@ tpl=%@", sceneImg ? @"Y" : @"N", tplImg ? @"Y" : @"N");
    if (!sceneImg || !tplImg) { YkLog(@"nil image"); return nil; }
    YkGray scene = YkGrayFromImage(sceneImg);
    YkGray tpl = YkGrayFromImage(tplImg);
    YkLog(@"gray scene=%dx%d tpl=%dx%d", scene.w, scene.h, tpl.w, tpl.h);
    if (!scene.g || !tpl.g) { YkLog(@"gray fail"); YkGrayFree(&scene); YkGrayFree(&tpl); return nil; }
    if (tpl.w > scene.w || tpl.h > scene.h) { YkLog(@"tpl larger"); YkGrayFree(&scene); YkGrayFree(&tpl); return nil; }

    // 粗搜因子：上限 4，避免过度下采样导致定位漂移
    int f = 1;
    int mn = MIN(tpl.w, tpl.h);
    while (mn / (f * 2) >= 8 && f < 4) f *= 2;

    YkGray sS = YkDownsample(scene, f);
    YkGray tS = YkDownsample(tpl, f);
    if (tS.w < 2 || tS.h < 2) { YkGrayFree(&scene); YkGrayFree(&tpl); YkGrayFree(&sS); YkGrayFree(&tS); return nil; }

    // 粗搜：保留 top-K 候选（含方差过滤）
    int K = 8;
    double bestScore[8]; int bestX[8], bestY[8];
    for (int i = 0; i < K; i++) { bestScore[i] = -2; bestX[i] = 0; bestY[i] = 0; }

    int maxX = sS.w - tS.w, maxY = sS.h - tS.h;
    for (int y = 0; y <= maxY; y++) {
        for (int x = 0; x <= maxX; x++) {
            double v = YkZNCC(sS, tS, x, y);
            if (v <= bestScore[K-1]) continue;
            // 插入排序到 top-K
            int pos = K - 1;
            while (pos > 0 && bestScore[pos-1] < v) {
                bestScore[pos] = bestScore[pos-1]; bestX[pos] = bestX[pos-1]; bestY[pos] = bestY[pos-1];
                pos--;
            }
            bestScore[pos] = v; bestX[pos] = x; bestY[pos] = y;
        }
    }
    YkGrayFree(&sS); YkGrayFree(&tS);

    // 对每个候选做全分辨率精修
    double bestFine = -2; int fx = 0, fy = 0;
    for (int k = 0; k < K; k++) {
        if (bestScore[k] <= -2) continue;
        int cx = bestX[k] * f, cy = bestY[k] * f;
        for (int dy = -f; dy <= f; dy++) {
            for (int dx = -f; dx <= f; dx++) {
                int nx = cx + dx, ny = cy + dy;
                if (nx < 0 || ny < 0 || nx + tpl.w > scene.w || ny + tpl.h > scene.h) continue;
                double v = YkZNCC(scene, tpl, nx, ny);
                if (v > bestFine) { bestFine = v; fx = nx; fy = ny; }
            }
        }
    }
    YkLog(@"best=%.4f at (%d,%d) f=%d th=%.2f", bestFine, fx, fy, f, threshold);
    YkGrayFree(&scene); YkGrayFree(&tpl);

    if (bestFine < threshold) return nil;
    return @{ @"x": @(fx), @"y": @(fy),
              @"width": @(tplImg.size.width * tplImg.scale),
              @"height": @(tplImg.size.height * tplImg.scale),
              @"score": @(bestFine),
              @"centerX": @(fx + tplImg.size.width * tplImg.scale / 2),
              @"centerY": @(fy + tplImg.size.height * tplImg.scale / 2) };
}

// 多目标匹配：粗搜收集全部候选 → 按分数降序 → 距离 NMS → 逐个精修
NSArray *YkMatchTemplateAll(UIImage *sceneImg, UIImage *tplImg, double threshold, NSInteger maxResults)
{
    if (!sceneImg || !tplImg) return @[];
    YkGray scene = YkGrayFromImage(sceneImg);
    YkGray tpl = YkGrayFromImage(tplImg);
    if (!scene.g || !tpl.g) { YkGrayFree(&scene); YkGrayFree(&tpl); return @[]; }
    if (tpl.w > scene.w || tpl.h > scene.h) { YkGrayFree(&scene); YkGrayFree(&tpl); return @[]; }

    int f = 1;
    int mn = MIN(tpl.w, tpl.h);
    while (mn / (f * 2) >= 8 && f < 4) f *= 2;

    YkGray sS = YkDownsample(scene, f);
    YkGray tS = YkDownsample(tpl, f);
    NSMutableArray *out = [NSMutableArray array];
    if (tS.w >= 2 && tS.h >= 2) {
        NSInteger limit = maxResults > 0 ? maxResults : 20;

        // 步骤 1：收集所有超过阈值的候选
        NSMutableArray *cands = [NSMutableArray array];
        for (int y = 0; y <= sS.h - tS.h; y++) {
            for (int x = 0; x <= sS.w - tS.w; x++) {
                double v = YkZNCC(sS, tS, x, y);
                if (v < threshold) continue;
                [cands addObject:@{ @"x": @(x), @"y": @(y), @"s": @(v) }];
            }
        }
        // 步骤 2：按分数降序
        [cands sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            double va = [a[@"s"] doubleValue], vb = [b[@"s"] doubleValue];
            if (va > vb) return NSOrderedAscending;
            if (va < vb) return NSOrderedDescending;
            return NSOrderedSame;
        }];

        // 步骤 3：距离 NMS + 全分辨率精修
        int minDist = MAX(tS.w, tS.h);
        for (NSDictionary *c in cands) {
            if ((NSInteger)out.count >= limit) break;
            int cx0 = [c[@"x"] intValue], cy0 = [c[@"y"] intValue];
            BOOL dup = NO;
            for (NSDictionary *h in out) {
                int hx = [h[@"x"] intValue] / f, hy = [h[@"y"] intValue] / f;
                if (abs(hx - cx0) < minDist && abs(hy - cy0) < minDist) { dup = YES; break; }
            }
            if (dup) continue;

            int cx = cx0 * f, cy = cy0 * f;
            double bestV = [c[@"s"] doubleValue]; int bx = cx, by = cy;
            for (int dy = -f; dy <= f; dy++) {
                for (int dx = -f; dx <= f; dx++) {
                    int nx = cx + dx, ny = cy + dy;
                    if (nx < 0 || ny < 0 || nx + tpl.w > scene.w || ny + tpl.h > scene.h) continue;
                    double vv = YkZNCC(scene, tpl, nx, ny);
                    if (vv > bestV) { bestV = vv; bx = nx; by = ny; }
                }
            }
            if (bestV >= threshold) {
                [out addObject:@{ @"x": @(bx), @"y": @(by),
                                  @"width": @(tpl.w), @"height": @(tpl.h),
                                  @"score": @(bestV),
                                  @"centerX": @(bx + tpl.w / 2),
                                  @"centerY": @(by + tpl.h / 2) }];
            }
        }
    }
    YkGrayFree(&sS); YkGrayFree(&tS); YkGrayFree(&scene); YkGrayFree(&tpl);
    YkLog(@"multi-match count=%lu", (unsigned long)out.count);
    return out;
}

// 多尺度匹配：按 scales 依次尝试，取最高分
NSDictionary *YkMatchTemplateScale(UIImage *sceneImg, UIImage *tplImg, double threshold,
                                   NSArray *scales, double *usedScale)
{
    NSDictionary *best = nil; double bestScore = -2; double bestScale = 1.0;
    NSArray *list = [scales isKindOfClass:[NSArray class]] && scales.count
                    ? scales : @[@0.8, @1.0, @1.2, @1.5];
    for (NSNumber *sn in list) {
        double sc = [sn doubleValue];
        if (sc <= 0.1 || sc > 4.0) continue;
        CGSize sz = CGSizeMake(tplImg.size.width * sc, tplImg.size.height * sc);
        if (sz.width < 4 || sz.height < 4) continue;
        if (sz.width > sceneImg.size.width || sz.height > sceneImg.size.height) continue;
        UIGraphicsBeginImageContextWithOptions(sz, NO, 1.0);
        [tplImg drawInRect:CGRectMake(0, 0, sz.width, sz.height)];
        UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSDictionary *hit = YkMatchTemplate(sceneImg, scaled, threshold);
        if (hit && [hit[@"score"] doubleValue] > bestScore) {
            bestScore = [hit[@"score"] doubleValue];
            best = hit; bestScale = sc;
        }
    }
    if (usedScale) *usedScale = bestScale;
    return best;
}
