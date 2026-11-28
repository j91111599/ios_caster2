//  YKMainView —— 三页复刻（纯 frame 布局）
//  几何/配色来源：设备实测 /element/tree + 截图像素采样（750x1334 @2x）
//    导航条 0..64pt（状态栏 20 + 44）；卡片 x=20 宽 335，内边距 20
//    蓝色 #24A1F1、页面底色 #F6F5FA；行高 68、磁贴 142x80、磁贴间距 12
//    磁贴底色：蓝 #EBF5FF / 红 #FCEBEB / 青 #EFF9FB / 橙 #FFF7EC
//    脚本页：绿 #EAF6EE / 紫 #EFEDFB / 橙 #FEF3E6 / 品红 #F7EDFB
//    录制页步骤：粉 #FDEEF0 / 蓝 #EAF2FE / 绿 #EAF7EE / 黄 #FEF6E6
#import <UIKit/UIKit.h>

static UIColor *YkBlue(void)    { return [UIColor colorWithRed:0.141 green:0.631 blue:0.945 alpha:1.0]; }
static UIColor *YkPageBg(void)  { return [UIColor colorWithRed:0.965 green:0.961 blue:0.980 alpha:1.0]; }
static UIColor *YkSub(void)     { return [UIColor colorWithRed:0.541 green:0.541 blue:0.561 alpha:1.0]; }
static UIColor *YkMain(void)    { return [UIColor colorWithWhite:0.08 alpha:1.0]; }
static UIColor *YkTint(void)    { return YkBlue(); }
static UIColor *YkPurple(void)  { return [UIColor colorWithRed:0.44 green:0.36 blue:0.86 alpha:1.0]; }
static UIColor *YkRed(void)     { return [UIColor colorWithRed:0.93 green:0.35 blue:0.33 alpha:1.0]; }
static UIColor *YkTeal(void)    { return [UIColor colorWithRed:0.31 green:0.71 blue:0.78 alpha:1.0]; }
static UIColor *YkOrange(void)  { return [UIColor colorWithRed:0.96 green:0.63 blue:0.22 alpha:1.0]; }
static UIColor *YkGreen(void)   { return [UIColor colorWithRed:0.20 green:0.72 blue:0.42 alpha:1.0]; }
static UIColor *YkMagenta(void) { return [UIColor colorWithRed:0.72 green:0.35 blue:0.85 alpha:1.0]; }

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
- (UIView *)ykTileAt:(CGRect)r key:(NSString *)k value:(NSString *)v symbol:(NSString *)s
                tint:(UIColor *)tint bg:(UIColor *)bg;
- (void)ykTab:(UIButton *)sender;
- (void)ykSelectTab:(NSInteger)idx;
- (void)ykShowPageObj:(id)o;
- (void)ykReloadScripts;
@end

@implementation YKMainView {
    CGFloat _W, _H;
    NSMutableArray *_tabIcons;
    NSMutableArray *_tabLabels;
    UIView *_tabCapsule;
    UIImageView *_navLeftIcon;
    UIButton *_navRightBtn;
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
        [self ykSelectTab:0];
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

- (UIView *)ykCardHeader:(UIView *)card title:(NSString *)t symbol:(NSString *)n tint:(UIColor *)tint {
    [card addSubview:[self ykIconBox:CGRectMake(INNER_PAD, 20, 36, 36) symbol:n tint:tint glyph:20]];
    UILabel *lbl = [self ykLabel:t size:17 bold:YES color:YkMain()];
    lbl.frame = CGRectMake(66, 27, 200, 22);
    [card addSubview:lbl];
    return lbl;
}

- (UIView *)ykTileAt:(CGRect)r key:(NSString *)k value:(NSString *)v symbol:(NSString *)s
                tint:(UIColor *)tint bg:(UIColor *)bg {
    UIView *tile = [[UIView alloc] initWithFrame:r];
    tile.backgroundColor = bg;
    tile.layer.cornerRadius = 12.0;
    [tile addSubview:[self ykIconBox:CGRectMake(12, 10, 32, 32) symbol:s tint:tint glyph:17]];
    UILabel *kl = [self ykLabel:k size:12 bold:NO color:YkSub()];
    kl.frame = CGRectMake(52, 15, 86, 16); [tile addSubview:kl];
    UILabel *vl = [self ykLabel:v size:19 bold:YES color:YkMain()];
    vl.frame = CGRectMake(14, 42, 124, 24);
    vl.adjustsFontSizeToFitWidth = YES; vl.minimumScaleFactor = 0.7;
    [tile addSubview:vl];
    return tile;
}

#pragma mark - 顶部导航（左图标 / 右按钮随页切换）

- (void)ykHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _W, NAV_H)];
    header.backgroundColor = YkBlue();
    [self addSubview:header];

    UIView *left = [[UIView alloc] initWithFrame:CGRectMake(4, 20, 44, 44)];
    [header addSubview:left];
    _navLeftIcon = [[UIImageView alloc] initWithFrame:CGRectMake(8, 8, 28, 28)];
    _navLeftIcon.contentMode = UIViewContentModeScaleAspectFit;
    _navLeftIcon.tintColor = [UIColor whiteColor];
    [left addSubview:_navLeftIcon];

    UILabel *title = [self ykLabel:@"远控 Pro" size:20 bold:YES color:[UIColor whiteColor]];
    title.textAlignment = NSTextAlignmentCenter;
    title.tag = 9001;
    title.frame = CGRectMake(0, 30, _W, 26);
    [header addSubview:title];

    _navRightBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _navRightBtn.frame = CGRectMake(_W - 8 - 96, 27, 96, 30);
    _navRightBtn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.22];
    _navRightBtn.layer.cornerRadius = 15.0;
    _navRightBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [_navRightBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _navRightBtn.tintColor = [UIColor whiteColor];
    [header addSubview:_navRightBtn];
}

- (UILabel *)ykNavTitle {
    for (UIView *v in self.subviews) {
        for (UIView *c in v.subviews) {
            if ([c isKindOfClass:[UILabel class]] && c.tag == 9001) return (UILabel *)c;
        }
    }
    return nil;
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
    [self ykCardHeader:c1 title:@"连接设备" symbol:@"antenna.radiowaves.left.and.right" tint:YkBlue()];

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
        BOOL isDevice = [r[3] intValue] < 0;
        CGFloat y = 72 + i * 80;
        CGFloat h = isDevice ? 72 : 68;
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, y, CARD_W - INNER_PAD * 2, h)];
        row.backgroundColor = on ? [YkBlue() colorWithAlphaComponent:0.06] : [UIColor whiteColor];
        row.layer.cornerRadius = 12.0;
        row.layer.borderWidth = 1.0;
        row.layer.borderColor = (on ? [YkBlue() colorWithAlphaComponent:0.18]
                                    : [UIColor colorWithWhite:0.93 alpha:1.0]).CGColor;
        [c1 addSubview:row];

        CGFloat iconSize = isDevice ? 42 : 44;
        CGFloat iconY = isDevice ? 15 : 12;
        UIColor *tint = on ? YkBlue() : [UIColor colorWithWhite:0.62 alpha:1.0];
        [row addSubview:[self ykIconBox:CGRectMake(14, iconY, iconSize, iconSize)
                                 symbol:r[2] tint:tint glyph:24]];

        UILabel *tt = [self ykLabel:r[0] size:17 bold:YES color:YkMain()];
        tt.frame = CGRectMake(68, isDevice ? 17 : 15, 160, 22);
        [row addSubview:tt];
        UILabel *ss = [self ykLabel:r[1] size:12 bold:NO color:YkSub()];
        ss.frame = CGRectMake(68, isDevice ? 40 : 38, 152, 16);
        ss.adjustsFontSizeToFitWidth = YES;
        ss.minimumScaleFactor = 0.75;
        [row addSubview:ss];

        if (!isDevice) {
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(row.bounds.size.width - 51 - 12, 18, 51, 31)];
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
        CGRect fr = CGRectMake(INNER_PAD + (i % 2) * 154, 72 + (i / 2) * 92, 142, 80);
        [c2 addSubview:[self ykTileAt:fr key:t[0] value:t[1] symbol:t[2] tint:t[3] bg:t[4]]];
    }

    // ---------- 卡片三：设备信息 ----------
    UIView *c3 = [self ykCard:CGRectMake(CARD_X, 648, CARD_W, 266)];
    [_devScroll addSubview:c3];
    [self ykCardHeader:c3 title:@"设备信息" symbol:@"gearshape.fill" tint:YkPurple()];

    UILabel *n1 = [self ykLabel:@"设备名称" size:12 bold:NO color:YkSub()];
    n1.frame = CGRectMake(INNER_PAD, 72, 200, 17); [c3 addSubview:n1];
    UILabel *nv = [self ykLabel:@"iPhone" size:19 bold:YES color:YkMain()];
    nv.frame = CGRectMake(INNER_PAD + 14, 111, 219, 24); [c3 addSubview:nv];
    UIButton *edit = [UIButton buttonWithType:UIButtonTypeSystem];
    edit.frame = CGRectMake(CARD_W - INNER_PAD - 52, 105, 40, 40);
    [edit setImage:[UIImage systemImageNamed:@"pencil"] forState:UIControlStateNormal];
    edit.tintColor = YkMain(); [c3 addSubview:edit];

    UILabel *n2 = [self ykLabel:@"设备 ID" size:12 bold:NO color:YkSub()];
    n2.frame = CGRectMake(INNER_PAD, 165, 200, 17); [c3 addSubview:n2];
    UILabel *nv2 = [self ykLabel:@"1983fed10d4062e506291b023e92c27cc6e470bf" size:13 bold:NO color:YkMain()];
    nv2.frame = CGRectMake(INNER_PAD + 14, 196, 219, 40);
    nv2.numberOfLines = 2; nv2.lineBreakMode = NSLineBreakByCharWrapping;
    [c3 addSubview:nv2];
    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    copy.frame = CGRectMake(CARD_W - INNER_PAD - 52, 196, 40, 40);
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

#pragma mark - 脚本页

- (void)ykScriptPage {
    _scriptScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, NAV_H, _W, _H - NAV_H)];
    _scriptScroll.contentInset = UIEdgeInsetsMake(0, 0, 88, 0);
    _scriptScroll.hidden = YES;
    [self addSubview:_scriptScroll];

    UIView *c1 = [self ykCard:CGRectMake(CARD_X, 20, CARD_W, 264)];
    [_scriptScroll addSubview:c1];
    [self ykCardHeader:c1 title:@"HTTP 服务" symbol:@"server.rack" tint:YkBlue()];

    NSArray *tiles = @[ @[@"HTTP 服务", @"已开启", @"bolt.fill", YkGreen(),
                          [UIColor colorWithRed:0.92 green:0.97 blue:0.93 alpha:1.0]],
                        @[@"本地端口", @"65322", @"number", YkPurple(),
                          [UIColor colorWithRed:0.94 green:0.93 blue:0.99 alpha:1.0]],
                        @[@"当前状态", @"就绪", @"waveform.path.ecg", YkOrange(),
                          [UIColor colorWithRed:1.0 green:0.95 blue:0.90 alpha:1.0]],
                        @[@"脚本数量", @"-", @"doc.text.fill", YkMagenta(),
                          [UIColor colorWithRed:0.97 green:0.93 blue:0.99 alpha:1.0]] ];
    for (NSInteger i = 0; i < 4; i++) {
        NSArray *t = tiles[i];
        CGRect fr = CGRectMake(INNER_PAD + (i % 2) * 154, 72 + (i / 2) * 92, 142, 80);
        UIView *tile = [self ykTileAt:fr key:t[0] value:t[1] symbol:t[2] tint:t[3] bg:t[4]];
        [c1 addSubview:tile];
        UILabel *v = (UILabel *)tile.subviews[2];
        if (i == 0) _lblHttpStatus = v;
        if (i == 1) _lblPort = v;
        if (i == 2) _lblState = v;
        if (i == 3) _lblScriptCount = v;
    }

    UIView *c2 = [self ykCard:CGRectMake(CARD_X, 304, CARD_W, 146)];
    [_scriptScroll addSubview:c2];
    [self ykCardHeader:c2 title:@"脚本列表" symbol:@"list.bullet.rectangle" tint:YkMagenta()];

    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
    refresh.frame = CGRectMake(CARD_W - INNER_PAD - 36, 20, 36, 36);
    refresh.backgroundColor = [YkMagenta() colorWithAlphaComponent:0.12];
    refresh.layer.cornerRadius = 18.0;
    [refresh setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
    refresh.tintColor = YkMagenta();
    [refresh addTarget:self action:@selector(ykReloadScripts) forControlEvents:UIControlEventTouchUpInside];
    [c2 addSubview:refresh];

    UIView *emptyBox = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, 72, CARD_W - INNER_PAD * 2, 54)];
    emptyBox.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    emptyBox.layer.cornerRadius = 10.0;
    [c2 addSubview:emptyBox];
    UILabel *empty = [self ykLabel:@"暂无订阅脚本" size:13 bold:NO color:YkSub()];
    empty.textAlignment = NSTextAlignmentCenter;
    empty.frame = CGRectMake(0, 18, emptyBox.bounds.size.width, 18);
    [emptyBox addSubview:empty];
    _lblScriptEmpty = empty;

    _scriptScroll.contentSize = CGSizeMake(_W, 470);
}

#pragma mark - 录制页

- (void)ykRecordPage {
    _recordScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, NAV_H, _W, _H - NAV_H)];
    _recordScroll.contentInset = UIEdgeInsetsMake(0, 0, 88, 0);
    _recordScroll.hidden = YES;
    [self addSubview:_recordScroll];

    UIView *card = [self ykCard:CGRectMake(CARD_X, 20, CARD_W, 554)];
    [_recordScroll addSubview:card];
    [self ykCardHeader:card title:@"录制向导" symbol:@"record.circle" tint:YkRed()];

    UILabel *sub = [self ykLabel:@"录制流程怎么用" size:17 bold:YES color:YkMain()];
    sub.frame = CGRectMake(INNER_PAD, 72, 295, 27);
    [card addSubview:sub];

    NSArray *steps = @[ @[@"1. 打开小球，回到桌面", @"点下方按钮后，App 会退到桌面，只留下\n44x44 红色录制小球。",
                          @"record.circle", YkRed(),
                          [UIColor colorWithRed:0.99 green:0.93 blue:0.94 alpha:1.0]],
                        @[@"2. 拖动或点开小球", @"小球可拖动，轻点可展开；操作小球和菜单不\n会写进录制。",
                          @"hand.point.up.left.fill", YkBlue(),
                          [UIColor colorWithRed:0.92 green:0.95 blue:1.0 alpha:1.0]],
                        @[@"3. 开始、暂停、继续", @"点「开始」或按音量 + 后先倒计时；录制中可\n暂停，再点继续接着录。",
                          @"play.fill", YkGreen(),
                          [UIColor colorWithRed:0.92 green:0.97 blue:0.94 alpha:1.0]],
                        @[@"4. 完成并命名保存", @"点「完成」或按音量 - 会回到 App 命名；留\n空就按当前时间保存。",
                          @"checkmark.circle.fill", YkOrange(),
                          [UIColor colorWithRed:1.0 green:0.96 blue:0.90 alpha:1.0]] ];
    for (NSInteger i = 0; i < 4; i++) {
        NSArray *s = steps[i];
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, 108 + i * 71,
                                                              CARD_W - INNER_PAD * 2, 62)];
        row.backgroundColor = s[4];
        row.layer.cornerRadius = 12.0;
        [card addSubview:row];
        [row addSubview:[self ykIconBox:CGRectMake(10, 13, 36, 36) symbol:s[2] tint:s[3] glyph:18]];
        UILabel *t = [self ykLabel:s[0] size:15 bold:YES color:YkMain()];
        t.frame = CGRectMake(56, 8, 227, 19); [row addSubview:t];
        UILabel *d = [self ykLabel:s[1] size:12 bold:NO color:YkSub()];
        d.frame = CGRectMake(56, 27, 227, 30); d.numberOfLines = 2; [row addSubview:d];
    }

    UIView *sc = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, 392, CARD_W - INNER_PAD * 2, 70)];
    sc.backgroundColor = [UIColor colorWithRed:0.99 green:0.94 blue:0.95 alpha:1.0];
    sc.layer.cornerRadius = 12.0;
    [card addSubview:sc];
    UIImageView *vol = [[UIImageView alloc] initWithFrame:CGRectMake(12, 12, 18, 15)];
    vol.image = [UIImage systemImageNamed:@"speaker.wave.2.fill"];
    vol.tintColor = YkRed();
    vol.contentMode = UIViewContentModeScaleAspectFit;
    [sc addSubview:vol];
    UILabel *vl = [self ykLabel:@"实体按键快捷操作" size:13 bold:YES color:YkMain()];
    vl.frame = CGRectMake(38, 10, 200, 18); [sc addSubview:vl];

    NSArray *pills = @[ @[@"音量 +", @"开始录制", YkGreen()], @[@"音量 -", @"完成并命名", YkRed()] ];
    for (NSInteger i = 0; i < 2; i++) {
        NSArray *p = pills[i];
        UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(12 + i * 140, 34, 132, 28)];
        pill.backgroundColor = [UIColor whiteColor];
        pill.layer.cornerRadius = 14.0;
        [sc addSubview:pill];
        UILabel *a = [self ykLabel:p[0] size:12 bold:YES color:p[2]];
        a.frame = CGRectMake(10, 6, 52, 16); [pill addSubview:a];
        UILabel *b = [self ykLabel:p[1] size:11 bold:NO color:YkMain()];
        b.frame = CGRectMake(66, 6, 60, 16); [pill addSubview:b];
    }

    UIButton *rec = [UIButton buttonWithType:UIButtonTypeSystem];
    rec.frame = CGRectMake(INNER_PAD, 478, CARD_W - INNER_PAD * 2, 56);
    rec.backgroundColor = [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0];
    rec.layer.cornerRadius = 28.0;
    [rec setTitle:@"  打开录制小球" forState:UIControlStateNormal];
    [rec setImage:[UIImage systemImageNamed:@"record.circle"] forState:UIControlStateNormal];
    rec.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [rec setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    rec.tintColor = [UIColor whiteColor];
    [card addSubview:rec];

    _recordScroll.contentSize = CGSizeMake(_W, 594);
}

#pragma mark - 底部导航（悬浮胶囊 + 选中态高亮）

- (void)ykBottom {
    _bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, _H - 68, _W, 68)];
    _bottomBar.backgroundColor = [UIColor clearColor];
    [self addSubview:_bottomBar];

    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(22, 0, _W - 44, 60)];
    pill.backgroundColor = [UIColor whiteColor];
    pill.layer.cornerRadius = 30.0;
    pill.layer.shadowColor = [UIColor blackColor].CGColor;
    pill.layer.shadowOpacity = 0.06;
    pill.layer.shadowRadius = 10.0;
    pill.layer.shadowOffset = CGSizeMake(0, 2);
    [_bottomBar addSubview:pill];

    _tabCapsule = [[UIView alloc] initWithFrame:CGRectMake(30, 5, 94, 50)];
    _tabCapsule.backgroundColor = [YkBlue() colorWithAlphaComponent:0.13];
    _tabCapsule.layer.cornerRadius = 25.0;
    [pill addSubview:_tabCapsule];

    _tabIcons = [NSMutableArray array];
    _tabLabels = [NSMutableArray array];

    NSArray *names = @[@"设备", @"脚本", @"录制"];
    NSArray *icons = @[@"iphone", @"terminal", @"record.circle"];
    CGFloat iw = (_W - 44) / 3.0;
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
        hit.frame = CGRectMake(i * iw, 0, iw, 60);
        hit.tag = i;
        [hit addTarget:self action:@selector(ykTab:) forControlEvents:UIControlEventTouchUpInside];
        [pill addSubview:hit];

        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(i * iw, 7, iw, 28)];
        iv.image = [UIImage systemImageNamed:icons[i]];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.userInteractionEnabled = NO;
        [pill addSubview:iv];
        [_tabIcons addObject:iv];

        UILabel *l = [self ykLabel:names[i] size:12 bold:NO color:YkSub()];
        l.textAlignment = NSTextAlignmentCenter;
        l.frame = CGRectMake(i * iw, 36, iw, 18);
        l.userInteractionEnabled = NO;
        [pill addSubview:l];
        [_tabLabels addObject:l];
    }
}

- (void)ykSelectTab:(NSInteger)idx {
    for (NSInteger i = 0; i < _tabIcons.count; i++) {
        UIColor *c = (i == idx) ? YkTint() : YkSub();
        ((UIImageView *)_tabIcons[i]).tintColor = c;
        ((UILabel *)_tabLabels[i]).textColor = c;
    }
    CGFloat iw = (_W - 44) / 3.0;
    _tabCapsule.frame = CGRectMake(idx * iw + (iw - 94) / 2.0, 5, 94, 50);

    UILabel *title = [self ykNavTitle];
    _navLeftIcon.image = nil;
    _navRightBtn.hidden = YES;
    [_navRightBtn setTitle:@"" forState:UIControlStateNormal];

    if (idx == 0) {
        title.text = @"远控 Pro";
        _navLeftIcon.image = [UIImage systemImageNamed:@"house.fill"];
    } else if (idx == 1) {
        title.text = @"脚本控制台";
        _navLeftIcon.image = [UIImage systemImageNamed:@"gearshape.fill"];
        _navRightBtn.hidden = NO;
        [_navRightBtn setTitle:@"＋ 添加脚本" forState:UIControlStateNormal];
    } else {
        title.text = @"录制中心";
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
        sf.lblHttpStatus.text = ready ? @"已开启" : @"已关闭";
        sf.lblHttpStatus.textColor = ready ? YkGreen() : [UIColor systemRedColor];
        sf.lblState.text = ready ? @"就绪" : @"异常";
        sf.lblPort.text = [NSString stringWithFormat:@"%@", j[@"value"][@"port"] ?: @"—"];
    }];
    [self ykHTTP:@"/executor/scripts" done:^(NSDictionary *j) {
        __strong typeof(ws) sf = ws; if (!sf) return;
        NSArray *list = j[@"value"][@"scripts"];
        sf.lblScriptCount.text = list.count ? [NSString stringWithFormat:@"%lu", (unsigned long)list.count] : @"-";
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
    [self ykSelectTab:i];
}

- (void)ykTab:(UIButton *)sender {
    _devScroll.hidden    = (sender.tag != 0);
    _scriptScroll.hidden = (sender.tag != 1);
    _recordScroll.hidden = (sender.tag != 2);
    if (sender.tag == 1) [self ykReloadScripts];
    [self ykSelectTab:sender.tag];
}

@end
