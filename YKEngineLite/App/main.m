//  YKRootVC — 按设备实拍 1:1 复刻原版「远控 Pro」首页
//  基准：live/ykpro_ui.png（750×1334 @2x = 375×667pt）
//  蓝色导航栏 + 卡片1「连接设备」(扫码连接/服务开关/广域网/未连接设备) +
//  卡片2「运行状态」(设备IP | 越狱方式) + 底部 Tab(设备/脚本/录制)
#import <UIKit/UIKit.h>
#import <signal.h>

static UIColor *YkBlue(void)     { return [UIColor colorWithRed:0.13 green:0.60 blue:0.95 alpha:1]; }
static UIColor *YkPageBg(void)   { return [UIColor colorWithRed:0.96 green:0.965 blue:0.97 alpha:1]; }
static UIColor *YkTintBlue(void) { return [UIColor colorWithRed:0.91 green:0.95 blue:1.0 alpha:1]; }
static UIColor *YkTintGray(void) { return [UIColor colorWithRed:0.94 green:0.945 blue:0.95 alpha:1]; }
static UIColor *YkTintRed(void)  { return [UIColor colorWithRed:0.99 green:0.93 blue:0.92 alpha:1]; }
static UIColor *YkTintPurple(void){ return [UIColor colorWithRed:0.93 green:0.92 blue:0.99 alpha:1]; }
static UIColor *YkText(void)     { return [UIColor colorWithRed:0.09 green:0.10 blue:0.12 alpha:1]; }
static UIColor *YkSubText(void)  { return [UIColor colorWithRed:0.55 green:0.57 blue:0.60 alpha:1]; }

@interface UIView (Yk)
+ (instancetype)yk_card;
@end
@implementation UIView (Yk)
+ (instancetype)yk_card {
    UIView *v = [UIView new];
    v.backgroundColor = [UIColor whiteColor];
    v.layer.cornerRadius = 18;
    v.layer.shadowColor = [UIColor blackColor].CGColor;
    v.layer.shadowOpacity = 0.05;
    v.layer.shadowRadius = 10;
    v.layer.shadowOffset = CGSizeMake(0, 4);
    return v;
}
@end

static UILabel *YkLabel(NSString *t, CGFloat s, BOOL b, UIColor *c) {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = b ? [UIFont boldSystemFontOfSize:s] : [UIFont systemFontOfSize:s];
    l.textColor = c;
    return l;
}
static UIImageView *YkIcon(NSString *sym, CGFloat size, UIColor *tint) {
    UIImageView *iv = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:sym withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold]]];
    iv.tintColor = tint;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    return iv;
}
static UIView *YkBadge(NSString *sym, UIColor *bg, UIColor *tint, CGFloat side, BOOL round) {
    UIView *box = [UIView new];
    box.backgroundColor = bg;
    box.frame = CGRectMake(0, 0, side, side);
    box.layer.cornerRadius = round ? side / 2.0 : side * 0.32;
    UIImageView *iv = YkIcon(sym, side * 0.5, tint);
    iv.frame = CGRectMake(side * 0.25, side * 0.25, side * 0.5, side * 0.5);
    [box addSubview:iv];
    return box;
}
static UILabel *YkPill(NSString *t, UIColor *bg, UIColor *fg, CGFloat h) {
    UILabel *l = YkLabel(t, 13, YES, fg);
    l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = bg;
    l.layer.cornerRadius = h / 2.0;
    l.layer.masksToBounds = YES;
    return l;
}

@interface YKRootVC : UIViewController
@end

@implementation YKRootVC {
    UIScrollView *_scroll;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = YkPageBg();
    const CGFloat W = [UIScreen mainScreen].bounds.size.width;

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, W, 667 - 108)];
    _scroll.contentSize = CGSizeMake(W, 610);
    _scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:_scroll];

    // ---------- 卡片1 ----------
    UIView *card1 = [UIView yk_card];
    card1.frame = CGRectMake(12, 14, W - 24, 340);
    [_scroll addSubview:card1];

    UIView *hIcon = YkBadge(@"dot.radiowaves.left.and.right", YkTintBlue(), YkBlue(), 38, YES);
    hIcon.frame = CGRectMake(16, 16, 38, 38);
    [card1 addSubview:hIcon];

    UILabel *hTitle = YkLabel(@"连接设备", 21, YES, YkText());
    hTitle.frame = CGRectMake(66, 21, 170, 26);
    [card1 addSubview:hTitle];

    UIView *scan = [UIView new];
    scan.frame = CGRectMake(card1.bounds.size.width - 130, 16, 114, 38);
    scan.backgroundColor = YkTintBlue();
    scan.layer.cornerRadius = 10;
    [card1 addSubview:scan];
    UIImageView *qr = YkIcon(@"qrcode.viewfinder", 17, YkBlue());
    qr.frame = CGRectMake(10, 10, 18, 18);
    [scan addSubview:qr];
    UILabel *scanT = YkLabel(@"扫码连接", 14, YES, YkBlue());
    scanT.frame = CGRectMake(32, 9, 76, 20);
    [scan addSubview:scanT];

    [self rowIn:card1 y:70  tint:YkTintBlue() icon:@"bolt.fill" title:@"服务开关"
        subtitle:@"允许局域网电脑接入当前设备" on:1 pill:nil];
    [self rowIn:card1 y:158 tint:YkTintGray() icon:@"globe" title:@"广域网"
        subtitle:@"允许外网通过安全隧道接入当前设备" on:0 pill:nil];
    [self rowIn:card1 y:246 tint:YkTintGray() icon:@"display" title:@"未连接设备"
        subtitle:@"当前暂无电脑接入" on:-1 pill:@"待接入"];

    // ---------- 卡片2 ----------
    UIView *card2 = [UIView yk_card];
    card2.frame = CGRectMake(12, 366, W - 24, 200);
    [_scroll addSubview:card2];

    UIView *sIcon = YkBadge(@"square.grid.2x2.fill", YkTintPurple(),
                            [UIColor colorWithRed:0.45 green:0.36 blue:0.95 alpha:1], 38, NO);
    sIcon.frame = CGRectMake(16, 16, 38, 38);
    [card2 addSubview:sIcon];
    UILabel *sTitle = YkLabel(@"运行状态", 21, YES, YkText());
    sTitle.frame = CGRectMake(66, 21, 200, 26);
    [card2 addSubview:sTitle];

    [self statIn:card2 frame:CGRectMake(16, 74, 156, 92) bg:YkTintBlue()
            icon:@"wifi" tint:YkBlue() caption:@"设备 IP" value:[self deviceIP]];
    [self statIn:card2 frame:CGRectMake(182, 74, 156, 92) bg:YkTintRed()
            icon:@"lock.fill" tint:[UIColor colorWithRed:0.90 green:0.35 blue:0.30 alpha:1]
         caption:@"越狱方式" value:@"隐根"];

    [self buildTabBar:W];
}

- (NSString *)deviceIP {
    NSString *ip = [[NSUserDefaults standardUserDefaults] stringForKey:@"ykIP"];
    return ip.length ? ip : @"192.168.1.43";
}

- (void)rowIn:(UIView *)card y:(CGFloat)y tint:(UIColor *)tint icon:(NSString *)sym
        title:(NSString *)title subtitle:(NSString *)subtitle on:(NSInteger)on pill:(NSString *)pill {
    UIView *row = [UIView new];
    row.frame = CGRectMake(12, y, card.bounds.size.width - 24, 78);
    row.backgroundColor = tint;
    row.layer.cornerRadius = 14;
    [card addSubview:row];

    UIView *badge = YkBadge(sym, [UIColor colorWithWhite:1 alpha:0.9], YkBlue(), 44, YES);
    badge.frame = CGRectMake(14, 17, 44, 44);
    [row addSubview:badge];

    UILabel *t = YkLabel(title, 17, YES, YkText());
    t.frame = CGRectMake(70, 15, 180, 22);
    [row addSubview:t];

    UILabel *s = YkLabel(subtitle, 12, NO, YkSubText());
    s.frame = CGRectMake(70, 40, 190, 18);
    [row addSubview:s];

    if (on >= 0) {
        UISwitch *sw = [UISwitch new];
        sw.on = (on == 1);
        sw.onTintColor = YkBlue();
        sw.frame = CGRectMake(row.bounds.size.width - 66, 23, 51, 31);
        [row addSubview:sw];
    } else if (pill.length) {
        UILabel *p = YkPill(pill, [UIColor colorWithWhite:0.92 alpha:1], YkSubText(), 34);
        p.frame = CGRectMake(row.bounds.size.width - 96, 22, 84, 34);
        [row addSubview:p];
    }
}

- (void)statIn:(UIView *)card frame:(CGRect)f bg:(UIColor *)bg icon:(NSString *)sym
          tint:(UIColor *)tint caption:(NSString *)caption value:(NSString *)value {
    UIView *box = [UIView new];
    box.frame = f;
    box.backgroundColor = bg;
    box.layer.cornerRadius = 14;
    [card addSubview:box];

    UIImageView *iv = YkIcon(sym, 16, tint);
    iv.frame = CGRectMake(14, 14, 20, 20);
    [box addSubview:iv];

    UILabel *c = YkLabel(caption, 13, NO, YkSubText());
    c.frame = CGRectMake(42, 14, 110, 20);
    [box addSubview:c];

    UILabel *v = YkLabel(value, 22, YES, YkText());
    v.frame = CGRectMake(14, 44, f.size.width - 28, 30);
    [box addSubview:v];
}

- (void)buildTabBar:(CGFloat)W {
    UIView *bar = [UIView new];
    bar.frame = CGRectMake(0, 667 - 96, W, 96);
    bar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.97];
    [self.view addSubview:bar];

    NSArray *tabs = @[ @[@"iphone", @"设备"], @[@"terminal", @"脚本"], @[@"record.circle", @"录制"] ];
    for (NSUInteger i = 0; i < tabs.count; i++) {
        BOOL sel = (i == 0);
        UIColor *c = sel ? YkBlue() : YkSubText();
        if (sel) {
            UIView *pill = [UIView new];
            pill.frame = CGRectMake(W / 3 * i + W / 6 - 44, 8, 88, 60);
            pill.backgroundColor = YkTintBlue();
            pill.layer.cornerRadius = 26;
            [bar addSubview:pill];
        }
        UIImageView *iv = YkIcon(tabs[i][0], 24, c);
        iv.frame = CGRectMake(W / 3 * i + W / 6 - 12, 16, 24, 26);
        [bar addSubview:iv];
        UILabel *l = YkLabel(tabs[i][1], 12, sel, c);
        l.textAlignment = NSTextAlignmentCenter;
        l.frame = CGRectMake(W / 3 * i, 44, W / 3, 18);
        [bar addSubview:l];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
@end

@interface YKAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation YKAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    YKRootVC *root = [YKRootVC new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.navigationBar.translucent = NO;
    nav.navigationBar.barTintColor = YkBlue();
    nav.navigationBar.backgroundColor = YkBlue();
    [nav.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    nav.navigationBar.shadowImage = [UIImage new];
    nav.navigationBar.titleTextAttributes = @{ NSForegroundColorAttributeName: [UIColor whiteColor],
                                               NSFontAttributeName: [UIFont boldSystemFontOfSize:24] };
    root.navigationItem.title = @"远控 Pro";
    UIBarButtonItem *home = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"house.fill"]
                                                            style:UIBarButtonItemStylePlain
                                                           target:nil action:nil];
    home.tintColor = [UIColor whiteColor];
    root.navigationItem.leftBarButtonItem = home;

    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([YKAppDelegate class]));
    }
}
