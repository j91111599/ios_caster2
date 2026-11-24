//  YKMainView — 按原版实测坐标复刻（frame 布局，无 Auto Layout）
//  数据来源：dump/ORIG_UI_SPEC.md（原版 /element/tree 实测，像素 @2x → 此处已 /2 换算为 pt）

#import <UIKit/UIKit.h>

static UIColor *YkBlue(void)   { return [UIColor colorWithRed:0.13 green:0.59 blue:0.95 alpha:1.0]; }
static UIColor *YkPageBg(void) { return [UIColor colorWithRed:0.95 green:0.96 blue:0.97 alpha:1.0]; }
static UIColor *YkSub(void)    { return [UIColor colorWithWhite:0.55 alpha:1.0]; }
static UIColor *YkMain(void)   { return [UIColor colorWithWhite:0.13 alpha:1.0]; }
static UIColor *YkTint(void)   { return [UIColor colorWithRed:0.13 green:0.59 blue:0.95 alpha:1.0]; }

@interface YKMainView : UIView
@property (nonatomic, strong) UIView *pageScript;
@property (nonatomic, strong) UIView *pageRecord;
@end

@implementation YKMainView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = YkPageBg();
        [self ykBuild];
    }
    return self;
}

- (UILabel *)ykLabel:(NSString *)text size:(CGFloat)sz bold:(BOOL)b color:(UIColor *)c {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = b ? [UIFont boldSystemFontOfSize:sz] : [UIFont systemFontOfSize:sz];
    l.textColor = c ?: YkMain();
    return l;
}

- (UIView *)ykCardAt:(CGRect)r {
    UIView *v = [[UIView alloc] initWithFrame:r];
    v.backgroundColor = [UIColor whiteColor];
    v.layer.cornerRadius = 14.0;
    return v;
}

- (UIView *)ykBadge:(CGRect)r symbol:(NSString *)name {
    UIView *box = [[UIView alloc] initWithFrame:r];
    box.backgroundColor = [YkTint() colorWithAlphaComponent:0.10];
    box.layer.cornerRadius = 12.0;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake((r.size.width-22)/2,(r.size.height-22)/2,22,22)];
    iv.image = [UIImage systemImageNamed:name];
    iv.tintColor = YkTint();
    iv.contentMode = UIViewContentModeScaleAspectFit;
    [box addSubview:iv];
    return box;
}

- (void)ykBuild {
    CGFloat W = self.bounds.size.width  > 1 ? self.bounds.size.width  : 375.0;
    CGFloat H = self.bounds.size.height > 1 ? self.bounds.size.height : 667.0;

    // ===== 顶部 =====
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 100)];
    header.backgroundColor = YkBlue();
    [self addSubview:header];

    UILabel *title = [self ykLabel:@"远控 Pro" size:20 bold:YES color:[UIColor whiteColor]];
    title.textAlignment = NSTextAlignmentCenter;
    title.frame = CGRectMake(0, 30, W, 26);
    title.backgroundColor = [UIColor clearColor];
    [self addSubview:title];
    [self bringSubviewToFront:title];

    UIButton *home = [UIButton buttonWithType:UIButtonTypeSystem];
    home.frame = CGRectMake(4, 20, 44, 44);
    [home setImage:[UIImage systemImageNamed:@"house.fill"] forState:UIControlStateNormal];
    home.tintColor = [UIColor whiteColor];
    [header addSubview:home];

    UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
    more.frame = CGRectMake(W-48, 20, 44, 44);
    [more setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
    more.tintColor = [UIColor whiteColor];
    [header addSubview:more];

    // ===== 内容 =====
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 100, W, H-168)];
    scroll.showsVerticalScrollIndicator = YES;
    [self addSubview:scroll];

    // 脚本页 / 录制页（默认隐藏，覆盖在内容区）
    _pageScript = [self ykListPage:@"脚本" hint:@"暂无脚本，等待 PC 端下发"];
    _pageRecord = [self ykListPage:@"录制" hint:@"暂无录制任务"];
    _pageScript.hidden = YES; _pageRecord.hidden = YES;
    _pageScript.frame = scroll.frame; _pageRecord.frame = scroll.frame;
    [self addSubview:_pageScript]; [self addSubview:_pageRecord];

    // 卡片一：连接设备
    UIView *c1 = [self ykCardAt:CGRectMake(12, 0, W-24, 220)];
    [scroll addSubview:c1];
    UILabel *t1 = [self ykLabel:@"连接设备" size:17 bold:YES color:YkMain()];
    t1.frame = CGRectMake(74, 14, 130, 22);
    [c1 addSubview:t1];
    [c1 addSubview:[self ykBadge:CGRectMake(16, 10, 44, 44) symbol:@"wifi"]];

    UIButton *scan = [UIButton buttonWithType:UIButtonTypeSystem];
    scan.frame = CGRectMake(c1.bounds.size.width-108, 10, 96, 36);
    [scan setTitle:@"扫码连接" forState:UIControlStateNormal];
    scan.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    scan.backgroundColor = [YkTint() colorWithAlphaComponent:0.12];
    scan.layer.cornerRadius = 10.0;
    [scan setTitleColor:YkTint() forState:UIControlStateNormal];
    [c1 addSubview:scan];

    NSArray *rows = @[ @[@"服务开关", @"允许局域网电脑接入当前设备", @"bolt.fill"],
                       @[@"广域网",   @"允许外网通过安全隧道接入当前设备", @"globe"],
                       @[@"未连接设备", @"当前暂无电脑接入", @"desktopcomputer"] ];
    CGFloat rowY = 62;
    for (NSInteger i = 0; i < (NSInteger)rows.count; i++) {
        NSArray *r = rows[i];
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(8, rowY, c1.bounds.size.width-16, 52)];
        row.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
        row.layer.cornerRadius = 12.0;
        [c1 addSubview:row];

        [row addSubview:[self ykBadge:CGRectMake(6, 4, 44, 44) symbol:r[2]]];
        UILabel *tt = [self ykLabel:r[0] size:15 bold:YES color:YkMain()];
        tt.frame = CGRectMake(58, 7, 170, 19);
        [row addSubview:tt];
        UILabel *ss = [self ykLabel:r[1] size:10.5 bold:NO color:YkSub()];
        ss.frame = CGRectMake(58, 27, 195, 14);
        [row addSubview:ss];

        if (i < 2) {
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(row.bounds.size.width-66, 10, 51, 31)];
            sw.on = (i == 0);
            sw.onTintColor = YkTint();
            [row addSubview:sw];
        } else {
            UILabel *pill = [self ykLabel:@"待接入" size:13 bold:NO color:YkSub()];
            pill.textAlignment = NSTextAlignmentCenter;
            pill.frame = CGRectMake(row.bounds.size.width-72, 16, 62, 20);
            [row addSubview:pill];
        }
        rowY += 58;
    }

    // 卡片二：运行状态
    UIView *c2 = [self ykCardAt:CGRectMake(12, 232, W-24, 150)];
    [scroll addSubview:c2];
    UILabel *t2 = [self ykLabel:@"运行状态" size:17 bold:YES color:YkMain()];
    t2.frame = CGRectMake(74, 14, 130, 22);
    [c2 addSubview:t2];
    [c2 addSubview:[self ykBadge:CGRectMake(16, 10, 44, 44) symbol:@"chart.bar.fill"]];

    NSArray *kv = @[ @[@"设备 IP", @"192.168.1.43", @"越狱方式", @"隐根"],
                     @[@"系统分辨率", @"750×1334", @"应用版本", @"3.9.5"] ];
    for (NSInteger i = 0; i < (NSInteger)kv.count; i++) {
        NSArray *r = kv[i];
        CGFloat y = 62 + i * 42;
        UILabel *k1 = [self ykLabel:r[0] size:11 bold:NO color:YkSub()];
        k1.frame = CGRectMake(36, y, 90, 15); [c2 addSubview:k1];
        UILabel *v1 = [self ykLabel:r[1] size:14 bold:YES color:YkMain()];
        v1.frame = CGRectMake(36, y+15, 116, 20); [c2 addSubview:v1];
        UILabel *k2 = [self ykLabel:r[2] size:11 bold:NO color:YkSub()];
        k2.frame = CGRectMake(190, y, 90, 15); [c2 addSubview:k2];
        UILabel *v2 = [self ykLabel:r[3] size:14 bold:YES color:YkMain()];
        v2.frame = CGRectMake(190, y+15, 116, 20); [c2 addSubview:v2];
    }

    // 卡片三：设备信息
    UIView *c3 = [self ykCardAt:CGRectMake(12, 394, W-24, 190)];
    [scroll addSubview:c3];
    UILabel *t3 = [self ykLabel:@"设备信息" size:17 bold:YES color:YkMain()];
    t3.frame = CGRectMake(74, 14, 130, 22);
    [c3 addSubview:t3];
    [c3 addSubview:[self ykBadge:CGRectMake(16, 10, 44, 44) symbol:@"gearshape.fill"]];

    UILabel *n1 = [self ykLabel:@"设备名称" size:11 bold:NO color:YkSub()];
    n1.frame = CGRectMake(24, 64, 200, 15); [c3 addSubview:n1];
    UILabel *nv = [self ykLabel:@"iPhone" size:14 bold:YES color:YkMain()];
    nv.frame = CGRectMake(38, 84, 230, 20); [c3 addSubview:nv];

    UILabel *n2 = [self ykLabel:@"设备 ID" size:11 bold:NO color:YkSub()];
    n2.frame = CGRectMake(24, 118, 200, 15); [c3 addSubview:n2];
    UILabel *nv2 = [self ykLabel:@"1983fed10d4062e506291b023e92c27cc6e470bf"
                            size:10 bold:NO color:YkMain()];
    nv2.frame = CGRectMake(38, 138, 300, 32);
    nv2.numberOfLines = 2;
    [c3 addSubview:nv2];

    // 设备 ID 的复制按钮（原版 x=566,y=1820,w=80,h=80 → 283,910,40,40）
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(c3.bounds.size.width-52, 132, 40, 40);
    [copyBtn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    copyBtn.tintColor = YkSub();
    [copyBtn addTarget:self action:@selector(ykCopyID:) forControlEvents:UIControlEventTouchUpInside];
    [c3 addSubview:copyBtn];

    // 卡片四：重启用户空间
    UIView *c4 = [self ykCardAt:CGRectMake(12, 596, W-24, 112)];
    [scroll addSubview:c4];
    UILabel *t4 = [self ykLabel:@"重启用户空间" size:17 bold:YES color:YkMain()];
    t4.frame = CGRectMake(74, 14, 170, 22);
    [c4 addSubview:t4];
    [c4 addSubview:[self ykBadge:CGRectMake(16, 10, 44, 44) symbol:@"arrow.clockwise"]];

    UILabel *tip1 = [self ykLabel:@"提示" size:13 bold:YES color:YkMain()];
    tip1.frame = CGRectMake(74, 60, 120, 18); [c4 addSubview:tip1];
    UILabel *tip2 = [self ykLabel:@"将直接重启用户空间，并断开当前 PC 连接，仅在异常时使用"
                            size:12 bold:NO color:YkSub()];
    tip2.frame = CGRectMake(74, 80, W-110, 32);
    tip2.numberOfLines = 2;
    [c4 addSubview:tip2];

    scroll.contentSize = CGSizeMake(W, 730);

    // ===== 底部导航（原版 y=1198px=599pt，三按钮 w=110 h=60）=====
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, H-68, W, 68)];
    bar.backgroundColor = [UIColor whiteColor];
    [self addSubview:bar];

    NSArray *names = @[@"设备", @"脚本", @"录制"];
    NSArray *icons = @[@"iphone", @"terminal", @"record.circle"];
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(22 + i * 110, 6, 110, 56);
        b.tag = i;
        [b setTitle:names[i] forState:UIControlStateNormal];
        [b setImage:[UIImage systemImageNamed:icons[i]] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:11];
        b.tintColor = (i == 0) ? YkTint() : YkSub();
        [b addTarget:self action:@selector(ykTab:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:b];
    }
}

- (void)ykTab:(UIButton *)sender {
    for (UIView *v in sender.superview.subviews) {
        if ([v isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)v;
            b.tintColor = (b.tag == sender.tag) ? YkTint() : YkSub();
        }
    }
    // 切页：0=设备 1=脚本 2=录制
    _pageScript.hidden = (sender.tag != 1);
    _pageRecord.hidden = (sender.tag != 2);
    for (UIView *sv in self.subviews) {
        if ([sv isKindOfClass:[UIScrollView class]]) sv.hidden = (sender.tag != 0);
    }
    if (sender.tag != 0) {
        _pageScript.frame = CGRectMake(0, 100, self.bounds.size.width, self.bounds.size.height - 168);
        _pageRecord.frame = _pageScript.frame;
    }
}

@end
