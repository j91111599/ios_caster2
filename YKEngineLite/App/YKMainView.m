//  YKMainView —— 三页复刻（纯 frame 布局）
//  几何/配色来源：设备实测 /element/tree + 截图像素采样（750x1334 @2x）
//    导航条 0..64pt（状态栏 20 + 44）；卡片 x=20 宽 335，内边距 20
//    蓝色 #24A1F1、页面底色 #F6F5FA；行高 68、磁贴 142x80、磁贴间距 12
//    磁贴底色：蓝 #EBF5FF / 红 #FCEBEB / 青 #EFF9FB / 橙 #FFF7EC
//    脚本页：绿 #EAF6EE / 紫 #EFEDFB / 橙 #FEF3E6 / 品红 #F7EDFB
//    录制页步骤：粉 #FDEEF0 / 蓝 #EAF2FE / 绿 #EAF7EE / 黄 #FEF6E6
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>

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

#define YK_DEF_NAME     @"yk.deviceName"
#define YK_DEF_SERVICE  @"yk.serviceOn"
#define YK_DEF_WAN      @"yk.wanOn"
#define YK_DEF_SCRIPTS  @"yk.scripts"
#define YK_DEF_PEER     @"yk.peerDevice"

extern void YKAlert(UIViewController *host, NSString *title, NSString *message,
                    NSArray<NSString *> *buttons, void (^onIndex)(NSInteger idx));
extern void YKAlertRename(UIViewController *host, NSString *current, void (^onSave)(NSString *name));
extern void YKAlertRestart(UIViewController *host, void (^onConfirm)(void));
extern BOOL YKRequestRestartUserspace(void);
extern UIViewController *YKPresentScan(UIViewController *host, BOOL scriptMode,
                                       NSString *title, void (^onCode)(NSString *code));
extern void YKSetServiceEnabled(BOOL on);
extern NSString *YKEnginePort(void);

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
- (UIViewController *)ykHost;
- (void)ykToggleService:(UISwitch *)sw;
- (void)ykToggleWAN:(UISwitch *)sw;
- (void)ykRename;
- (void)ykCopyID;
- (void)ykScanConnect;
- (void)ykHandleConnectCode:(NSString *)code;
- (void)ykRebuildDevicePage;
- (void)ykAddScript;
- (void)ykSubscribeScript:(NSString *)code;
- (NSString *)ykHashOf:(NSString *)s;
- (void)ykRestartUserspace;
- (void)ykOpenRecordBall;
- (void)ykRefreshRecordList;
@end

@implementation YKMainView {
    CGFloat _W, _H;
    NSMutableArray *_tabIcons;
    NSMutableArray *_tabLabels;
    UIView *_tabCapsule;
    UIImageView *_navLeftIcon;
    UIButton *_navRightBtn;
    UISwitch *_svcSwitch;
    UIView *_svcRow;
    UIView *_wanRow;
    UISwitch *_wanSwitch;
    UILabel *_lblDeviceName;
    UILabel *_lblDeviceID;
    UIView *_recordListBox;
    UIView *_scriptListBox;
    UIView *_ballView;
    UILabel *_ballLabel;
    BOOL _ballRecording;
    NSMutableArray *_ballSteps;
    NSTimeInterval _ballStartAt;
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
    kl.frame = CGRectMake(52, 17, 86, 16); [tile addSubview:kl];
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
    [_navRightBtn addTarget:self action:@selector(ykAddScript)
           forControlEvents:UIControlEventTouchUpInside];
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
    [scan addTarget:self action:@selector(ykScanConnect)
  forControlEvents:UIControlEventTouchUpInside];
    [c1 addSubview:scan];

    BOOL svcOn = [[NSUserDefaults standardUserDefaults] objectForKey:YK_DEF_SERVICE] ? [[NSUserDefaults standardUserDefaults] boolForKey:YK_DEF_SERVICE] : YES;
    BOOL wanOn = [[NSUserDefaults standardUserDefaults] boolForKey:YK_DEF_WAN];
    NSDictionary *peer = [[NSUserDefaults standardUserDefaults] dictionaryForKey:YK_DEF_PEER];
    NSString *peerName = peer[@"name"];
    NSString *peerIP = peer[@"ip"];
    NSArray *rows = @[ @[@"服务开关", @"允许局域网电脑接入当前设备", @"bolt.fill", @(svcOn ? 1 : 0)],
                       @[@"广域网", @"允许外网通过安全隧道接入当前设备", @"globe", @(wanOn ? 1 : 0)],
                       @[(peerName.length ? peerName : @"未连接设备"),
                         (peerIP.length ? [NSString stringWithFormat:@"IP %@", peerIP] : @"当前暂无电脑接入"),
                         @"display", @(peerName.length ? 2 : -1)] ];
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
            sw.tag = 100 + i;
            [sw addTarget:self action:@selector(ykSwitchChanged:)
                forControlEvents:UIControlEventValueChanged];
            [row addSubview:sw];
            if (i == 0) { _svcSwitch = sw; _svcRow = row; }
            if (i == 1) { _wanSwitch = sw; _wanRow = row; }
        } else {
            BOOL connected = ([r[3] intValue] == 2);
            if (connected) {
                row.backgroundColor = [YkBlue() colorWithAlphaComponent:0.06];
                row.layer.borderColor = [YkBlue() colorWithAlphaComponent:0.18].CGColor;
                row.layer.borderWidth = 1.0;
                UILabel *pill = [self ykLabel:@"已连接" size:12 bold:YES color:YkGreen()];
                pill.textAlignment = NSTextAlignmentCenter;
                pill.backgroundColor = [YkGreen() colorWithAlphaComponent:0.12];
                pill.layer.cornerRadius = 12;
                pill.clipsToBounds = YES;
                pill.frame = CGRectMake(row.bounds.size.width - 86, 22, 62, 24);
                [row addSubview:pill];
                tt.frame = CGRectMake(68, 15, 120, 22);
            } else {
                UILabel *pill = [self ykLabel:@"待接入" size:12 bold:NO color:YkSub()];
                pill.textAlignment = NSTextAlignmentRight;
                pill.frame = CGRectMake(row.bounds.size.width - 74, 26, 62, 18);
                [row addSubview:pill];
            }
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
    UIView *nameField = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, 96, CARD_W - INNER_PAD * 2, 56)];
    nameField.backgroundColor = [UIColor colorWithWhite:0.965 alpha:1.0];
    nameField.layer.cornerRadius = 12.0;
    [c3 addSubview:nameField];
    NSString *devName = [[NSUserDefaults standardUserDefaults] stringForKey:YK_DEF_NAME] ?: @"iPhone";
    _lblDeviceName = [self ykLabel:devName size:19 bold:YES color:YkMain()];
    _lblDeviceName.frame = CGRectMake(14, 16, 210, 24); [nameField addSubview:_lblDeviceName];
    UIButton *edit = [UIButton buttonWithType:UIButtonTypeSystem];
    edit.frame = CGRectMake(nameField.bounds.size.width - 52, 8, 40, 40);
    [edit setImage:[UIImage systemImageNamed:@"pencil"] forState:UIControlStateNormal];
    edit.tintColor = YkMain();
    [edit addTarget:self action:@selector(ykRename) forControlEvents:UIControlEventTouchUpInside];
    [nameField addSubview:edit];

    UILabel *n2 = [self ykLabel:@"设备 ID" size:12 bold:NO color:YkSub()];
    n2.frame = CGRectMake(INNER_PAD, 165, 200, 17); [c3 addSubview:n2];
    UIView *idField = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, 186, CARD_W - INNER_PAD * 2, 60)];
    idField.backgroundColor = [UIColor colorWithWhite:0.965 alpha:1.0];
    idField.layer.cornerRadius = 12.0;
    [c3 addSubview:idField];
    _lblDeviceID = [self ykLabel:@"1983fed10d4062e506291b023e92c27cc6e470bf" size:13 bold:NO color:YkMain()];
    _lblDeviceID.frame = CGRectMake(14, 8, 210, 44);
    _lblDeviceID.numberOfLines = 2; _lblDeviceID.lineBreakMode = NSLineBreakByCharWrapping;
    [idField addSubview:_lblDeviceID];
    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    copy.frame = CGRectMake(idField.bounds.size.width - 52, 10, 40, 40);
    [copy setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    copy.tintColor = YkMain();
    [copy addTarget:self action:@selector(ykCopyID) forControlEvents:UIControlEventTouchUpInside];
    [idField addSubview:copy];

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
    UIButton *spaceBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    spaceBtn.frame = row4.bounds;
    [spaceBtn addTarget:self action:@selector(ykRestartUserspace)
       forControlEvents:UIControlEventTouchUpInside];
    [row4 addSubview:spaceBtn];
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
                        @[@"脚本数量", @"-", @"doc.text", YkMagenta(),
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

    _scriptListBox = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, 72, CARD_W - INNER_PAD * 2, 54)];
    [c2 addSubview:_scriptListBox];

    UIView *emptyBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _scriptListBox.bounds.size.width, 54)];
    emptyBox.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    emptyBox.layer.cornerRadius = 10.0;
    emptyBox.tag = 9201;
    [_scriptListBox addSubview:emptyBox];
    UILabel *empty = [self ykLabel:@"暂无订阅脚本" size:13 bold:NO color:YkSub()];
    empty.textAlignment = NSTextAlignmentCenter;
    empty.frame = CGRectMake(0, 18, emptyBox.bounds.size.width, 18);
    empty.tag = 9202;
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

    NSArray *steps = @[ @[@"1. 打开小球，回到桌面", @"点下方按钮后，App 会退到桌面，只留下 44x44 红色录制小球。",
                          @"record.circle", YkRed(),
                          [UIColor colorWithRed:0.99 green:0.93 blue:0.94 alpha:1.0]],
                        @[@"2. 拖动或点开小球", @"小球可拖动，轻点可展开；操作小球和菜单不会写进录制。",
                          @"hand.point.up.left.fill", YkBlue(),
                          [UIColor colorWithRed:0.92 green:0.95 blue:1.0 alpha:1.0]],
                        @[@"3. 开始、暂停、继续", @"点「开始」或按音量 + 后先倒计时；录制中可暂停，再点继续接着录。",
                          @"play.fill", YkGreen(),
                          [UIColor colorWithRed:0.92 green:0.97 blue:0.94 alpha:1.0]],
                        @[@"4. 完成并命名保存", @"点「完成」或按音量 - 会回到 App 命名；留空就按当前时间保存。",
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
        d.frame = CGRectMake(56, 27, 227, 32); d.numberOfLines = 2;
        d.lineBreakMode = NSLineBreakByTruncatingTail; [row addSubview:d];
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
    [rec addTarget:self action:@selector(ykOpenRecordBall)
  forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:rec];

    // ---------- 我的录制（回放指引 + 列表）----------
    UIView *rc = [self ykCard:CGRectMake(CARD_X, 594, CARD_W, 402)];
    [_recordScroll addSubview:rc];
    [self ykCardHeader:rc title:@"我的录制" symbol:@"list.bullet.rectangle" tint:YkMagenta()];

    UILabel *rsub = [self ykLabel:@"回放流程怎么用" size:15 bold:YES color:YkMain()];
    rsub.frame = CGRectMake(INNER_PAD, 72, 295, 20); [rc addSubview:rsub];

    NSArray *rsteps = @[ @[@"1. 点回放，先选次数", @"可选 1 次、3 次、10 次、自定义次数，或无循环。",
                           @"repeat.1", YkBlue()],
                         @[@"2. 确认后回到桌面", @"回到桌面后开始注入，逐帧重放录制的事件。",
                           @"play.fill", YkGreen()],
                         @[@"3. 可暂停、继续、停止", @"回放中可随时停止；结束后自动回到本页。",
                           @"stop.circle.fill", YkRed()] ];
    for (NSInteger i = 0; i < 3; i++) {
        NSArray *r = rsteps[i];
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, 100 + i * 58,
                                                              CARD_W - INNER_PAD * 2, 50)];
        row.backgroundColor = [UIColor colorWithWhite:0.975 alpha:1.0];
        row.layer.cornerRadius = 10.0;
        [rc addSubview:row];
        [row addSubview:[self ykIconBox:CGRectMake(8, 9, 32, 32) symbol:r[2] tint:r[3] glyph:16]];
        UILabel *t = [self ykLabel:r[0] size:14 bold:YES color:YkMain()];
        t.frame = CGRectMake(50, 6, 220, 18); [row addSubview:t];
        UILabel *d = [self ykLabel:r[1] size:11 bold:NO color:YkSub()];
        d.frame = CGRectMake(50, 22, 236, 26); d.numberOfLines = 2; [row addSubview:d];
    }

    _recordListBox = [[UIView alloc] initWithFrame:CGRectMake(INNER_PAD, 280, CARD_W - INNER_PAD * 2, 100)];
    [rc addSubview:_recordListBox];
    [self ykRefreshRecordList];

    _recordScroll.contentSize = CGSizeMake(_W, 1020);
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
        // 切到录制页时刷新一次（小球在后台保存的记录要能立刻看到）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self ykRefreshRecordList]; });
    }
}


#pragma mark - 交互动作

- (UIViewController *)ykHost {
    UIWindow *win = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                    if (w.isKeyWindow) { win = w; break; }
                }
            }
            if (win) break;
        }
    }
    if (!win) win = [UIApplication sharedApplication].keyWindow;
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

- (void)ykSwitchChanged:(UISwitch *)sw {
    if (sw == _svcSwitch) {
        [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:YK_DEF_SERVICE];
        [[NSUserDefaults standardUserDefaults] synchronize];
        YKSetServiceEnabled(sw.on);
        [self ykStyleRow:_svcRow on:sw.on];
        NSString *flag = @"/var/mobile/Library/YKEngineLite/service.on";
        [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/YKEngineLite"
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSString stringWithFormat:@"%d", sw.on ? 1 : 0]
            writeToFile:flag atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:
            [NSURL URLWithString:@"http://127.0.0.1:65325/system/service"]];
        rq.HTTPMethod = @"POST";
        rq.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"on": @(sw.on) }
                                                     options:0 error:NULL];
        [rq setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [[[NSURLSession sharedSession] dataTaskWithRequest:rq
                                         completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {}] resume];
    } else if (sw == _wanSwitch) {
        [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:YK_DEF_WAN];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self ykStyleRow:_wanRow on:sw.on];
        // Lite 无中继隧道：仅记录开关状态（与原版开关行为对齐）
    }
}


- (void)ykStyleRow:(UIView *)row on:(BOOL)on {
    if (!row) return;
    row.backgroundColor = on ? [YkBlue() colorWithAlphaComponent:0.06] : [UIColor whiteColor];
    row.layer.borderColor = (on ? [YkBlue() colorWithAlphaComponent:0.18]
                                : [UIColor colorWithWhite:0.93 alpha:1.0]).CGColor;
}

- (void)ykToggleService:(UISwitch *)sw { [self ykSwitchChanged:sw]; }
- (void)ykToggleWAN:(UISwitch *)sw { [self ykSwitchChanged:sw]; }

- (void)ykRename {
    __weak typeof(self) ws = self;
    YKAlertRename([self ykHost], _lblDeviceName.text, ^(NSString *name) {
        __strong typeof(ws) sf = ws; if (!sf) return;
        sf->_lblDeviceName.text = name;
        [[NSUserDefaults standardUserDefaults] setObject:name forKey:YK_DEF_NAME];
        [[NSUserDefaults standardUserDefaults] synchronize];
    });
}

- (void)ykCopyID {
    NSString *sid = _lblDeviceID.text ?: @"";
    [UIPasteboard generalPasteboard].string = sid;
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}

- (void)ykScanConnect {
    __weak typeof(self) ws = self;
    YKPresentScan([self ykHost], NO, @"扫一扫连接设备", ^(NSString *code) {
        __strong typeof(ws) sf = ws; if (!sf) return;
        [sf ykHandleConnectCode:code];
    });
}

// 二维码内容：JSON 或 URL 查询串；广域网码需要先开启广域网（与原版一致）
- (void)ykHandleConnectCode:(NSString *)code {
    NSString *trim = [code stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL wanCode = [trim.lowercaseString containsString:@"wan"]
                || [trim.lowercaseString containsString:@"tunnel"];
    BOOL wanOn = [[NSUserDefaults standardUserDefaults] boolForKey:YK_DEF_WAN];
    if (wanCode && !wanOn) {
        YKAlert([self ykHost], @"广域网连接提示",
                @"当前设备尚未开启广域网，请先开启后再扫码连接。", @[@"好"], nil);
        return;
    }

    NSDictionary *info = nil;
    NSData *d = [trim dataUsingEncoding:NSUTF8StringEncoding];
    if (d) info = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    if (![info isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *q = [NSMutableDictionary dictionary];
        NSRange r = [trim rangeOfString:@"?"];
        NSString *qs = (r.location != NSNotFound) ? [trim substringFromIndex:r.location + 1] : trim;
        for (NSString *kv in [qs componentsSeparatedByString:@"&"]) {
            NSArray *parts = [kv componentsSeparatedByString:@"="];
            if (parts.count == 2) {
                q[[parts[0] stringByRemovingPercentEncoding] ?: parts[0]] =
                    [parts[1] stringByRemovingPercentEncoding] ?: parts[1];
            }
        }
        info = q;
    }

    NSString *ip = info[@"ip"] ?: info[@"host"] ?: info[@"address"];
    NSString *name = info[@"name"] ?: info[@"device"] ?: info[@"deviceName"] ?: @"PC";
    if (!ip.length) {
        YKAlert([self ykHost], @"二维码无效", @"未解析到设备地址，请重新扫码。", @[@"好"], nil);
        return;
    }
    NSDictionary *peer = @{ @"name": name, @"ip": ip,
                            @"port": info[@"port"] ?: @(65322) };
    [[NSUserDefaults standardUserDefaults] setObject:peer forKey:YK_DEF_PEER];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self ykRebuildDevicePage];
    YKAlert([self ykHost], @"连接设备", [NSString stringWithFormat:@"%@  IP %@", name, ip],
            @[@"好"], nil);
}

// 重建设备页（连接信息变化后刷新）
- (void)ykRebuildDevicePage {
    if (!_devScroll) return;
    CGFloat y = _devScroll.contentOffset.y;
    [_devScroll removeFromSuperview];
    _devScroll = nil;
    [self ykDevicePage];
    _devScroll.contentOffset = CGPointMake(0, y);
}

- (void)ykAddScript {
    __weak typeof(self) ws = self;
    YKPresentScan([self ykHost], YES, @"添加脚本", ^(NSString *code) {
        __strong typeof(ws) sf = ws; if (!sf) return;
        [sf ykSubscribeScript:code];
    });
}

// 脚本码订阅：与文案对齐（正在添加脚本，请稍候 / 脚本订阅信息不完整）
- (void)ykSubscribeScript:(NSString *)code {
    NSString *c = [code stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (c.length < 4) {
        YKAlert([self ykHost], @"脚本订阅信息不完整", @"脚本码为空或长度不足，请重新扫码。", @[@"好"], nil);
        return;
    }
    UIAlertController *hud = [UIAlertController alertControllerWithTitle:nil
                                                               message:@"正在添加脚本，请稍候"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [[self ykHost] presentViewController:hud animated:YES completion:nil];

    // 脚本码 → 订阅条目（本地保存 name/hash/status）
    NSString *hash = [self ykHashOf:c];
    NSString *name = [c containsString:@"://"]
        ? [[c componentsSeparatedByString:@"://"].lastObject componentsSeparatedByString:@"/"].firstObject
        : [NSString stringWithFormat:@"脚本 %@", [hash substringToIndex:6]];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [hud dismissViewControllerAnimated:YES completion:^{
            NSMutableArray *list = [[[NSUserDefaults standardUserDefaults]
                                     arrayForKey:YK_DEF_SCRIPTS] mutableCopy] ?: [NSMutableArray array];
            for (NSDictionary *o in list) {
                if ([o[@"code"] isEqualToString:c]) {
                    YKAlert([self ykHost], @"已订阅", @"该脚本已在订阅列表中。", @[@"好"], nil);
                    return;
                }
            }
            [list addObject:@{ @"code": c, @"name": name ?: @"未命名脚本",
                               @"hash": hash, @"status": @"已订阅 · 自动更新",
                               @"addedAt": @([[NSDate date] timeIntervalSince1970]) }];
            [[NSUserDefaults standardUserDefaults] setObject:list forKey:YK_DEF_SCRIPTS];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self ykReloadScripts];
            YKAlert([self ykHost], @"已添加脚本", name ?: c, @[@"好"], nil);
        }];
    });
}

- (NSString *)ykHashOf:(NSString *)s {
    const char *c = s.UTF8String;
    unsigned long h = 5381;
    while (*c) h = ((h << 5) + h) + (unsigned char)(*c++);
    return [NSString stringWithFormat:@"%016lx", h];
}

- (void)ykRestartUserspace {
    YKAlertRestart([self ykHost], ^{
        YKRequestRestartUserspace();
    });
}

#pragma mark - 录制

- (void)ykRefreshRecordList {
    if (!_recordListBox) return;
    for (UIView *v in _recordListBox.subviews) [v removeFromSuperview];

    NSArray *recs = nil;
    NSURL *u = [NSURL URLWithString:@"http://127.0.0.1:65325/record/list"];
    NSData *d = [NSData dataWithContentsOfURL:u];
    if (d) {
        NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
        recs = j[@"value"][@"records"];
    }
    if (![recs isKindOfClass:[NSArray class]]) recs = @[];

    CGFloat w = _recordListBox.bounds.size.width;
    if (!recs.count) {
        UIView *empty = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 54)];
        empty.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
        empty.layer.cornerRadius = 10.0;
        [_recordListBox addSubview:empty];
        UILabel *l = [self ykLabel:@"还没有录制脚本" size:13 bold:NO color:YkSub()];
        l.textAlignment = NSTextAlignmentCenter;
        l.frame = CGRectMake(0, 18, w, 18);
        [empty addSubview:l];
        return;
    }

    CGFloat y = 0;
    for (NSDictionary *r in recs) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, 84)];
        row.backgroundColor = [UIColor colorWithWhite:0.975 alpha:1.0];
        row.layer.cornerRadius = 10.0;
        [_recordListBox addSubview:row];

        [row addSubview:[self ykIconBox:CGRectMake(8, 20, 44, 44)
                                 symbol:@"record.circle" tint:YkRed() glyph:22]];
        UILabel *name = [self ykLabel:(r[@"name"] ?: @"未命名") size:15 bold:YES color:YkMain()];
        name.frame = CGRectMake(62, 12, 120, 18); [row addSubview:name];

        NSNumber *dur = r[@"duration"] ?: @0;
        NSNumber *cnt = r[@"count"] ?: @0;
        UILabel *meta = [self ykLabel:[NSString stringWithFormat:@"%.1fs · %@ 事件",
                                       dur.doubleValue, cnt] size:11 bold:NO color:YkSub()];
        meta.frame = CGRectMake(62, 32, 130, 16); [row addSubview:meta];

        UIButton *play = [UIButton buttonWithType:UIButtonTypeSystem];
        play.frame = CGRectMake(w - 132, 22, 60, 40);
        [play setTitle:@"回放" forState:UIControlStateNormal];
        play.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        play.backgroundColor = [YkBlue() colorWithAlphaComponent:0.12];
        play.layer.cornerRadius = 10;
        [play setTitleColor:YkBlue() forState:UIControlStateNormal];
        play.accessibilityIdentifier = r[@"id"];
        [play addTarget:self action:@selector(ykPlayRecord:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:play];

        UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
        del.frame = CGRectMake(w - 66, 22, 60, 40);
        [del setTitle:@"删除" forState:UIControlStateNormal];
        del.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        del.backgroundColor = [YkRed() colorWithAlphaComponent:0.10];
        del.layer.cornerRadius = 10;
        [del setTitleColor:YkRed() forState:UIControlStateNormal];
        del.accessibilityIdentifier = r[@"id"];
        [del addTarget:self action:@selector(ykDeleteRecord:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:del];

        y += 92;
    }
    CGRect f = _recordListBox.frame;
    f.size.height = MAX(54, y);
    _recordListBox.frame = f;
}

- (void)ykPlayRecord:(UIButton *)b {
    NSString *rid = b.accessibilityIdentifier;
    __weak typeof(self) ws = self;
    YKAlert([self ykHost], @"选择回放次数", nil,
            @[@"1 次", @"3 次", @"10 次"], ^(NSInteger i) {
        __strong typeof(ws) sf = ws; if (!sf) return;
        int times = (i == 0) ? 1 : (i == 1 ? 3 : 10);
        NSDictionary *body = @{ @"id": rid ?: @"" , @"times": @(times), @"delayMs": @(1800) };
        NSData *d = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
        NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:
            [NSURL URLWithString:@"http://127.0.0.1:65325/record/play"]];
        r.HTTPMethod = @"POST"; r.HTTPBody = d;
        [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [[[NSURLSession sharedSession] dataTaskWithRequest:r
                                     completionHandler:^(NSData *d2, NSURLResponse *r2, NSError *e2) {}] resume];
        // 回放前退到桌面（与原版一致）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] performSelector:@selector(suspend)];
        });
    });
}

- (void)ykDeleteRecord:(UIButton *)b {
    NSString *rid = b.accessibilityIdentifier ?: @"";
    NSDictionary *body = @{ @"id": rid };
    NSData *d = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"http://127.0.0.1:65325/record/remove"]];
    r.HTTPMethod = @"POST"; r.HTTPBody = d;
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:r
        completionHandler:^(NSData *x, NSURLResponse *y, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self ykRefreshRecordList]; });
    }] resume];
}

- (void)ykOpenRecordBall {
    // 交给 SpringBoard 侧的悬浮球（跨 App 录制），随后退到桌面（与原版一致）
    CFMessagePortRef remote = CFMessagePortCreateRemote(kCFAllocatorDefault, CFSTR("com.yk.ball"));
    BOOL ok = NO;
    if (remote) {
        NSData *body = [NSJSONSerialization dataWithJSONObject:@{ @"action": @"show" }
                                                       options:0 error:NULL];
        CFDataRef reply = NULL;
        SInt32 st = CFMessagePortSendRequest(remote, 1, (__bridge CFDataRef)body,
                                             1.0, 1.0, kCFRunLoopDefaultMode, &reply);
        ok = (st == kCFMessagePortSuccess);
        if (reply) CFRelease(reply);
        CFRelease(remote);
    }
    if (!ok) {
        YKAlert([self ykHost], @"录制小球不可用",
                @"SpringBoard 插件未加载（com.yk.ball 通道无响应），请重启 SpringBoard 后重试。",
                @[@"好"], nil);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] performSelector:@selector(suspend)];
    });
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
    NSArray *list = [[NSUserDefaults standardUserDefaults] arrayForKey:YK_DEF_SCRIPTS] ?: @[];
    _lblScriptCount.text = list.count ? [NSString stringWithFormat:@"%lu", (unsigned long)list.count] : @"-";
    _lblHttpStatus.text = @"已开启";
    _lblHttpStatus.textColor = YkGreen();
    _lblState.text = @"就绪";
    _lblPort.text = @"65324";

    if (!_scriptListBox) return;
    for (UIView *v in _scriptListBox.subviews) [v removeFromSuperview];

    CGFloat w = _scriptListBox.bounds.size.width;
    if (!list.count) {
        _lblScriptEmpty.hidden = NO;
        _lblScriptEmpty.text = @"暂无订阅脚本";
        return;
    }
    _lblScriptEmpty.hidden = YES;

    CGFloat y = 0;
    for (NSDictionary *it in list) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, 64)];
        row.backgroundColor = [UIColor colorWithWhite:0.975 alpha:1.0];
        row.layer.cornerRadius = 10;
        [_scriptListBox addSubview:row];

        [row addSubview:[self ykIconBox:CGRectMake(8, 10, 44, 44)
                                  symbol:@"doc.text" tint:YkMagenta() glyph:22]];
        UILabel *name = [self ykLabel:(it[@"name"] ?: @"未命名脚本") size:15 bold:YES color:YkMain()];
        name.frame = CGRectMake(62, 10, w - 150, 18); [row addSubview:name];

        UILabel *meta = [self ykLabel:(it[@"status"] ?: @"已订阅 · 自动更新")
                                 size:11 bold:NO color:YkSub()];
        meta.frame = CGRectMake(62, 30, w - 150, 16); [row addSubview:meta];

        UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
        del.frame = CGRectMake(w - 70, 14, 62, 36);
        [del setTitle:@"删除" forState:UIControlStateNormal];
        del.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        del.backgroundColor = [YkRed() colorWithAlphaComponent:0.10];
        del.layer.cornerRadius = 9;
        [del setTitleColor:YkRed() forState:UIControlStateNormal];
        objc_setAssociatedObject(del, "code", it[@"code"] ?: @"", OBJC_ASSOCIATION_RETAIN);
        [del addTarget:self action:@selector(ykDeleteScript:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:del];

        y += 72;
    }
    CGRect f = _scriptListBox.frame;
    f.size.height = y;
    _scriptListBox.frame = f;
}

- (void)ykDeleteScript:(UIButton *)b {
    NSString *code = objc_getAssociatedObject(b, "code");
    __weak typeof(self) ws = self;
    YKAlert([self ykHost], @"删除脚本订阅？", @"将从订阅列表移除，确认要删除吗",
            @[@"取消", @"删除"], ^(NSInteger i) {
        if (i != 1) return;
        __strong typeof(ws) sf = ws; if (!sf) return;
        NSMutableArray *list = [[[NSUserDefaults standardUserDefaults]
                                 arrayForKey:YK_DEF_SCRIPTS] mutableCopy] ?: [NSMutableArray array];
        NSIndexSet *drop = [list indexesOfObjectsPassingTest:^BOOL(NSDictionary *o, NSUInteger idx, BOOL *st) {
            return [o[@"code"] isEqualToString:code ?: @""];
        }];
        [list removeObjectsAtIndexes:drop];
        [[NSUserDefaults standardUserDefaults] setObject:list forKey:YK_DEF_SCRIPTS];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [sf ykReloadScripts];
    });
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
