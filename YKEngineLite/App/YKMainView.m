//  YKMainView —— 三页复刻（纯 frame 布局）
//  几何/配色来源：设备实测 /element/tree + 截图像素采样（750x1334 @2x）
//    导航条 0..64pt（状态栏 20 + 44），卡片 x=20 宽 335，卡片内边距 20
//    蓝色 #24A1F1、页面底色 #F6F5FA、行高 68、磁贴 142x80、磁贴间距 12
//    磁贴底色：设备IP #EBF5FF / 越狱 #FCEBEB / 分辨率 #EFF9FB / 版本 #FFF7EC
#import <UIKit/UIKit.h>

static UIColor *YkBlue(void)    { return [UIColor colorWithRed:0.141 green:0.631 blue:0.945 alpha:1.0]; } // #24A1F1
static UIColor *YkPageBg(void)  { return [UIColor colorWithRed:0.965 green:0.961 blue:0.980 alpha:1.0]; } // #F6F5FA
static UIColor *YkSub(void)     { return [UIColor colorWithRed:0.541 green:0.541 blue:0.561 alpha:1.0]; }
static UIColor *YkMain(void)    { return [UIColor colorWithWhite:0.08 alpha:1.0]; }
static UIColor *YkLine(void)    { return [UIColor colorWithWhite:0.90 alpha:1.0]; }
static UIColor *YkTint(void)    { return YkBlue(); }
static UIColor *YkPurple(void)  { return [UIColor colorWithRed:0.44 green:0.36 blue:0.86 alpha:1.0]; }
static UIColor *YkRed(void)     { return [UIColor colorWithRed:0.93 green:0.35 blue:0.33 alpha:1.0]; }
static UIColor *YkTeal(void)     { return [UIColor colorWithRed:0.31 green:0.71 blue:0.78 alpha:1.0]; }
static UIColor *YkOrange(void)  { return [UIColor colorWithRed:0.96 green:0.63 blue:0.22 alpha:1.0]; }
static UIColor *YkGreen(void)   { return [UIColor colorWithRed:0.20 green:0.72 blue:0.42 alpha:1.0]; }

#define NAV_H      64.0
#define CARD_X     20.0
#define CARD_W     335.0
#define INNER_PAD  20.0

@interface YKMainView : UIView
@property (nonatomic, strong) UIScrollView *devScroll;
@property (nonatomic, strong) UIScrollView *scriptScroll;
@property (nonatomic, strong) UIScrollView *recordScroll;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *lblHttpStatus;
@property (nonatomic, strong) UILabel *lblPort;
@property (nonatomic, strong) UILabel *lblState;
@property (nonatomic, strong) UILabel *lblScriptCount;
@property (nonatomic, strong) UILabel *lblScriptEmpty;
- (UILabel *)ykLabel:(NSString *)t size:(CGFloat)s bold:(BOOL)b color:(UIColor *)c;
- (UIView *)ykCard:(CGRect)r;
- (UIView *)ykIconBox:(CGRect)r symbol:(NSString *)n tint:(UIColor *)tint glyph:(CGFloat)g;
- (UIView *)ykCardHeader:(UIView *)card title:(NSString *)t symbol:(NSString *)n tint:(UIColor *)tint;
- (void)ykTab:(UIButton *)sender;
- (void)ykShowPageObj:(id)o;
- (void)ykReloadScripts;
@end

@implementation YKMainView {
    CGFloat _W, _H;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = YkPageBg();
        _W = frame.size.width  > 1 ? frame.size.width  : 375.0;
        _H = frame.size.height > 1 ? frame.size.height : 667.0;
        [self ykHeader];
        [self ykDevicePage];
        [self ykScriptPage];
        [self ykRecordPage];
        [self ykBottom];
    }
    return self;
}

#pragma mark - 基础控件

- (UILabel *)ykLabel:(NSString *)t size:(CGFloat)s bold:(BOOL)b color:(UIColor *)c {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = b ? [UIFont boldSystemFontOfSize:s] : [UIFont systemFontOfSize:s];
    l.textColor = c ?: YkMain();
    l.backgroundColor = [UIColor clearColor];
    return l;
}

- (UIView *)ykCard:(CGRect)r {
    UIView *v = [[UIView alloc] initWithFrame:r];
    v.backgroundColor = [UIColor whiteColor];
    v.layer.cornerRadius = 12.0;
    v.layer.shadowColor = [UIColor blackColor].CGColor;
    v.layer.shadowOpacity = 0.05;
    v.layer.shadowRadius = 8.0;
    v.layer.shadowOffset = CGSizeMake(0, 2);
    return v;
}

// 圆角方形图标底 + 字形（原版所有图标都是这种「浅色底 + 同色系字形」）
- (UIView *)ykIconBox:(CGRect)r symbol:(NSString *)n tint:(UIColor *)tint glyph:(CGFloat)g {
    UIView *box = [[UIView alloc] initWithFrame:r];
    box.backgroundColor = [tint colorWithAlphaComponent:0.12];
    box.layer.cornerRadius = r.size.width / 2.0;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake((r.size.width - g) / 2.0,
                                                                   (r.size.height - g) / 2.0, g, g)];
    iv.image = [UIImage systemImageNamed:n];
    iv.tintColor = tint;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    [box addSubview:iv];
    return box;
}

// 卡片头：36x36 图标 + 标题（相对卡片坐标 20,20 / 66,28）
- (UIView *)ykCardHeader:(UIView *)card title:(NSString *)t symbol:(NSString *)n tint:(UIColor *)tint {
    [card addSubview:[self ykIconBox:CGRectMake(INNER_PAD, 20, 36, 36) symbol:n tint:tint glyph:20]];
    UILabel *lbl = [self ykLabel:t size:17 bold:YES color:YkMain()];
    lbl.frame = CGRectMake(66, 27, 200, 22);
    [card addSubview:lbl];
    return lbl;
}

#pragma mark - 顶部导航

- (void)ykHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _W, NAV_H)];
    header.backgroundColor = YkBlue();
    [self addSubview:header];

    UIButton *home = [UIButton buttonWithType:UIButtonTypeSystem];
    home.frame = CGRectMake(4, 20, 44, 44);
    [home setImage:[UIImage systemImageNamed:@"house.fill"] forState:UIControlStateNormal];
    home.tintColor = [UIColor whiteColor];
    [header addSubview:home];

    UILabel *title = [self ykLabel:@"远控 Pro" size:20 bold:YES color:[UIColor whiteColor]];
    title.textAlignment = NSTextAlignmentCenter;
    title.frame = CGRectMake(0, 30, _W, 26);
    [header addSubview:title];
}

#pragma mark - 设备页

- (void)ykDevicePage {
    _devScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, NAV_H, _W, _H - NAV_H)];
    _devScroll.contentInset = UIEdgeInsetsMake(0, 0, 88, 0);
    _devScroll.showsVerticalScrollIndicator = NO;
    [self addSubview:_devScroll];

    // ---------- 卡片一：连接设备 ----------
    UIView *c1 = [self ykCard:CGRectMake(CARD_X, 20, CARD_W, 324)];
    [_devScroll addSubview:c1];
    [self ykCardHeader:c1 title:@"连接设备" symbol:@"dot.radiowaves.left.and.right" tint:YkBlue()];

    UIButton *scan = [UIButton buttonWithType:UIButtonTypeSystem];
    scan.frame = CGRectMake(CARD_W - INNER_PAD - 96, 20, 96, 36);
    [scan setTitle:@"  扫码连接" forState:UIControlStateNormal];
    [scan setImage:[UIImage systemImageNamed:@"qrcode.viewfinder"] forState:UIControlStateNormal];
    scan.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    scan.backgroundColor = [YkBlue() colorWithAlphaComponent:0.10];
    scan.layer.cornerRadius = 10.0;
    [scan setTitleColor:YkBlue() forState:UIControlStateNormal];
    scan.tintColor = YkBlue();
    [c1 addSubview:scan];

    NSArray *rows = @[ @[@"服务开关", @"允许局域网电脑接入当前设备", @"bolt.fill", @1],
                       @[@"广域网", @"允许外网通过安全隧道接入当前设备", @"globe", @0],
                       @[@"未连接设备", @"当前暂无电脑接入", @"display", @(-1)] ];
    for (NSInteger i = 0; i < 3; i++) {
        NSArray *r = rows[i];
        BOOL on = [r[3] intValue] == 1;
        CGFloat y = 72 + i * 80;
        CGFloat h = ([r[3] intValue] < 0) ? 72 : 68;
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, y, CARD_W - INNER_PAD * 2, h)];
        // 开启 → 淡蓝底蓝边；关闭 → 白底灰边
        row.backgroundColor = on ? [YkBlue() colorWithAlphaComponent:0.06] : [UIColor whiteColor];
        row.layer.cornerRadius = 12.0;
        row.layer.borderWidth = 1.0;
        row.layer.borderColor = (on ? [YkBlue() colorWithAlphaComponent:0.18]
                                    : [UIColor colorWithWhite:0.93 alpha:1.0]).CGColor;
        [c1 addSubview:row];

        CGFloat iconSize = ([r[3] intValue] < 0) ? 42 : 44;
        CGFloat iconY = ([r[3] intValue] < 0) ? 15 : 12;
        UIColor *tint = on ? YkBlue() : [UIColor colorWithWhite:0.62 alpha:1.0];
        [row addSubview:[self ykIconBox:CGRectMake(14, iconY, iconSize, iconSize)
                                 symbol:r[2] tint:tint glyph:24]];

        UILabel *tt = [self ykLabel:r[0] size:17 bold:YES color:YkMain()];
        tt.frame = CGRectMake(68, ([r[3] intValue] < 0) ? 17 : 15, 160, 22);
        [row addSubview:tt];
        UILabel *ss = [self ykLabel:r[1] size:12 bold:NO color:YkSub()];
        ss.frame = CGRectMake(68, ([r[3] intValue] < 0) ? 40 : 38, 170, 16);
        [row addSubview:ss];

        if ([r[3] intValue] >= 0) {
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(row.bounds.size.width - 51 - 12,
                                                                      18, 51, 31)];
            sw.on = on; sw.onTintColor = YkBlue();
            [row addSubview:sw];
        } else {
            UILabel *pill = [self ykLabel:@"待接入" size:12 bold:NO color:YkSub()];
            pill.textAlignment = NSTextAlignmentRight;
            pill.frame = CGRectMake(row.bounds.size.width - 74, 26, 62, 18);
            [row addSubview:pill];
        }
    }

    // ---------- 卡片二：运行状态 ----------
    UIView *c2 = [self ykCard:CGRectMake(CARD_X, 364, CARD_W, 264)];
    [_devScroll addSubview:c2];
    [self ykCardHeader:c2 title:@"运行状态" symbol:@"square.grid.2x2.fill" tint:YkPurple()];

    NSArray *tiles = @[ @[@"设备 IP", @"192.168.1.43", @"wifi", YkBlue(),
                          [UIColor colorWithRed:0.92 green:0.96 blue:1.0 alpha:1.0]],
                        @[@"越狱方式", @"隐根", @"lock.fill", YkRed(),
                          [UIColor colorWithRed:0.99 green:0.92 blue:0.92 alpha:1.0]],
                        @[@"系统分辨率", @"750×1334", @"iphone", YkTeal(),
                          [UIColor colorWithRed:0.94 green:0.98 blue:0.99 alpha:1.0]],
                        @[@"应用版本", @"3.9.5", @"app.badge", YkOrange(),
                          [UIColor colorWithRed:1.0 green:0.97 blue:0.93 alpha:1.0]] ];
    for (NSInteger i = 0; i < 4; i++) {
        NSArray *t = tiles[i];
        CGFloat tx = INNER_PAD + (i % 2) * 154;
        CGFloat ty = 72 + (i / 2) * 92;
        UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(tx, ty, 142, 80)];
        tile.backgroundColor = t[4];
        tile.layer.cornerRadius = 12.0;
        [c2 addSubview:tile];
        [tile addSubview:[self ykIconBox:CGRectMake(12, 10, 32, 32) symbol:t[2] tint:t[3] glyph:17]];
        UILabel *k = [self ykLabel:t[0] size:12 bold:NO color:YkSub()];
        k.frame = CGRectMake(52, 15, 86, 16); [tile addSubview:k];
        UILabel *v = [self ykLabel:t[1] size:19 bold:YES color:YkMain()];
        v.frame = CGRectMake(14, 42, 124, 24); v.adjustsFontSizeToFitWidth = YES;
        v.minimumScaleFactor = 0.7;
        [tile addSubview:v];
    }

    // ---------- 卡片三：设备信息 ----------
    UIView *c3 = [self ykCard:CGRectMake(CARD_X, 648, CARD_W, 266)];
    [_devScroll addSubview:c3];
    [self ykCardHeader:c3 title:@"设备信息" symbol:@"gearshape.fill" tint:YkPurple()];

    UILabel *n1 = [self ykLabel:@"设备名称" size:12 bold:NO color:YkSub()];
    n1.frame = CGRectMake(INNER_PAD, 72, 200, 17); [c3 addSubview:n1];
    UILabel *nv = [self ykLabel:@"iPhone" size:19 bold:YES color:YkMain()];
    nv.frame = CGRectMake(INNER_PAD + 14, 97 + 14, 219, 24); [c3 addSubview:nv];
    UIButton *edit = [UIButton buttonWithType:UIButtonTypeSystem];
    edit.frame = CGRectMake(CARD_W - INNER_PAD - 40 - 12, 97 + 8, 40, 40);
    [edit setImage:[UIImage systemImageNamed:@"pencil"] forState:UIControlStateNormal];
    edit.tintColor = YkMain(); [c3 addSubview:edit];

    UILabel *n2 = [self ykLabel:@"设备 ID" size:12 bold:NO color:YkSub()];
    n2.frame = CGRectMake(INNER_PAD, 165, 200, 17); [c3 addSubview:n2];
    UILabel *nv2 = [self ykLabel:@"1983fed10d4062e506291b023e92c27cc6e470bf" size:13 bold:NO color:YkMain()];
    nv2.frame = CGRectMake(INNER_PAD + 14, 190 + 6, 219, 40);
    nv2.numberOfLines = 2; nv2.lineBreakMode = NSLineBreakByCharWrapping;
    [c3 addSubview:nv2];
    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    copy.frame = CGRectMake(CARD_W - INNER_PAD - 40 - 12, 190 + 6, 40, 40);
    [copy setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    copy.tintColor = YkMain(); [c3 addSubview:copy];

    // ---------- 卡片四：备用用户空间 ----------
    UIView *c4 = [self ykCard:CGRectMake(CARD_X, 934, CARD_W, 176)];
    [_devScroll addSubview:c4];
    [self ykCardHeader:c4 title:@"备用用户空间" symbol:@"arrow.clockwise" tint:YkBlue()];

    UIView *row4 = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, 72, CARD_W - INNER_PAD * 2, 84)];
    row4.backgroundColor = [UIColor colorWithWhite:0.975 alpha:1.0];
    row4.layer.cornerRadius = 12.0;
    [c4 addSubview:row4];
    [row4 addSubview:[self ykIconBox:CGRectMake(14, 21, 42, 42) symbol:@"externaldrive.fill" tint:YkBlue() glyph:22]];
    UILabel *t41 = [self ykLabel:@"显示" size:17 bold:YES color:YkMain()];
    t41.frame = CGRectMake(68, 14, 180, 22); [row4 addSubview:t41];
    UILabel *t42 = [self ykLabel:@"垂直布局备用空间，配合当前 PC 连接，出现异常时使用"
                            size:12 bold:NO color:YkSub()];
    t42.frame = CGRectMake(68, 38, 190, 34); t42.numberOfLines = 2; [row4 addSubview:t42];
    UIImageView *chev = [[UIImageView alloc] initWithFrame:CGRectMake(row4.bounds.size.width - 26, 36, 12, 12)];
    chev.image = [UIImage systemImageNamed:@"chevron.right"];
    chev.tintColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    [row4 addSubview:chev];

    _devScroll.contentSize = CGSizeMake(_W, 1158);
}

#pragma mark - 脚本页（文案取自原版 __cfstring）

- (void)ykScriptPage {
    _scriptScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, NAV_H, _W, _H - NAV_H)];
    _scriptScroll.contentInset = UIEdgeInsetsMake(0, 0, 88, 0);
    _scriptScroll.hidden = YES;
    [self addSubview:_scriptScroll];

    UIView *c1 = [self ykCard:CGRectMake(CARD_X, 20, CARD_W, 250)];
    [_scriptScroll addSubview:c1];
    [self ykCardHeader:c1 title:@"脚本控制台" symbol:@"terminal" tint:YkBlue()];

    NSArray *kv = @[ @[@"HTTP 服务", @"检测中", @"当前状态", @"已开启"],
                     @[@"本地端口", @"65322", @"脚本数量", @"0"] ];
    for (NSInteger i = 0; i < 2; i++) {
        NSArray *r = kv[i]; CGFloat y = 72 + i * 60;
        UIView *tileA = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, y, 142, 52)];
        UIView *tileB = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD + 154, y, 142, 52)];
        for (UIView *t in @[tileA, tileB]) {
            t.backgroundColor = [YkBlue() colorWithAlphaComponent:0.06];
            t.layer.cornerRadius = 10.0;
            [c1 addSubview:t];
        }
        UILabel *k1 = [self ykLabel:r[0] size:12 bold:NO color:YkSub()];
        k1.frame = CGRectMake(10, 6, 120, 16); [tileA addSubview:k1];
        UILabel *v1 = [self ykLabel:r[1] size:16 bold:YES color:YkMain()];
        v1.frame = CGRectMake(10, 24, 120, 20); [tileA addSubview:v1];
        UILabel *k2 = [self ykLabel:r[2] size:12 bold:NO color:YkSub()];
        k2.frame = CGRectMake(10, 6, 120, 16); [tileB addSubview:k2];
        UILabel *v2 = [self ykLabel:r[3] size:16 bold:YES color:YkMain()];
        v2.frame = CGRectMake(10, 24, 120, 20); [tileB addSubview:v2];
        if (i == 0) { _lblHttpStatus = v1; _lblState = v2; }
        else        { _lblPort = v1; _lblScriptCount = v2; }
    }
    UILabel *h1 = [self ykLabel:@"设备可通过互联网远程调试" size:12 bold:NO color:YkSub()];
    h1.frame = CGRectMake(INNER_PAD, 200, 300, 18); [c1 addSubview:h1];

    UIView *c2 = [self ykCard:CGRectMake(CARD_X, 290, CARD_W, 96)];
    [_scriptScroll addSubview:c2];
    UILabel *t2 = [self ykLabel:@"远程调试安全状态" size:15 bold:YES color:YkMain()];
    t2.frame = CGRectMake(INNER_PAD, 16, 220, 20); [c2 addSubview:t2];
    UILabel *s2 = [self ykLabel:@"公网远程调试已开启" size:12 bold:NO color:YkSub()];
    s2.frame = CGRectMake(INNER_PAD, 42, 300, 18); [c2 addSubview:s2];
    UILabel *s3 = [self ykLabel:@"未连接" size:12 bold:NO color:YkSub()];
    s3.frame = CGRectMake(INNER_PAD, 64, 120, 18); [c2 addSubview:s3];

    UIView *c3 = [self ykCard:CGRectMake(CARD_X, 406, CARD_W, 160)];
    [_scriptScroll addSubview:c3];
    UILabel *t3 = [self ykLabel:@"脚本列表" size:17 bold:YES color:YkMain()];
    t3.frame = CGRectMake(INNER_PAD, 16, 150, 22); [c3 addSubview:t3];

    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
    refresh.frame = CGRectMake(CARD_W - INNER_PAD - 72, 14, 72, 30);
    [refresh setTitle:@"刷新" forState:UIControlStateNormal];
    refresh.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    refresh.backgroundColor = [YkBlue() colorWithAlphaComponent:0.10];
    refresh.layer.cornerRadius = 9.0;
    [refresh setTitleColor:YkBlue() forState:UIControlStateNormal];
    [refresh addTarget:self action:@selector(ykReloadScripts) forControlEvents:UIControlEventTouchUpInside];
    [c3 addSubview:refresh];

    UILabel *empty = [self ykLabel:@"暂无订阅脚本" size:13 bold:NO color:YkSub()];
    empty.textAlignment = NSTextAlignmentCenter;
    empty.frame = CGRectMake(0, 96, CARD_W, 20);
    [c3 addSubview:empty];
    _lblScriptEmpty = empty;
    UILabel *hint = [self ykLabel:@"刷新脚本列表" size:12 bold:NO color:YkSub()];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.frame = CGRectMake(0, 120, CARD_W, 18);
    [c3 addSubview:hint];

    _scriptScroll.contentSize = CGSizeMake(_W, 600);
}

#pragma mark - 录制页（文案取自原版 __cfstring）

- (void)ykRecordPage {
    _recordScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, NAV_H, _W, _H - NAV_H)];
    _recordScroll.contentInset = UIEdgeInsetsMake(0, 0, 88, 0);
    _recordScroll.hidden = YES;
    [self addSubview:_recordScroll];

    UIView *c1 = [self ykCard:CGRectMake(CARD_X, 20, CARD_W, 140)];
    [_recordScroll addSubview:c1];
    [self ykCardHeader:c1 title:@"录制中心" symbol:@"record.circle" tint:YkRed()];

    UILabel *h1 = [self ykLabel:@"点下方按钮后，App 会退到桌面，只留下 44x44 红色录制小球。"
                            size:12 bold:NO color:YkSub()];
    h1.frame = CGRectMake(INNER_PAD, 64, CARD_W - INNER_PAD * 2 - 8, 34); h1.numberOfLines = 2;
    [c1 addSubview:h1];

    UIButton *start = [UIButton buttonWithType:UIButtonTypeSystem];
    start.frame = CGRectMake(CARD_W - INNER_PAD - 100, 96, 100, 32);
    [start setTitle:@"开始录制" forState:UIControlStateNormal];
    start.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    start.backgroundColor = YkBlue();
    start.layer.cornerRadius = 10.0;
    [start setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [c1 addSubview:start];

    UIView *c2 = [self ykCard:CGRectMake(CARD_X, 180, CARD_W, 160)];
    [_recordScroll addSubview:c2];
    UILabel *t2 = [self ykLabel:@"我的录制" size:17 bold:YES color:YkMain()];
    t2.frame = CGRectMake(INNER_PAD, 16, 150, 22); [c2 addSubview:t2];
    UILabel *empty = [self ykLabel:@"还没有录制脚本" size:13 bold:NO color:YkSub()];
    empty.textAlignment = NSTextAlignmentCenter;
    empty.frame = CGRectMake(0, 84, CARD_W, 20);
    [c2 addSubview:empty];
    UILabel *h2 = [self ykLabel:@"录制向导" size:12 bold:NO color:YkSub()];
    h2.textAlignment = NSTextAlignmentCenter;
    h2.frame = CGRectMake(0, 110, CARD_W, 18);
    [c2 addSubview:h2];

    UIView *c3 = [self ykCard:CGRectMake(CARD_X, 360, CARD_W, 96)];
    [_recordScroll addSubview:c3];
    UILabel *t3 = [self ykLabel:@"选择回放次数" size:15 bold:YES color:YkMain()];
    t3.frame = CGRectMake(INNER_PAD, 16, 200, 20); [c3 addSubview:t3];
    NSArray *opts = @[@"回放 1 次", @"回放 3 次", @"回放 10 次"];
    for (NSInteger i = 0; i < 3; i++) {
        UILabel *o = [self ykLabel:opts[i] size:12 bold:NO color:[UIColor whiteColor]];
        o.textAlignment = NSTextAlignmentCenter;
        o.backgroundColor = [YkBlue() colorWithAlphaComponent:0.85];
        o.layer.cornerRadius = 8.0; o.clipsToBounds = YES;
        o.frame = CGRectMake(INNER_PAD + i * 100, 52, 90, 28);
        [c3 addSubview:o];
    }

    _recordScroll.contentSize = CGSizeMake(_W, 500);
}

#pragma mark - 底部导航（悬浮胶囊）

- (void)ykBottom {
    _bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, _H - 68, _W, 68)];
    _bottomBar.backgroundColor = [UIColor clearColor];
    [self addSubview:_bottomBar];

    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(22, 0, _W - 44, 60)];
    pill.backgroundColor = [UIColor colorWithWhite:0.99 alpha:0.96];
    pill.layer.cornerRadius = 30.0;
    pill.layer.shadowColor = [UIColor blackColor].CGColor;
    pill.layer.shadowOpacity = 0.06;
    pill.layer.shadowRadius = 10.0;
    pill.layer.shadowOffset = CGSizeMake(0, 2);
    [_bottomBar addSubview:pill];

    NSArray *names = @[@"设备", @"脚本", @"录制"];
    NSArray *icons = @[@"iphone", @"terminal", @"record.circle"];
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(i * (pill.bounds.size.width / 3.0), 4, pill.bounds.size.width / 3.0, 52);
        b.tag = i;
        [b setTitle:names[i] forState:UIControlStateNormal];
        [b setImage:[UIImage systemImageNamed:icons[i]] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12];
        b.tintColor = (i == 0) ? YkTint() : YkSub();
        b.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 0);
        [b setTitleEdgeInsets:UIEdgeInsetsMake(26, -22, 0, 0)];
        [b setImageEdgeInsets:UIEdgeInsetsMake(-14, 0, 0, 0)];
        [b addTarget:self action:@selector(ykTab:) forControlEvents:UIControlEventTouchUpInside];
        [pill addSubview:b];
    }
}

- (void)ykHTTP:(NSString *)path done:(void (^)(NSDictionary *))done {
    NSURL *u = [NSURL URLWithString:[@"http://127.0.0.1:65324" stringByAppendingString:path]];
    [[[NSURLSession sharedSession] dataTaskWithURL:u
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(j); });
    }] resume];
}

- (void)ykReloadScripts {
    __weak typeof(self) ws = self;
    [self ykHTTP:@"/health" done:^(NSDictionary *j) {
        __strong typeof(ws) sf = ws; if (!sf) return;
        BOOL ready = [j[@"value"][@"ready"] boolValue];
        sf.lblHttpStatus.text = ready ? @"正常" : @"异常";
        sf.lblHttpStatus.textColor = ready ? YkTint() : [UIColor systemRedColor];
        sf.lblPort.text = [NSString stringWithFormat:@"%@", j[@"value"][@"port"] ?: @"—"];
        sf.lblState.text = ready ? @"已开启" : @"已关闭";
    }];
    [self ykHTTP:@"/executor/scripts" done:^(NSDictionary *j) {
        __strong typeof(ws) sf = ws; if (!sf) return;
        NSArray *list = j[@"value"][@"scripts"];
        sf.lblScriptCount.text = [NSString stringWithFormat:@"%lu", (unsigned long)list.count];
        sf.lblScriptEmpty.text = list.count ? [NSString stringWithFormat:@"共 %lu 个脚本", (unsigned long)list.count]
                                            : @"暂无订阅脚本";
    }];
}

- (void)ykShowPageObj:(id)o {
    NSInteger i = [o isKindOfClass:[NSNumber class]] ? [o integerValue] : [o respondsToSelector:@selector(integerValue)] ? [o integerValue] : 0;
    _devScroll.hidden    = (i != 0);
    _scriptScroll.hidden = (i != 1);
    _recordScroll.hidden = (i != 2);
    if (i == 1) [self ykReloadScripts];
    for (UIView *v in _bottomBar.subviews) {
        for (UIView *b in v.subviews) {
            if ([b isKindOfClass:[UIButton class]]) {
                UIButton *btn = (UIButton *)b;
                btn.tintColor = (btn.tag == i) ? YkTint() : YkSub();
            }
        }
    }
}

- (void)ykTab:(UIButton *)sender {
    for (UIView *v in _bottomBar.subviews) {
        for (UIView *b in v.subviews) {
            if ([b isKindOfClass:[UIButton class]]) {
                UIButton *btn = (UIButton *)b;
                btn.tintColor = (btn.tag == sender.tag) ? YkTint() : YkSub();
            }
        }
    }
    _devScroll.hidden    = (sender.tag != 0);
    _scriptScroll.hidden = (sender.tag != 1);
    _recordScroll.hidden = (sender.tag != 2);
}

@end
