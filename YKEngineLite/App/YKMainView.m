//  YKMainView — 三页复刻（纯 frame 布局）
//  文案来源：dump/orig_ui_text.txt（原版二进制 __cfstring 抽出 657 条）
//  结构来源：dump/project_rn/YKApp/{YKViewYyyy,YKScriptView,YKRecordView}.m

#import <UIKit/UIKit.h>

static UIColor *YkBlue(void)   { return [UIColor colorWithRed:0.13 green:0.59 blue:0.95 alpha:1.0]; }
static UIColor *YkPageBg(void) { return [UIColor colorWithRed:0.95 green:0.96 blue:0.97 alpha:1.0]; }
static UIColor *YkSub(void)    { return [UIColor colorWithWhite:0.55 alpha:1.0]; }
static UIColor *YkMain(void)   { return [UIColor colorWithWhite:0.13 alpha:1.0]; }
static UIColor *YkTint(void)   { return [UIColor colorWithRed:0.13 green:0.59 blue:0.95 alpha:1.0]; }

@interface YKMainView : UIView
@property (nonatomic, strong) UIScrollView *devScroll;
@property (nonatomic, strong) UIScrollView *scriptScroll;
@property (nonatomic, strong) UIScrollView *recordScroll;
@property (nonatomic, strong) UIView *bottomBar;
- (UILabel *)ykLabel:(NSString *)t size:(CGFloat)s bold:(BOOL)b color:(UIColor *)c;
- (UIView *)ykCard:(CGRect)r;
- (UIView *)ykBadge:(CGRect)r symbol:(NSString *)n;
- (void)ykTab:(UIButton *)sender;
- (void)ykShowPageObj:(id)o;
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

- (UILabel *)ykLabel:(NSString *)t size:(CGFloat)s bold:(BOOL)b color:(UIColor *)c {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = b ? [UIFont boldSystemFontOfSize:s] : [UIFont systemFontOfSize:s];
    l.textColor = c ?: YkMain();
    return l;
}

- (UIView *)ykCard:(CGRect)r {
    UIView *v = [[UIView alloc] initWithFrame:r];
    v.backgroundColor = [UIColor whiteColor];
    v.layer.cornerRadius = 14.0;
    return v;
}

- (UIView *)ykBadge:(CGRect)r symbol:(NSString *)n {
    UIView *box = [[UIView alloc] initWithFrame:r];
    box.backgroundColor = [YkTint() colorWithAlphaComponent:0.10];
    box.layer.cornerRadius = 12.0;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake((r.size.width-22)/2,(r.size.height-22)/2,22,22)];
    iv.image = [UIImage systemImageNamed:n];
    iv.tintColor = YkTint();
    iv.contentMode = UIViewContentModeScaleAspectFit;
    [box addSubview:iv];
    return box;
}

- (void)ykHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _W, 100)];
    header.backgroundColor = YkBlue();
    [self addSubview:header];

    UILabel *title = [self ykLabel:@"远控 Pro" size:20 bold:YES color:[UIColor whiteColor]];
    title.textAlignment = NSTextAlignmentCenter;
    title.frame = CGRectMake(0, 30, _W, 26);
    title.backgroundColor = [UIColor clearColor];
    [self addSubview:title];
    [self bringSubviewToFront:title];

    UIButton *home = [UIButton buttonWithType:UIButtonTypeSystem];
    home.frame = CGRectMake(4, 20, 44, 44);
    [home setImage:[UIImage systemImageNamed:@"house.fill"] forState:UIControlStateNormal];
    home.tintColor = [UIColor whiteColor];
    [header addSubview:home];

    UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
    more.frame = CGRectMake(_W-48, 20, 44, 44);
    [more setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
    more.tintColor = [UIColor whiteColor];
    [header addSubview:more];
}

#pragma mark - 设备页

- (void)ykDevicePage {
    _devScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 100, _W, _H-168)];
    [self addSubview:_devScroll];

    UIView *c1 = [self ykCard:CGRectMake(12, 0, _W-24, 220)];
    [_devScroll addSubview:c1];
    UILabel *t1 = [self ykLabel:@"连接设备" size:17 bold:YES color:YkMain()];
    t1.frame = CGRectMake(74, 14, 130, 22); [c1 addSubview:t1];
    [c1 addSubview:[self ykBadge:CGRectMake(16, 10, 44, 44) symbol:@"wifi"]];

    UIButton *scan = [UIButton buttonWithType:UIButtonTypeSystem];
    scan.frame = CGRectMake(c1.bounds.size.width-108, 10, 96, 36);
    [scan setTitle:@"扫码连接" forState:UIControlStateNormal];
    scan.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    scan.backgroundColor = [YkTint() colorWithAlphaComponent:0.12];
    scan.layer.cornerRadius = 10.0;
    [scan setTitleColor:YkTint() forState:UIControlStateNormal];
    [c1 addSubview:scan];

    NSArray *rows = @[ @[@"服务开关", @"允许局域网电脑接入当前设备", @"bolt.fill", @1],
                       @[@"广域网", @"允许外网通过安全隧道接入当前设备", @"globe", @0],
                       @[@"未连接设备", @"当前暂无电脑接入", @"desktopcomputer", @(-1)] ];
    for (NSInteger i = 0; i < 3; i++) {
        NSArray *r = rows[i];
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(8, 62 + i*58, c1.bounds.size.width-16, 52)];
        row.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
        row.layer.cornerRadius = 12.0;
        [c1 addSubview:row];
        [row addSubview:[self ykBadge:CGRectMake(6, 4, 44, 44) symbol:r[2]]];
        UILabel *tt = [self ykLabel:r[0] size:15 bold:YES color:YkMain()];
        tt.frame = CGRectMake(58, 7, 170, 19); [row addSubview:tt];
        UILabel *ss = [self ykLabel:r[1] size:10.5 bold:NO color:YkSub()];
        ss.frame = CGRectMake(58, 27, 195, 14); [row addSubview:ss];
        NSNumber *onv = r[3];
        if ([onv intValue] >= 0) {
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(row.bounds.size.width-66, 10, 51, 31)];
            sw.on = [onv boolValue]; sw.onTintColor = YkTint();
            [row addSubview:sw];
        } else {
            UILabel *pill = [self ykLabel:@"待接入" size:13 bold:NO color:YkSub()];
            pill.textAlignment = NSTextAlignmentCenter;
            pill.frame = CGRectMake(row.bounds.size.width-72, 16, 62, 20);
            [row addSubview:pill];
        }
    }

    // 运行状态
    UIView *c2 = [self ykCard:CGRectMake(12, 232, _W-24, 150)];
    [_devScroll addSubview:c2];
    UILabel *t2 = [self ykLabel:@"运行状态" size:17 bold:YES color:YkMain()];
    t2.frame = CGRectMake(74, 14, 130, 22); [c2 addSubview:t2];
    [c2 addSubview:[self ykBadge:CGRectMake(16, 10, 44, 44) symbol:@"chart.bar.fill"]];

    NSArray *kv = @[ @[@"设备 IP", @"192.168.1.43", @"越狱方式", @"隐根"],
                     @[@"系统分辨率", @"750×1334", @"应用版本", @"3.9.5"] ];
    for (NSInteger i = 0; i < 2; i++) {
        NSArray *r = kv[i]; CGFloat y = 62 + i*42;
        UILabel *k1 = [self ykLabel:r[0] size:11 bold:NO color:YkSub()];
        k1.frame = CGRectMake(36, y, 90, 15); [c2 addSubview:k1];
        UILabel *v1 = [self ykLabel:r[1] size:14 bold:YES color:YkMain()];
        v1.frame = CGRectMake(36, y+15, 116, 20); [c2 addSubview:v1];
        UILabel *k2 = [self ykLabel:r[2] size:11 bold:NO color:YkSub()];
        k2.frame = CGRectMake(190, y, 90, 15); [c2 addSubview:k2];
        UILabel *v2 = [self ykLabel:r[3] size:14 bold:YES color:YkMain()];
        v2.frame = CGRectMake(190, y+15, 116, 20); [c2 addSubview:v2];
    }

    // 设备信息
    UIView *c3 = [self ykCard:CGRectMake(12, 394, _W-24, 190)];
    [_devScroll addSubview:c3];
    UILabel *t3 = [self ykLabel:@"设备信息" size:17 bold:YES color:YkMain()];
    t3.frame = CGRectMake(74, 14, 130, 22); [c3 addSubview:t3];
    [c3 addSubview:[self ykBadge:CGRectMake(16, 10, 44, 44) symbol:@"gearshape.fill"]];

    UILabel *n1 = [self ykLabel:@"设备名称" size:11 bold:NO color:YkSub()];
    n1.frame = CGRectMake(24, 64, 200, 15); [c3 addSubview:n1];
    UILabel *nv = [self ykLabel:@"iPhone" size:14 bold:YES color:YkMain()];
    nv.frame = CGRectMake(38, 84, 230, 20); [c3 addSubview:nv];

    UILabel *n2 = [self ykLabel:@"设备 ID" size:11 bold:NO color:YkSub()];
    n2.frame = CGRectMake(24, 118, 200, 15); [c3 addSubview:n2];
    UILabel *nv2 = [self ykLabel:@"1983fed10d4062e506291b023e92c27cc6e470bf" size:10 bold:NO color:YkMain()];
    nv2.frame = CGRectMake(38, 138, 300, 32); nv2.numberOfLines = 2;
    [c3 addSubview:nv2];

    // 重启用户空间
    UIView *c4 = [self ykCard:CGRectMake(12, 596, _W-24, 112)];
    [_devScroll addSubview:c4];
    UILabel *t4 = [self ykLabel:@"重启用户空间" size:17 bold:YES color:YkMain()];
    t4.frame = CGRectMake(74, 14, 170, 22); [c4 addSubview:t4];
    [c4 addSubview:[self ykBadge:CGRectMake(16, 10, 44, 44) symbol:@"arrow.clockwise"]];
    UILabel *tp1 = [self ykLabel:@"提示" size:13 bold:YES color:YkMain()];
    tp1.frame = CGRectMake(74, 60, 120, 18); [c4 addSubview:tp1];
    UILabel *tp2 = [self ykLabel:@"将直接重启用户空间，并断开当前 PC 连接，仅在异常时使用" size:12 bold:NO color:YkSub()];
    tp2.frame = CGRectMake(74, 80, _W-110, 32); tp2.numberOfLines = 2;
    [c4 addSubview:tp2];

    _devScroll.contentSize = CGSizeMake(_W, 730);
}

#pragma mark - 脚本页（文案取自原版 __cfstring）

- (void)ykScriptPage {
    _scriptScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 100, _W, _H-168)];
    _scriptScroll.hidden = YES;
    [self addSubview:_scriptScroll];

    UIView *c1 = [self ykCard:CGRectMake(12, 0, _W-24, 250)];
    [_scriptScroll addSubview:c1];
    UILabel *t1 = [self ykLabel:@"脚本控制台" size:17 bold:YES color:YkMain()];
    t1.frame = CGRectMake(74, 14, 150, 22); [c1 addSubview:t1];
    [c1 addSubview:[self ykBadge:CGRectMake(16, 10, 44, 44) symbol:@"terminal"]];

    NSArray *kv = @[ @[@"HTTP 服务", @"检测中", @"当前状态", @"已开启"],
                     @[@"本地端口", @"65322", @"脚本数量", @"0"] ];
    for (NSInteger i = 0; i < 2; i++) {
        NSArray *r = kv[i]; CGFloat y = 62 + i*42;
        UILabel *k1 = [self ykLabel:r[0] size:11 bold:NO color:YkSub()];
        k1.frame = CGRectMake(36, y, 90, 15); [c1 addSubview:k1];
        UILabel *v1 = [self ykLabel:r[1] size:14 bold:YES color:YkMain()];
        v1.frame = CGRectMake(36, y+15, 116, 20); [c1 addSubview:v1];
        UILabel *k2 = [self ykLabel:r[2] size:11 bold:NO color:YkSub()];
        k2.frame = CGRectMake(190, y, 90, 15); [c1 addSubview:k2];
        UILabel *v2 = [self ykLabel:r[3] size:14 bold:YES color:YkMain()];
        v2.frame = CGRectMake(190, y+15, 116, 20); [c1 addSubview:v2];
    }
    UILabel *h1 = [self ykLabel:@"设备可通过互联网远程调试" size:12 bold:NO color:YkSub()];
    h1.frame = CGRectMake(36, 200, 300, 18); [c1 addSubview:h1];

    UIView *c2 = [self ykCard:CGRectMake(12, 262, _W-24, 96)];
    [_scriptScroll addSubview:c2];
    UILabel *t2 = [self ykLabel:@"远程调试安全状态" size:15 bold:YES color:YkMain()];
    t2.frame = CGRectMake(16, 14, 220, 20); [c2 addSubview:t2];
    UILabel *s2 = [self ykLabel:@"公网远程调试已开启" size:12 bold:NO color:YkSub()];
    s2.frame = CGRectMake(16, 40, 300, 18); [c2 addSubview:s2];
    UILabel *s3 = [self ykLabel:@"未连接" size:12 bold:NO color:YkSub()];
    s3.frame = CGRectMake(16, 62, 120, 18); [c2 addSubview:s3];

    UIView *c3 = [self ykCard:CGRectMake(12, 370, _W-24, 160)];
    [_scriptScroll addSubview:c3];
    UILabel *t3 = [self ykLabel:@"脚本列表" size:17 bold:YES color:YkMain()];
    t3.frame = CGRectMake(16, 14, 150, 22); [c3 addSubview:t3];

    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
    refresh.frame = CGRectMake(c3.bounds.size.width-100, 10, 84, 30);
    [refresh setTitle:@"刷新" forState:UIControlStateNormal];
    refresh.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    refresh.backgroundColor = [YkTint() colorWithAlphaComponent:0.12];
    refresh.layer.cornerRadius = 9.0;
    [refresh setTitleColor:YkTint() forState:UIControlStateNormal];
    [c3 addSubview:refresh];

    UILabel *empty = [self ykLabel:@"暂无订阅脚本" size:13 bold:NO color:YkSub()];
    empty.textAlignment = NSTextAlignmentCenter;
    empty.frame = CGRectMake(0, 90, c3.bounds.size.width, 20);
    [c3 addSubview:empty];
    UILabel *hint = [self ykLabel:@"刷新脚本列表" size:12 bold:NO color:YkSub()];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.frame = CGRectMake(0, 114, c3.bounds.size.width, 18);
    [c3 addSubview:hint];

    _scriptScroll.contentSize = CGSizeMake(_W, 560);
}

#pragma mark - 录制页（文案取自原版 __cfstring）

- (void)ykRecordPage {
    _recordScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 100, _W, _H-168)];
    _recordScroll.hidden = YES;
    [self addSubview:_recordScroll];

    UIView *c1 = [self ykCard:CGRectMake(12, 0, _W-24, 140)];
    [_recordScroll addSubview:c1];
    UILabel *t1 = [self ykLabel:@"录制中心" size:17 bold:YES color:YkMain()];
    t1.frame = CGRectMake(74, 14, 150, 22); [c1 addSubview:t1];
    [c1 addSubview:[self ykBadge:CGRectMake(16, 10, 44, 44) symbol:@"record.circle"]];

    UILabel *h1 = [self ykLabel:@"点下方按钮后，App 会退到桌面，只留下 44x44 红色录制小球。"
                            size:12 bold:NO color:YkSub()];
    h1.frame = CGRectMake(16, 58, _W-56, 34); h1.numberOfLines = 2;
    [c1 addSubview:h1];

    UIButton *start = [UIButton buttonWithType:UIButtonTypeSystem];
    start.frame = CGRectMake(c1.bounds.size.width-116, 98, 100, 32);
    [start setTitle:@"开始录制" forState:UIControlStateNormal];
    start.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    start.backgroundColor = YkTint();
    start.layer.cornerRadius = 10.0;
    [start setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [c1 addSubview:start];

    UIView *c2 = [self ykCard:CGRectMake(12, 152, _W-24, 160)];
    [_recordScroll addSubview:c2];
    UILabel *t2 = [self ykLabel:@"我的录制" size:17 bold:YES color:YkMain()];
    t2.frame = CGRectMake(16, 14, 150, 22); [c2 addSubview:t2];
    UILabel *empty = [self ykLabel:@"还没有录制脚本" size:13 bold:NO color:YkSub()];
    empty.textAlignment = NSTextAlignmentCenter;
    empty.frame = CGRectMake(0, 80, c2.bounds.size.width, 20);
    [c2 addSubview:empty];
    UILabel *h2 = [self ykLabel:@"录制向导" size:12 bold:NO color:YkSub()];
    h2.textAlignment = NSTextAlignmentCenter;
    h2.frame = CGRectMake(0, 106, c2.bounds.size.width, 18);
    [c2 addSubview:h2];

    UIView *c3 = [self ykCard:CGRectMake(12, 324, _W-24, 96)];
    [_recordScroll addSubview:c3];
    UILabel *t3 = [self ykLabel:@"选择回放次数" size:15 bold:YES color:YkMain()];
    t3.frame = CGRectMake(16, 14, 200, 20); [c3 addSubview:t3];
    NSArray *opts = @[@"回放 1 次", @"回放 3 次", @"回放 10 次"];
    for (NSInteger i = 0; i < 3; i++) {
        UILabel *o = [self ykLabel:opts[i] size:12 bold:NO color:[UIColor whiteColor]];
        o.textAlignment = NSTextAlignmentCenter;
        o.backgroundColor = [YkTint() colorWithAlphaComponent:0.85];
        o.layer.cornerRadius = 8.0; o.clipsToBounds = YES;
        o.frame = CGRectMake(16 + i*106, 52, 96, 28);
        [c3 addSubview:o];
    }

    _recordScroll.contentSize = CGSizeMake(_W, 450);
}

#pragma mark - 底部导航

- (void)ykBottom {
    _bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, _H-68, _W, 68)];
    _bottomBar.backgroundColor = [UIColor whiteColor];
    [self addSubview:_bottomBar];

    NSArray *names = @[@"设备", @"脚本", @"录制"];
    NSArray *icons = @[@"iphone", @"terminal", @"record.circle"];
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(22 + i*110, 6, 110, 56);
        b.tag = i;
        [b setTitle:names[i] forState:UIControlStateNormal];
        [b setImage:[UIImage systemImageNamed:icons[i]] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:11];
        b.tintColor = (i == 0) ? YkTint() : YkSub();
        [b addTarget:self action:@selector(ykTab:) forControlEvents:UIControlEventTouchUpInside];
        [_bottomBar addSubview:b];
    }
}

- (void)ykShowPageObj:(id)o {
    NSInteger i = [o isKindOfClass:[NSNumber class]] ? [o integerValue] : [o respondsToSelector:@selector(integerValue)] ? [o integerValue] : 0;
    _devScroll.hidden    = (i != 0);
    _scriptScroll.hidden = (i != 1);
    _recordScroll.hidden = (i != 2);
    for (UIView *v in _bottomBar.subviews) {
        if ([v isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)v;
            b.tintColor = (b.tag == i) ? YkTint() : YkSub();
        }
    }
}

- (void)ykTab:(UIButton *)sender {
    for (UIView *v in _bottomBar.subviews) {
        if ([v isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)v;
            b.tintColor = (b.tag == sender.tag) ? YkTint() : YkSub();
        }
    }
    _devScroll.hidden    = (sender.tag != 0);
    _scriptScroll.hidden = (sender.tag != 1);
    _recordScroll.hidden = (sender.tag != 2);
}

@end
