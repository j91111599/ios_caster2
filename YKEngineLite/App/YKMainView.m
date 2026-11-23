//  YKMainView — 主屏 1:1 复刻（结构完全依据反编译 YKViewYyyy）
//
//  反编译依据（dump/project_rn/YKApp/YKViewYyyy.m，8,147 行 / 393 约束）：
//    viewDidLoad:
//        bg = colorWithRed:0.96 green:0.96 blue:0.98 alpha:1.0
//        [self DtsYdatxijgQ69u0YcYvDfeHRigF6lHH]  → 挂载
//        [self XVX3WBjfMW9EuO2xJYoObrmBSJlUVayr]  → 约束（25 条在单个方法内）
//        [self vFu3Ezk0ARiNzjIrxFsVwsw1zYgIbbHx]  → contentStack 组装
//    层级：
//        view
//        ├── headerView
//        │   └── moreControl
//        └── scrollView
//            └── contentStack (vertical)
//                ├── heroCard
//                └── segmentControl
//        bottomBar
//        subscriptionDialogView / subscriptionOverlayView
//
//  间距常量（IEEE754 还原）：12 / 16 / 20 / 24 / 40 / 44 / 52（4pt 栅格）

#import <UIKit/UIKit.h>

static const CGFloat kGutter   = 12.0;   // 0x4028…
static const CGFloat kPad      = 16.0;   // 0x4030…
static const CGFloat kRowBase  = 44.0;   // 0x4046…
static const CGFloat kBadge    = 52.0;   // 0x404a…

static UIColor *YkBlue(void)      { return [UIColor colorWithRed:0.13 green:0.60 blue:0.95 alpha:1]; }
static UIColor *YkPageBg(void)    { return [UIColor colorWithRed:0.96 green:0.96 blue:0.98 alpha:1.0]; } // 反编译原值
static UIColor *YkTintBlue(void)  { return [UIColor colorWithRed:0.91 green:0.95 blue:1.0 alpha:1]; }
static UIColor *YkTintGray(void)  { return [UIColor colorWithWhite:0.94 alpha:1]; }
static UIColor *YkTintRed(void)   { return [UIColor colorWithRed:0.99 green:0.93 blue:0.92 alpha:1]; }
static UIColor *YkTitle(void)     { return [UIColor colorWithWhite:0.09 alpha:1]; }
static UIColor *YkSub(void)       { return [UIColor colorWithWhite:0.60 alpha:1]; }

@interface YKMainView : UIView
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIButton *moreControl;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIView *heroCard;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, strong) UIView *bottomBar;
@end

@implementation YKMainView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = YkPageBg();      // 反编译实测底色
        [self buildHeader];
        [self buildScrollAndStack];
        [self buildHeroCard];
        [self buildSegmentControl];
        [self buildBottomBar];
        [self installConstraints];
    }
    return self;
}

#pragma mark - headerView + moreControl

- (void)buildHeader {
    _headerView = [UIView new];
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    _headerView.backgroundColor = YkBlue();
    [self addSubview:_headerView];

    UILabel *title = [UILabel new];
    title.text = @"远控 Pro";
    title.font = [UIFont boldSystemFontOfSize:24];
    title.textColor = [UIColor whiteColor];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:title];

    _moreControl = [UIButton buttonWithType:UIButtonTypeSystem];
    [_moreControl setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
    _moreControl.tintColor = [UIColor whiteColor];
    _moreControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:_moreControl];

    [NSLayoutConstraint activateConstraints:@[
        [title.centerXAnchor constraintEqualToAnchor:_headerView.centerXAnchor],
        [title.bottomAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:-10.0],
        [_moreControl.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-kPad],
        [_moreControl.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [_moreControl.widthAnchor constraintEqualToConstant:kRowBase],
        [_moreControl.heightAnchor constraintEqualToConstant:kRowBase],
    ]];
}

#pragma mark - scrollView + contentStack

- (void)buildScrollAndStack {
    _scrollView = [UIScrollView new];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    [self addSubview:_scrollView];

    _contentStack = [UIStackView new];
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.spacing = kPad;              // 16
    _contentStack.alignment = UIStackViewAlignmentFill;
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_contentStack];
}

#pragma mark - heroCard（= 反编译 heroCard，内含连接设备区）

- (void)buildHeroCard {
    _heroCard = [UIView new];
    _heroCard.backgroundColor = [UIColor whiteColor];
    _heroCard.layer.cornerRadius = 18.0;
    _heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:_heroCard];

    // 卡片头：图标 + 标题 + 扫码
    UIView *icon = [self badge:@"dot.radiowaves.left.and.right" bg:YkTintBlue() tint:YkBlue() round:YES];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [_heroCard addSubview:icon];

    UILabel *title = [UILabel new];
    title.text = @"连接设备";
    title.font = [UIFont boldSystemFontOfSize:21];
    title.textColor = YkTitle();
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [_heroCard addSubview:title];

    UIButton *scan = [UIButton buttonWithType:UIButtonTypeSystem];
    [scan setTitle:@"扫码连接" forState:UIControlStateNormal];
    [scan setImage:[UIImage systemImageNamed:@"qrcode.viewfinder"] forState:UIControlStateNormal];
    scan.tintColor = YkBlue();
    scan.backgroundColor = YkTintBlue();
    scan.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    scan.layer.cornerRadius = 10;
    scan.translatesAutoresizingMaskIntoConstraints = NO;
    [_heroCard addSubview:scan];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:_heroCard.leadingAnchor constant:kPad],
        [icon.topAnchor constraintEqualToAnchor:_heroCard.topAnchor constant:kPad],
        [icon.widthAnchor constraintEqualToConstant:38.0],
        [icon.heightAnchor constraintEqualToConstant:38.0],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:kGutter],
        [title.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor],
        [scan.trailingAnchor constraintEqualToAnchor:_heroCard.trailingAnchor constant:-kPad],
        [scan.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor],
        [scan.widthAnchor constraintEqualToConstant:114.0],
        [scan.heightAnchor constraintEqualToConstant:38.0],
    ]];

    // 三行：服务开关 / 广域网 / 未连接设备（对应反编译三组约束）
    UIView *r1 = [self row:@"服务开关" sub:@"允许局域网电脑接入当前设备"
                     tint:YkTintBlue() icon:@"bolt.fill" trailing:@"switch"];
    UIView *r2 = [self row:@"广域网" sub:@"允许外网通过安全隧道接入当前设备"
                     tint:YkTintGray() icon:@"globe" trailing:@"switch"];
    UIView *r3 = [self row:@"未连接设备" sub:@"当前暂无电脑接入"
                     tint:YkTintGray() icon:@"display" trailing:@"pill"];

    [NSLayoutConstraint activateConstraints:@[
        [r1.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:kPad],
        [r2.topAnchor constraintEqualToAnchor:r1.bottomAnchor constant:kPad],
        [r3.topAnchor constraintEqualToAnchor:r2.bottomAnchor constant:kPad],
        [r3.bottomAnchor constraintEqualToAnchor:_heroCard.bottomAnchor constant:-kPad],
    ]];
}

- (UIView *)row:(NSString *)title sub:(NSString *)sub
           tint:(UIColor *)tint icon:(NSString *)sym trailing:(NSString *)kind {
    UIView *row = [UIView new];
    row.backgroundColor = tint;
    row.layer.cornerRadius = 14;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [_heroCard addSubview:row];

    UIView *badge = [self badge:sym bg:[UIColor colorWithWhite:1 alpha:0.9] tint:YkBlue() round:YES];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:badge];

    UILabel *t = [UILabel new];
    t.text = title;
    t.font = [UIFont boldSystemFontOfSize:17];
    t.textColor = YkTitle();
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:t];

    UILabel *s = [UILabel new];
    s.text = sub;
    s.font = [UIFont systemFontOfSize:12];
    s.textColor = YkSub();
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:s];

    NSMutableArray *c = [NSMutableArray arrayWithArray:@[
        [row.leadingAnchor constraintEqualToAnchor:_heroCard.leadingAnchor constant:kGutter],
        [row.trailingAnchor constraintEqualToAnchor:_heroCard.trailingAnchor constant:-kGutter],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:kBadge + 24.0],   // 52 + 24
        [badge.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14.0],
        [badge.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [badge.widthAnchor constraintEqualToConstant:kBadge],
        [badge.heightAnchor constraintEqualToConstant:kBadge],
        [t.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:kPad],
        [t.topAnchor constraintEqualToAnchor:badge.topAnchor constant:2.0],
        [s.leadingAnchor constraintEqualToAnchor:t.leadingAnchor],
        [s.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:2.0],
    ]];

    if ([kind isEqualToString:@"switch"]) {
        UISwitch *sw = [UISwitch new];
        sw.onTintColor = YkBlue();
        sw.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:sw];
        [c addObjectsFromArray:@[
            [sw.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14.0],
            [sw.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [t.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-8.0],
        ]];
    } else {
        UILabel *p = [UILabel new];
        p.text = @"待接入";
        p.font = [UIFont systemFontOfSize:13];
        p.textColor = YkSub();
        p.textAlignment = NSTextAlignmentCenter;
        p.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1];
        p.layer.cornerRadius = 17;
        p.layer.masksToBounds = YES;
        p.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:p];
        [c addObjectsFromArray:@[
            [p.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14.0],
            [p.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [p.widthAnchor constraintEqualToConstant:84.0],
            [p.heightAnchor constraintEqualToConstant:34.0],
            [t.trailingAnchor constraintLessThanOrEqualToAnchor:p.leadingAnchor constant:-8.0],
        ]];
    }
    [NSLayoutConstraint activateConstraints:c];
    return row;
}

#pragma mark - segmentControl（反编译 segmentControl）

- (void)buildSegmentControl {
    _segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"设备", @"脚本", @"录制"]];
    _segmentControl.selectedSegmentIndex = 0;
    _segmentControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:_segmentControl];
    [_segmentControl.heightAnchor constraintEqualToConstant:kRowBase].active = YES;
}

#pragma mark - bottomBar（反编译 bottomBar）

- (void)buildBottomBar {
    _bottomBar = [UIView new];
    _bottomBar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.97];
    _bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_bottomBar];

    NSArray *tabs = @[ @[@"iphone", @"设备"], @[@"terminal", @"脚本"], @[@"record.circle", @"录制"] ];
    NSMutableArray *cols = [NSMutableArray array];
    for (NSUInteger i = 0; i < tabs.count; i++) {
        BOOL sel = (i == 0);
        UIColor *c = sel ? YkBlue() : YkSub();
        UIButton *col = [UIButton buttonWithType:UIButtonTypeCustom];
        col.translatesAutoresizingMaskIntoConstraints = NO;
        [col setImage:[UIImage systemImageNamed:tabs[i][0]] forState:UIControlStateNormal];
        [col setTitle:tabs[i][1] forState:UIControlStateNormal];
        col.tintColor = c;
        [col setTitleColor:c forState:UIControlStateNormal];
        col.titleLabel.font = [UIFont systemFontOfSize:12];
        col.contentEdgeInsets = UIEdgeInsetsMake(0, 0, -18, 0);
        [_bottomBar addSubview:col];
        [cols addObject:col];
    }

    UIView *c0 = cols[0], *c1 = cols[1], *c2 = cols[2];
    [NSLayoutConstraint activateConstraints:@[
        [c0.leadingAnchor constraintEqualToAnchor:_bottomBar.leadingAnchor],
        [c0.widthAnchor constraintEqualToAnchor:_bottomBar.widthAnchor multiplier:1.0 / 3.0],
        [c1.leadingAnchor constraintEqualToAnchor:c0.trailingAnchor],
        [c1.widthAnchor constraintEqualToAnchor:c0.widthAnchor],
        [c2.leadingAnchor constraintEqualToAnchor:c1.trailingAnchor],
        [c2.widthAnchor constraintEqualToAnchor:c0.widthAnchor],
    ]];
    for (UIView *col in cols) {
        [NSLayoutConstraint activateConstraints:@[
            [col.topAnchor constraintEqualToAnchor:_bottomBar.topAnchor],
            [col.heightAnchor constraintEqualToConstant:70.0],
        ]];
    }
}

#pragma mark - 总约束

- (void)installConstraints {
    [NSLayoutConstraint activateConstraints:@[
        [_headerView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_headerView.heightAnchor constraintEqualToConstant:88.0],

        [_scrollView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_bottomBar.topAnchor],

        [_contentStack.topAnchor constraintEqualToAnchor:_scrollView.topAnchor constant:kPad],
        [_contentStack.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor constant:kGutter],
        [_contentStack.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor constant:-kGutter],
        [_contentStack.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor constant:-kPad],
        [_contentStack.widthAnchor constraintEqualToAnchor:_scrollView.widthAnchor
                                               constant:-(kGutter * 2)],

        [_bottomBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_bottomBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_bottomBar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_bottomBar.heightAnchor constraintEqualToConstant:88.0],
    ]];
}

#pragma mark - 通用

- (UIView *)badge:(NSString *)sym bg:(UIColor *)bg tint:(UIColor *)tint round:(BOOL)round {
    UIView *box = [UIView new];
    box.backgroundColor = bg;
    box.layer.cornerRadius = round ? 19.0 : 12.0;
    UIImageView *iv = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:sym withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold]]];
    iv.tintColor = tint;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:iv];
    [NSLayoutConstraint activateConstraints:@[
        [iv.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
    ]];
    return box;
}

@end
