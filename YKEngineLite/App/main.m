//  YKViewYyyy — 按反编译数值重建的首页（约束版）
//
//  数值来源：dump/project_rn/YKApp/YKViewYyyy.m（Ghidra 伪代码）
//    · 301 条 NSLayoutConstraint / 18 组 activateConstraints
//    · 72 个视图 setTranslatesAutoresizingMaskIntoConstraints:NO
//    · 间距（IEEE754 还原）：12 / 16 / 20 / 24 / 40 / 44 / 52，全部 4pt 栅格
//    · 行高 = 内容高 + 44（in_d3 + 44.0）
//    · constraintEqualToAnchor:multiplier: 用于两栏 1:1 与 Tab 1:3
//
//  元素清单：7 图标 · 18 文本 · 8 圆角 · 5 显隐
#import <UIKit/UIKit.h>
#import <signal.h>
#import "YKHTTPServerCompat.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <string.h>

static const CGFloat kGutter  = 12.0;   // 卡片左右外边距
static const CGFloat kPad     = 16.0;   // 卡片内边距
static const CGFloat kGap     = 16.0;   // 行间距
static const CGFloat kRowBase = 44.0;   // 行高基准
static const CGFloat kBadge   = 52.0;   // 图标块边长
static const CGFloat kCardTop = 14.0;

static UIColor *YkBlue(void)      { return [UIColor colorWithRed:0.13 green:0.60 blue:0.95 alpha:1]; }
static UIColor *YkPageBg(void)    { return [UIColor colorWithWhite:0.96 alpha:1]; }
static UIColor *YkTintBlue(void)  { return [UIColor colorWithRed:0.91 green:0.95 blue:1.0 alpha:1]; }
static UIColor *YkTintGray(void)  { return [UIColor colorWithWhite:0.94 alpha:1]; }
static UIColor *YkTintRed(void)   { return [UIColor colorWithRed:0.99 green:0.93 blue:0.92 alpha:1]; }
static UIColor *YkTintPurple(void){ return [UIColor colorWithRed:0.93 green:0.92 blue:0.99 alpha:1]; }
static UIColor *YkTitle(void)     { return [UIColor colorWithWhite:0.09 alpha:1]; }
static UIColor *YkSub(void)       { return [UIColor colorWithWhite:0.60 alpha:1]; }


// 真实 Wi-Fi 地址（en0）——对应 YKPhoneDevice 的取 IP 逻辑
static NSString *YkDeviceIP(void) {
    struct ifaddrs *ifa = NULL;
    if (getifaddrs(&ifa) != 0) return @"—";
    NSString *ip = nil;
    for (struct ifaddrs *p = ifa; p; p = p->ifa_next) {
        if (!p->ifa_addr || p->ifa_addr->sa_family != AF_INET) continue;
        if (strncmp(p->ifa_name, "en", 2) != 0) continue;
        char buf[INET_ADDRSTRLEN] = {0};
        struct sockaddr_in *sin = (struct sockaddr_in *)p->ifa_addr;
        if (inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf))) { ip = @(buf); break; }
    }
    freeifaddrs(ifa);
    return ip.length ? ip : @"—";
}

// 越狱形态探测：/.jbroot → 隐根(roothide)，/var/jb → 无根(rootless)，否则 有根
static NSString *YkJBType(void) {
    // 沙箱内 / 根路径不可见，先用自身 bundle 路径判断（roothide 特征 .jbroot-XXXX）
    NSString *bp = [NSBundle mainBundle].bundlePath ?: @"";
    if ([bp rangeOfString:@".jbroot"].location != NSNotFound) return @"隐根";
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:@"/var/jb"]) return @"无根";
    if ([fm fileExistsAtPath:@"/.jbroot"]) return @"隐根";
    return @"有根";
}

static UILabel *YkLabel(NSString *t, CGFloat size, UIFontWeight w, UIColor *c) {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = [UIFont systemFontOfSize:size weight:w];
    l.textColor = c;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    return l;
}
static UIImageView *YkIcon(NSString *sym, CGFloat size, UIColor *tint) {
    UIImageView *iv = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:sym withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold]]];
    iv.tintColor = tint;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    return iv;
}

#pragma mark - 列表页（脚本 / 录制）

@interface YKListVC : UITableViewController
@property (nonatomic, copy) NSString *endpoint;     // /executor/scripts 或 /record/tasks
@property (nonatomic, copy) NSString *rowAction;    // /executor/run 或 /record/start
@property (nonatomic, copy) NSString *listKey;      // scripts 或 tasks
@property (nonatomic, strong) NSArray *items;
@end

@implementation YKListVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = YkPageBg();
    self.tableView.tableFooterView = [UIView new];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(load)];
    if (self.rowAction) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(doAction)];
    }
    [self load];
}

- (NSString *)base { return [NSString stringWithFormat:@"http://127.0.0.1:%u", 65324]; }

- (void)load {
    NSURL *u = [NSURL URLWithString:[self.base stringByAppendingString:self.endpoint]];
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:u completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        NSArray *list = j[@"value"][self.listKey];
        if (![list isKindOfClass:[NSArray class]]) list = @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.items = list;
            [weakSelf.tableView reloadData];
        });
    }] resume];
}

- (void)doAction {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[self.base stringByAppendingString:self.rowAction]]];
    req.HTTPMethod = @"POST";
    req.HTTPBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf load]; });
    }] resume];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    NSDictionary *it = self.items[ip.row];
    c.textLabel.text = it[@"name"] ?: it[@"taskId"] ?: @"—";
    c.detailTextLabel.text = it[@"state"] ?: it[@"scriptId"] ?: @"";
    c.detailTextLabel.textColor = YkSub();
    return c;
}

@end

@interface YKRootVC : UIViewController
@end

@implementation YKRootVC {
    UIScrollView *_scroll;
    UIView *_stack;
    HTTPServer *_srv;
    NSTimer *_poller;
    UILabel *_connValue;
    UISwitch *_serviceSwitch;
    UILabel *_connTitle;
    UILabel *_connPill;
    NSMutableArray *_sessions;
    NSMutableArray *_scripts;
    NSMutableArray *_records;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = YkPageBg();

    _scroll = [UIScrollView new];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:_scroll];

    // 状态栏区域铺蓝色（原版蓝底延伸到屏幕顶端）
    UIView *statusBg = [UIView new];
    statusBg.translatesAutoresizingMaskIntoConstraints = NO;
    statusBg.backgroundColor = YkBlue();
    [self.view addSubview:statusBg];
    [NSLayoutConstraint activateConstraints:@[
        [statusBg.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [statusBg.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [statusBg.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [statusBg.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    ]];

    _stack = [UIView new];
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_stack];
    _scroll.contentInset = UIEdgeInsetsMake(0, 0, 96.0, 0);

    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-(96.0 + 8.0)],

        [_stack.topAnchor constraintEqualToAnchor:_scroll.topAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:_scroll.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:_scroll.trailingAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:_scroll.bottomAnchor],
        [_stack.widthAnchor constraintEqualToAnchor:_scroll.widthAnchor],
    ]];

    UIView *card1 = [self card];
    UIView *card2 = [self card];
    [_stack addSubview:card1];
    [_stack addSubview:card2];

    [NSLayoutConstraint activateConstraints:@[
        [card1.topAnchor constraintEqualToAnchor:_stack.topAnchor constant:kCardTop],
        [card1.leadingAnchor constraintEqualToAnchor:_stack.leadingAnchor constant:kGutter],
        [card1.trailingAnchor constraintEqualToAnchor:_stack.trailingAnchor constant:-kGutter],

        [card2.topAnchor constraintEqualToAnchor:card1.bottomAnchor constant:kGap],
        [card2.leadingAnchor constraintEqualToAnchor:card1.leadingAnchor],
        [card2.trailingAnchor constraintEqualToAnchor:card1.trailingAnchor],
        [card2.bottomAnchor constraintEqualToAnchor:_stack.bottomAnchor constant:-(96.0 + 40.0)],
    ]];

    [self buildCard1:card1];
    [self buildCard2:card2];
    [self buildTabBar];

}

- (UIView *)card {
    UIView *v = [UIView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.backgroundColor = [UIColor whiteColor];
    v.layer.cornerRadius = 18.0;
    v.layer.shadowColor = [UIColor blackColor].CGColor;
    v.layer.shadowOpacity = 0.05;
    v.layer.shadowRadius = 10;
    v.layer.shadowOffset = CGSizeMake(0, 4);
    return v;
}

- (UIView *)badgeWith:(NSString *)sym bg:(UIColor *)bg tint:(UIColor *)tint round:(BOOL)round {
    UIView *box = [UIView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.backgroundColor = bg;
    box.layer.cornerRadius = round ? 19.0 : 12.0;
    UIImageView *iv = YkIcon(sym, 19, tint);
    [box addSubview:iv];
    [NSLayoutConstraint activateConstraints:@[
        [iv.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
    ]];
    return box;
}

- (UIView *)scanButton {
    UIView *v = [UIView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.backgroundColor = YkTintBlue();
    v.layer.cornerRadius = 10.0;
    UIImageView *iv = YkIcon(@"qrcode.viewfinder", 17, YkBlue());
    UILabel *l = YkLabel(@"扫码连接", 14, UIFontWeightBold, YkBlue());
    [v addSubview:iv];
    [v addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [iv.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:10.0],
        [iv.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
        [l.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:4.0],
        [l.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
        [l.trailingAnchor constraintLessThanOrEqualToAnchor:v.trailingAnchor constant:-10.0],
    ]];
    return v;
}

- (void)buildCard1:(UIView *)card {
    UIView *badge = [self badgeWith:@"dot.radiowaves.left.and.right" bg:YkTintBlue() tint:YkBlue() round:YES];
    UILabel *title = YkLabel(@"连接设备", 21, UIFontWeightBold, YkTitle());
    UIView *scan = [self scanButton];
    scan.userInteractionEnabled = YES;
    [scan addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openScan)]];
    [card addSubview:badge];
    [card addSubview:title];
    [card addSubview:scan];

    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:kPad],
        [badge.topAnchor constraintEqualToAnchor:card.topAnchor constant:kPad],
        [badge.widthAnchor constraintEqualToConstant:38.0],
        [badge.heightAnchor constraintEqualToConstant:38.0],
        [title.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
        [title.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [scan.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-kPad],
        [scan.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [scan.widthAnchor constraintEqualToConstant:114.0],
        [scan.heightAnchor constraintEqualToConstant:38.0],
    ]];

    UIView *r1 = [self row:card yAnchor:badge.bottomAnchor gap:kGap tint:YkTintBlue()
                       icon:@"bolt.fill" title:@"服务开关"
                   subtitle:@"允许局域网电脑接入当前设备" on:YES pill:nil];
    UIView *r2 = [self row:card yAnchor:r1.bottomAnchor gap:kGap tint:YkTintGray()
                       icon:@"globe" title:@"广域网"
                   subtitle:@"允许外网通过安全隧道接入当前设备" on:NO pill:nil];
    UIView *r3 = [self row:card yAnchor:r2.bottomAnchor gap:kGap tint:YkTintGray()
                       icon:@"display" title:@"未连接设备"
                   subtitle:@"当前暂无电脑接入" on:NO pill:@"待接入"];
    [card addConstraint:[r3.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-kPad]];
}

- (UIView *)row:(UIView *)card yAnchor:(NSLayoutAnchor *)yAnchor gap:(CGFloat)gap
          tint:(UIColor *)tint icon:(NSString *)sym title:(NSString *)title
      subtitle:(NSString *)subtitle on:(BOOL)on pill:(NSString *)pill {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = tint;
    row.layer.cornerRadius = 14.0;
    [card addSubview:row];

    UIView *badge = [self badgeWith:sym bg:[UIColor colorWithWhite:1 alpha:0.9] tint:YkBlue() round:YES];
    UILabel *t = YkLabel(title, 17, UIFontWeightBold, YkTitle());
    UILabel *s = YkLabel(subtitle, 12, UIFontWeightRegular, YkSub());
    if (pill.length) {
        _connTitle = t; _connValue = s;
        t.adjustsFontSizeToFitWidth = YES;
        t.minimumScaleFactor = 0.75;
    }
    [row addSubview:badge];
    [row addSubview:t];
    [row addSubview:s];

    NSMutableArray *c = [NSMutableArray arrayWithArray:@[
        [row.topAnchor constraintEqualToAnchor:yAnchor constant:gap],
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:kGutter],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-kGutter],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:kBadge + 24.0],

        [badge.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14.0],
        [badge.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [badge.widthAnchor constraintEqualToConstant:kBadge],
        [badge.heightAnchor constraintEqualToConstant:kBadge],

        [t.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:kGap],
        [t.topAnchor constraintEqualToAnchor:badge.topAnchor constant:2.0],
        [t.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-76.0],

        [s.leadingAnchor constraintEqualToAnchor:t.leadingAnchor],
        [s.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:2.0],
        [s.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-76.0],
    ]];

    if (pill.length) {
        UILabel *p = YkLabel(pill, 13, UIFontWeightSemibold, YkSub());
        _connPill = p;
        p.textAlignment = NSTextAlignmentCenter;
        p.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1];
        p.layer.cornerRadius = 17.0;
        p.layer.masksToBounds = YES;
        [row addSubview:p];
        [c addObjectsFromArray:@[
            [p.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14.0],
            [p.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [p.widthAnchor constraintEqualToConstant:84.0],
            [p.heightAnchor constraintEqualToConstant:34.0],
        ]];
    } else {
        UISwitch *sw = [UISwitch new];
        sw.translatesAutoresizingMaskIntoConstraints = NO;
        sw.tag = 2001;   // 服务开关
        _serviceSwitch = sw;
        sw.on = [[NSUserDefaults standardUserDefaults] objectForKey:@"ykServiceOn"]
                    ? [[NSUserDefaults standardUserDefaults] boolForKey:@"ykServiceOn"] : on;
        sw.onTintColor = YkBlue();
        [sw addTarget:self action:@selector(serviceToggled:) forControlEvents:UIControlEventValueChanged];
        [row addSubview:sw];
        [c addObjectsFromArray:@[
            [sw.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14.0],
            [sw.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];
    }
    [NSLayoutConstraint activateConstraints:c];
    return row;
}

- (void)buildCard2:(UIView *)card {
    UIView *badge = [self badgeWith:@"square.grid.2x2.fill" bg:YkTintPurple()
                               tint:[UIColor colorWithRed:0.45 green:0.36 blue:0.95 alpha:1] round:NO];
    UILabel *title = YkLabel(@"运行状态", 21, UIFontWeightBold, YkTitle());
    [card addSubview:badge];
    [card addSubview:title];

    UIView *t1 = [self statTile:@"wifi" tint:YkBlue() bg:YkTintBlue()
                        caption:@"设备 IP" value:YkDeviceIP()];
    UIView *t2 = [self statTile:@"lock.fill"
                           tint:[UIColor colorWithRed:0.90 green:0.35 blue:0.30 alpha:1]
                             bg:YkTintRed() caption:@"越狱方式" value:YkJBType()];
    [card addSubview:t1];
    [card addSubview:t2];

    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:kPad],
        [badge.topAnchor constraintEqualToAnchor:card.topAnchor constant:kPad],
        [badge.widthAnchor constraintEqualToConstant:38.0],
        [badge.heightAnchor constraintEqualToConstant:38.0],
        [title.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
        [title.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],

        [t1.topAnchor constraintEqualToAnchor:badge.bottomAnchor constant:kPad],
        [t1.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:kPad],
        [t1.heightAnchor constraintEqualToConstant:92.0],

        [t2.topAnchor constraintEqualToAnchor:t1.topAnchor],
        [t2.leadingAnchor constraintEqualToAnchor:t1.trailingAnchor constant:kGap],
        [t2.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-kPad],
        [t2.widthAnchor constraintEqualToAnchor:t1.widthAnchor],
        [t2.heightAnchor constraintEqualToAnchor:t1.heightAnchor],

        [t1.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-kPad],
        [t1.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-kPad],
    ]];
}

- (UIView *)statTile:(NSString *)sym tint:(UIColor *)tint bg:(UIColor *)bg
             caption:(NSString *)caption value:(NSString *)value {
    UIView *box = [UIView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.backgroundColor = bg;
    box.layer.cornerRadius = 14.0;

    UIImageView *iv = YkIcon(sym, 16, tint);
    UILabel *c = YkLabel(caption, 13, UIFontWeightRegular, YkSub());
    UILabel *v = YkLabel(value, 22, UIFontWeightBold, YkTitle());
    v.adjustsFontSizeToFitWidth = YES;
    v.minimumScaleFactor = 0.65;
    [box addSubview:iv];
    [box addSubview:c];
    [box addSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        [iv.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:14.0],
        [iv.topAnchor constraintEqualToAnchor:box.topAnchor constant:14.0],
        [c.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:8.0],
        [c.centerYAnchor constraintEqualToAnchor:iv.centerYAnchor],
        [v.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:14.0],
        [v.topAnchor constraintEqualToAnchor:c.bottomAnchor constant:12.0],
        [v.trailingAnchor constraintLessThanOrEqualToAnchor:box.trailingAnchor constant:-14.0],
    ]];
    return box;
}

- (void)buildTabBar {
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.97];
    [self.view addSubview:bar];

    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [bar.heightAnchor constraintEqualToConstant:96.0],
    ]];

    NSArray *tabs = @[ @[@"iphone", @"设备"], @[@"terminal", @"脚本"], @[@"record.circle", @"录制"] ];
    NSMutableArray *cols = [NSMutableArray array];
    for (NSUInteger i = 0; i < tabs.count; i++) {
        BOOL sel = (i == 0);
        UIColor *c = sel ? YkBlue() : YkSub();
        UIView *col = [UIView new];
        col.translatesAutoresizingMaskIntoConstraints = NO;
        col.tag = 3100 + i;
        col.userInteractionEnabled = YES;
        [col addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tabTapped:)]];
        [bar addSubview:col];

        UIImageView *iv = YkIcon(tabs[i][0], 24, c);
        UILabel *l = YkLabel(tabs[i][1], 12, sel ? UIFontWeightSemibold : UIFontWeightRegular, c);
        l.textAlignment = NSTextAlignmentCenter;
        [col addSubview:iv];
        [col addSubview:l];

        [NSLayoutConstraint activateConstraints:@[
            [iv.centerXAnchor constraintEqualToAnchor:col.centerXAnchor],
            [iv.topAnchor constraintEqualToAnchor:col.topAnchor constant:10.0],
            [l.centerXAnchor constraintEqualToAnchor:col.centerXAnchor],
            [l.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:4.0],
        ]];

        if (sel) {
            UIView *pill = [UIView new];
            pill.translatesAutoresizingMaskIntoConstraints = NO;
            pill.backgroundColor = YkTintBlue();
            pill.layer.cornerRadius = 26.0;
            [col insertSubview:pill atIndex:0];
            [NSLayoutConstraint activateConstraints:@[
                [pill.centerXAnchor constraintEqualToAnchor:col.centerXAnchor],
                [pill.topAnchor constraintEqualToAnchor:col.topAnchor],
                [pill.widthAnchor constraintEqualToConstant:88.0],
                [pill.heightAnchor constraintEqualToConstant:60.0],
            ]];
        }
        [cols addObject:col];
    }

    UIView *c0 = cols[0], *c1 = cols[1], *c2 = cols[2];
    NSMutableArray *cc = [NSMutableArray array];
    [cc addObject:[c0.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor]];
    [cc addObject:[c0.widthAnchor constraintEqualToAnchor:bar.widthAnchor multiplier:1.0 / 3.0]];
    [cc addObject:[c1.leadingAnchor constraintEqualToAnchor:c0.trailingAnchor]];
    [cc addObject:[c1.widthAnchor constraintEqualToAnchor:c0.widthAnchor]];
    [cc addObject:[c2.leadingAnchor constraintEqualToAnchor:c1.trailingAnchor]];
    [cc addObject:[c2.widthAnchor constraintEqualToAnchor:c0.widthAnchor]];
    for (UIView *col in cols) {
        [cc addObject:[col.topAnchor constraintEqualToAnchor:bar.topAnchor]];
        [cc addObject:[col.heightAnchor constraintEqualToConstant:70.0]];
    }
    [NSLayoutConstraint activateConstraints:cc];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    static BOOL fired = NO;
    if (fired) return;
    fired = YES;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL saved = [ud objectForKey:@"ykServiceOn"] ? [ud boolForKey:@"ykServiceOn"] : YES;
    if (!saved) return;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        YKRootVC *me = weakSelf; if (!me) return;
        if (me->_serviceSwitch.on) [me serviceToggled:me->_serviceSwitch];
    });
}

- (void)openScan {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"连接设备"
                                                               message:@"输入电脑端配对码"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"配对码"; }];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"连接" style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *a) {
        NSString *code = ac.textFields.firstObject.text ?: @"device";
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
            [NSURL URLWithString:@"http://127.0.0.1:65324/session/create"]];
        req.HTTPMethod = @"POST";
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"name": code } options:0 error:NULL];
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [[[NSURLSession sharedSession] dataTaskWithRequest:req
            completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {}] resume];
        (void)weakSelf;
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)tabTapped:(UITapGestureRecognizer *)g {
    NSInteger idx = g.view.tag - 3100;
    if (idx == 0) { [self.navigationController popToRootViewControllerAnimated:YES]; return; }
    YKListVC *vc = [YKListVC new];
    if (idx == 1) {
        vc.title = @"脚本";
        vc.endpoint = @"/executor/scripts";
        vc.listKey = @"scripts";
        vc.rowAction = @"/executor/run";
    } else {
        vc.title = @"录制";
        vc.endpoint = @"/record/tasks";
        vc.listKey = @"tasks";
        vc.rowAction = @"/record/start";
    }
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)serviceToggled:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"ykServiceOn"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (sw.isOn) {
        if (!_srv) {
            _srv = [HTTPServer new];
            _srv.port = 65324;
            _srv.interface = @"loopback";
            [_srv get:@"/health" withBlock:^(RouteRequest *req, RouteResponse *res) {
                [res respondWithJSON:@{ @"value": @{ @"state": @"ready", @"ready": @YES,
                                                     @"engine": @"reconstructed-inapp",
                                                     @"port": @65324,
                                                     @"sessionCount": @(_sessions.count) } }];
            }];
            // 会话生命周期（对齐原版 /session/create|list|delete）
            [_srv post:@"/session/create" withBlock:^(RouteRequest *req, RouteResponse *res) {
                NSString *sid = [NSString stringWithFormat:@"sess_%.0f_%@",
                                 [[NSDate date] timeIntervalSince1970] * 1000,
                                 [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""]];
                NSDictionary *sess = @{ @"sessionId": sid, @"state": @"active",
                                        @"name": req.jsonBody[@"name"] ?: @"Mac",
                                        @"createdAt": @([[NSDate date] timeIntervalSince1970]) };
                if (!_sessions) _sessions = [NSMutableArray array];
                [_sessions addObject:sess];
                [res respondWithJSON:@{ @"value": sess }];
            }];
            [_srv get:@"/session/list" withBlock:^(RouteRequest *req, RouteResponse *res) {
                [res respondWithJSON:@{ @"value": @{ @"count": @(_sessions.count),
                                                     @"sessions": _sessions ?: @[] } }];
            }];
            [_srv delete:@"/session/all" withBlock:^(RouteRequest *req, RouteResponse *res) {
                [_sessions removeAllObjects];
                [res respondWithJSON:@{ @"value": @YES }];
            }];
            // 脚本页数据源（对齐原版 /executor/scripts 结构）
            [_srv get:@"/executor/scripts" withBlock:^(RouteRequest *req, RouteResponse *res) {
                [res respondWithJSON:@{ @"value": @{ @"scripts": _scripts ?: @[], @"count": @(_scripts.count) } }];
            }];
            [_srv post:@"/executor/scripts/save" withBlock:^(RouteRequest *req, RouteResponse *res) {
                NSDictionary *b = req.jsonBody ?: @{};
                if (!_scripts) _scripts = [NSMutableArray array];
                NSDictionary *item = @{ @"name": b[@"name"] ?: @"未命名脚本",
                                        @"scriptId": [[NSUUID UUID] UUIDString],
                                        @"createdAt": @([[NSDate date] timeIntervalSince1970]) };
                [_scripts addObject:item];
                [res respondWithJSON:@{ @"value": item }];
            }];
            [_srv post:@"/executor/run" withBlock:^(RouteRequest *req, RouteResponse *res) {
                NSString *runId = [[NSUUID UUID] UUIDString];
                [res respondWithJSON:@{ @"value": @{ @"runId": runId, @"state": @"running",
                                                     @"startedAt": @([[NSDate date] timeIntervalSince1970]) } }];
            }];
            // 录制页数据源（对齐原版 /record/tasks 结构）
            [_srv get:@"/record/tasks" withBlock:^(RouteRequest *req, RouteResponse *res) {
                [res respondWithJSON:@{ @"value": @{ @"tasks": _records ?: @[], @"count": @(_records.count) } }];
            }];
            [_srv post:@"/record/start" withBlock:^(RouteRequest *req, RouteResponse *res) {
                if (!_records) _records = [NSMutableArray array];
                NSDictionary *t = @{ @"taskId": [[NSUUID UUID] UUIDString],
                                     @"state": @"recording",
                                     @"startedAt": @([[NSDate date] timeIntervalSince1970]) };
                [_records addObject:t];
                [res respondWithJSON:@{ @"value": t }];
            }];
            [_srv post:@"/record/stop" withBlock:^(RouteRequest *req, RouteResponse *res) {
                [_records removeAllObjects];
                [res respondWithJSON:@{ @"value": @YES }];
            }];
        }
        NSError *err = nil;
        BOOL ok = [_srv start:&err];
        NSLog(@"[YKEngineLite] engine start=%d err=%@", ok, err);
        [self startPolling];
    } else {
        [_srv stop]; _srv = nil;
        [_poller invalidate]; _poller = nil;
        _connValue.text = @"待接入";
        _connValue.textColor = YkSub();
    }
}

- (void)startPolling {
    if (_poller) return;
    __weak typeof(self) weakSelf = self;
    _poller = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        NSURL *u = [NSURL URLWithString:@"http://127.0.0.1:65324/session/list"];
        [[[NSURLSession sharedSession] dataTaskWithURL:u
            completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
                NSArray *list = j[@"value"][@"sessions"];
                if (![list isKindOfClass:[NSArray class]]) list = @[];
                dispatch_async(dispatch_get_main_queue(), ^{
                    YKRootVC *me = weakSelf; if (!me) return;
                    if (list.count) {
                        NSString *name = list.firstObject[@"name"] ?: @"Mac";
                        me->_connTitle.text = [NSString stringWithFormat:@"%@ · 已连接", name];
                        me->_connValue.text = @"远程控制中";
                        me->_connValue.textColor = YkBlue();
                        me->_connPill.text = @"已连接";
                        me->_connPill.textColor = YkBlue();
                        me->_connPill.backgroundColor = YkTintBlue();
                    } else {
                        me->_connTitle.text = @"未连接设备";
                        me->_connValue.text = @"当前暂无电脑接入";
                        me->_connValue.textColor = YkSub();
                        me->_connPill.text = @"待接入";
                        me->_connPill.textColor = YkSub();
                        me->_connPill.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1];
                    }
                });
            }] resume];
    }];
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
    nav.navigationBar.translucent = YES;
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
