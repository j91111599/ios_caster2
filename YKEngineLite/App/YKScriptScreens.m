//  YKScriptView / YKScriptSettings / YKButtonView — 三屏按反编译结构实现
//
//  反编译依据（dump/UI_TREE.md）：
//   YKScriptView    36 组件 · 62 约束
//     navigationView / navigationHeightConstraint / scriptListStack / scriptRefreshButton
//     scriptRefreshIconView / httpServiceGridView / deviceUDID / lastHTTPStatus
//     openScriptSettings / openScriptScan / refreshRuntimeDashboard
//   YKScriptSettings 29 组件 · 50 约束
//     headerView / backgroundLayer / scrollView / scrollContentView
//     bootSwitch / floatingWindowRow / restartRow / vibrateRow / volumeShortcutRow
//     applyLocalSettings / fetchEngineSettings / updateBootSubtitle
//   YKButtonView    20 组件 · 47 约束
//     sheetView / closeButton / primaryButton / secondaryButton
//     progressView / progressWidthConstraint / progressPercentLabel
//     program / scriptName / downloadURL / displayName / showCheckingState

#import <UIKit/UIKit.h>

static const CGFloat kG2 = 12.0, kP2 = 16.0, kR2 = 44.0, kB2 = 52.0;

static UIColor *C_Blue(void)   { return [UIColor colorWithRed:0.13 green:0.60 blue:0.95 alpha:1]; }
static UIColor *C_Page(void)   { return [UIColor colorWithRed:0.96 green:0.96 blue:0.98 alpha:1.0]; }
static UIColor *C_TintB(void)  { return [UIColor colorWithRed:0.91 green:0.95 blue:1.0 alpha:1]; }
static UIColor *C_TintG(void)  { return [UIColor colorWithWhite:0.94 alpha:1]; }
static UIColor *C_Title(void)  { return [UIColor colorWithWhite:0.09 alpha:1]; }
static UIColor *C_Sub(void)    { return [UIColor colorWithWhite:0.60 alpha:1]; }

static UILabel *L(NSString *t, CGFloat s, UIFontWeight w, UIColor *c) {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = [UIFont systemFontOfSize:s weight:w];
    l.textColor = c;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    return l;
}
static NSString *GET(NSString *path) {
    NSData *d = [NSData dataWithContentsOfURL:[NSURL URLWithString:
        [@"http://127.0.0.1:65324" stringByAppendingString:path]]];
    if (!d) return @"";
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
}

#pragma mark - 脚本 Tab（YKScriptView）

@interface YKScriptView : UIViewController
@end

@implementation YKScriptView {
    UIView *_navigationView;
    UIView *_scriptListStack;
    UIButton *_scriptRefreshButton;
    UIView *_httpServiceGridView;
    UILabel *_deviceUDID;
    UILabel *_lastHTTPStatus;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = C_Page();

    // navigationView
    _navigationView = [UIView new];
    _navigationView.backgroundColor = C_Blue();
    _navigationView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_navigationView];

    UILabel *navTitle = L(@"脚本", 20, UIFontWeightBold, UIColor.whiteColor);
    [_navigationView addSubview:navTitle];

    // scriptRefreshButton + scriptRefreshIconView
    _scriptRefreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_scriptRefreshButton setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
    _scriptRefreshButton.tintColor = UIColor.whiteColor;
    _scriptRefreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_scriptRefreshButton addTarget:self action:@selector(refreshRuntimeDashboard)
                   forControlEvents:UIControlEventTouchUpInside];
    [_navigationView addSubview:_scriptRefreshButton];

    // deviceUDID
    _deviceUDID = L([self udid], 12, UIFontWeightRegular, C_Sub());

    // httpServiceGridView
    _httpServiceGridView = [UIView new];
    _httpServiceGridView.backgroundColor = UIColor.whiteColor;
    _httpServiceGridView.layer.cornerRadius = 14;
    _httpServiceGridView.translatesAutoresizingMaskIntoConstraints = NO;
    [_httpServiceGridView addSubview:_deviceUDID];

    // scriptListStack
    _scriptListStack = [UIView new];
    _scriptListStack.backgroundColor = UIColor.whiteColor;
    _scriptListStack.layer.cornerRadius = 14;
    _scriptListStack.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *empty = L(@"暂无脚本，点右上角刷新", 13, UIFontWeightRegular, C_Sub());
    [_scriptListStack addSubview:empty];

    // lastHTTPStatus
    _lastHTTPStatus = L(@"lastHTTPStatus: —", 11, UIFontWeightRegular, C_Sub());

    [self.view addSubview:_httpServiceGridView];
    [self.view addSubview:_scriptListStack];
    [self.view addSubview:_lastHTTPStatus];

    [NSLayoutConstraint activateConstraints:@[
        [_navigationView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_navigationView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_navigationView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_navigationView.heightAnchor constraintEqualToConstant:88.0],

        [navTitle.centerXAnchor constraintEqualToAnchor:_navigationView.centerXAnchor],
        [navTitle.bottomAnchor constraintEqualToAnchor:_navigationView.bottomAnchor constant:-10.0],

        [_scriptRefreshButton.trailingAnchor constraintEqualToAnchor:_navigationView.trailingAnchor constant:-kP2],
        [_scriptRefreshButton.centerYAnchor constraintEqualToAnchor:navTitle.centerYAnchor],
        [_scriptRefreshButton.widthAnchor constraintEqualToConstant:kR2],
        [_scriptRefreshButton.heightAnchor constraintEqualToConstant:kR2],

        [_httpServiceGridView.topAnchor constraintEqualToAnchor:_navigationView.bottomAnchor constant:kP2],
        [_httpServiceGridView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kG2],
        [_httpServiceGridView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kG2],
        [_httpServiceGridView.heightAnchor constraintEqualToConstant:88.0],

        [_deviceUDID.leadingAnchor constraintEqualToAnchor:_httpServiceGridView.leadingAnchor constant:kP2],
        [_deviceUDID.topAnchor constraintEqualToAnchor:_httpServiceGridView.topAnchor constant:kP2],

        [_scriptListStack.topAnchor constraintEqualToAnchor:_httpServiceGridView.bottomAnchor constant:kP2],
        [_scriptListStack.leadingAnchor constraintEqualToAnchor:_httpServiceGridView.leadingAnchor],
        [_scriptListStack.trailingAnchor constraintEqualToAnchor:_httpServiceGridView.trailingAnchor],
        [_scriptListStack.heightAnchor constraintGreaterThanOrEqualToConstant:120.0],

        [empty.leadingAnchor constraintEqualToAnchor:_scriptListStack.leadingAnchor constant:kP2],
        [empty.centerYAnchor constraintEqualToAnchor:_scriptListStack.centerYAnchor],

        [_lastHTTPStatus.topAnchor constraintEqualToAnchor:_scriptListStack.bottomAnchor constant:kG2],
        [_lastHTTPStatus.leadingAnchor constraintEqualToAnchor:_scriptListStack.leadingAnchor],
    ]];
}

- (NSString *)udid {
    return [NSString stringWithFormat:@"deviceUDID: %@",
            [[UIDevice currentDevice].identifierForVendor UUIDString] ?: @"—"];
}

// refreshRuntimeDashboard：拉取脚本列表 + 服务状态
- (void)refreshRuntimeDashboard {
    NSString *json = GET(@"/executor/scripts");
    _lastHTTPStatus.text = [NSString stringWithFormat:@"lastHTTPStatus: %@",
                            json.length ? @"200 OK" : @"—"];
    NSLog(@"[YKScriptView] scripts -> %@", json);
}

@end

#pragma mark - 脚本设置（YKScriptSettings）

@interface YKScriptSettings : UIViewController
@end

@implementation YKScriptSettings

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = C_Page();

    UIView *headerView = [UIView new];
    headerView.backgroundColor = C_Blue();
    headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:headerView];

    UILabel *title = L(@"脚本设置", 20, UIFontWeightBold, UIColor.whiteColor);
    [headerView addSubview:title];

    UIScrollView *scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = kP2;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:stack];

    // bootSwitch / floatingWindowRow / restartRow / vibrateRow / volumeShortcutRow
    [stack addArrangedSubview:[self rowWithTitle:@"开机启动" sub:@"开机后自动运行脚本" kind:@"switch"]];
    [stack addArrangedSubview:[self rowWithTitle:@"悬浮窗" sub:@"显示运行状态悬浮窗" kind:@"switch"]];
    [stack addArrangedSubview:[self rowWithTitle:@"震动反馈" sub:@"操作时震动提示" kind:@"switch"]];
    [stack addArrangedSubview:[self rowWithTitle:@"音量快捷键" sub:@"音量键触发脚本" kind:@"switch"]];
    [stack addArrangedSubview:[self rowWithTitle:@"重启引擎" sub:@"重新加载运行时" kind:@"button"]];

    [NSLayoutConstraint activateConstraints:@[
        [headerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [headerView.heightAnchor constraintEqualToConstant:88.0],

        [title.centerXAnchor constraintEqualToAnchor:headerView.centerXAnchor],
        [title.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor constant:-10.0],

        [scrollView.topAnchor constraintEqualToAnchor:headerView.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:kP2],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor constant:kG2],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor constant:-kG2],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:-kP2],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor constant:-(kG2 * 2)],
    ]];
}

- (UIView *)rowWithTitle:(NSString *)title sub:(NSString *)sub kind:(NSString *)kind {
    UIView *row = [UIView new];
    row.backgroundColor = UIColor.whiteColor;
    row.layer.cornerRadius = 14;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *t = L(title, 17, UIFontWeightBold, C_Title());
    UILabel *s = L(sub, 12, UIFontWeightRegular, C_Sub());
    [row addSubview:t];
    [row addSubview:s];

    NSMutableArray *c = [NSMutableArray arrayWithArray:@[
        [row.heightAnchor constraintEqualToConstant:kB2 + 24.0],
        [t.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:kP2],
        [t.topAnchor constraintEqualToAnchor:row.topAnchor constant:14.0],
        [s.leadingAnchor constraintEqualToAnchor:t.leadingAnchor],
        [s.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:2.0],
    ]];

    if ([kind isEqualToString:@"switch"]) {
        UISwitch *sw = [UISwitch new];
        sw.onTintColor = C_Blue();
        sw.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:sw];
        [c addObjectsFromArray:@[
            [sw.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-kP2],
            [sw.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];
    } else {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        [btn setTitle:@"重启" forState:UIControlStateNormal];
        btn.tintColor = C_Blue();
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:btn];
        [c addObjectsFromArray:@[
            [btn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-kP2],
            [btn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];
    }
    [NSLayoutConstraint activateConstraints:c];
    return row;
}

@end

#pragma mark - 安装弹层（YKButtonView）

@interface YKButtonView : UIViewController
@property (nonatomic, copy) NSString *scriptName;
@property (nonatomic, copy) NSString *downloadURL;
@end

@implementation YKButtonView {
    UIView *_sheetView;
    UIButton *_closeButton;
    UIButton *_primaryButton;
    UIButton *_secondaryButton;
    UIView *_progressView;
    NSLayoutConstraint *_progressWidthConstraint;
    UILabel *_progressPercentLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];

    _sheetView = [UIView new];
    _sheetView.backgroundColor = UIColor.whiteColor;
    _sheetView.layer.cornerRadius = 20;
    _sheetView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_sheetView];

    UILabel *t = L(self.scriptName ?: @"安装脚本", 20, UIFontWeightBold, C_Title());
    [_sheetView addSubview:t];

    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    _closeButton.tintColor = C_Sub();
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [_sheetView addSubview:_closeButton];

    _progressView = [UIView new];
    _progressView.backgroundColor = C_Blue();
    _progressView.layer.cornerRadius = 3;
    _progressView.translatesAutoresizingMaskIntoConstraints = NO;
    [_sheetView addSubview:_progressView];

    UIView *track = [UIView new];
    track.backgroundColor = C_TintG();
    track.layer.cornerRadius = 3;
    track.translatesAutoresizingMaskIntoConstraints = NO;
    [_sheetView addSubview:track];

    _progressPercentLabel = L(@"0%", 12, UIFontWeightRegular, C_Sub());
    [_sheetView addSubview:_progressPercentLabel];

    _primaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_primaryButton setTitle:@"开始安装" forState:UIControlStateNormal];
    _primaryButton.backgroundColor = C_Blue();
    [_primaryButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _primaryButton.layer.cornerRadius = 10;
    _primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_sheetView addSubview:_primaryButton];

    _secondaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_secondaryButton setTitle:@"稍后" forState:UIControlStateNormal];
    _secondaryButton.backgroundColor = C_TintG();
    [_secondaryButton setTitleColor:C_Title() forState:UIControlStateNormal];
    _secondaryButton.layer.cornerRadius = 10;
    _secondaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_secondaryButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [_sheetView addSubview:_secondaryButton];

    _progressWidthConstraint = [_progressView.widthAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [_sheetView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kG2],
        [_sheetView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kG2],
        [_sheetView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [t.leadingAnchor constraintEqualToAnchor:_sheetView.leadingAnchor constant:kP2],
        [t.topAnchor constraintEqualToAnchor:_sheetView.topAnchor constant:kP2],

        [_closeButton.trailingAnchor constraintEqualToAnchor:_sheetView.trailingAnchor constant:-kP2],
        [_closeButton.centerYAnchor constraintEqualToAnchor:t.centerYAnchor],
        [_closeButton.widthAnchor constraintEqualToConstant:kR2],
        [_closeButton.heightAnchor constraintEqualToConstant:kR2],

        [track.leadingAnchor constraintEqualToAnchor:_sheetView.leadingAnchor constant:kP2],
        [track.trailingAnchor constraintEqualToAnchor:_sheetView.trailingAnchor constant:-kP2],
        [track.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:kP2],
        [track.heightAnchor constraintEqualToConstant:6.0],

        [_progressView.leadingAnchor constraintEqualToAnchor:track.leadingAnchor],
        [_progressView.centerYAnchor constraintEqualToAnchor:track.centerYAnchor],
        [_progressView.heightAnchor constraintEqualToConstant:6.0],
        _progressWidthConstraint,

        [_progressPercentLabel.trailingAnchor constraintEqualToAnchor:track.trailingAnchor],
        [_progressPercentLabel.topAnchor constraintEqualToAnchor:track.bottomAnchor constant:6.0],

        [_primaryButton.leadingAnchor constraintEqualToAnchor:_sheetView.leadingAnchor constant:kP2],
        [_primaryButton.trailingAnchor constraintEqualToAnchor:_sheetView.trailingAnchor constant:-kP2],
        [_primaryButton.topAnchor constraintEqualToAnchor:_progressPercentLabel.bottomAnchor constant:kP2],
        [_primaryButton.heightAnchor constraintEqualToConstant:kR2],

        [_secondaryButton.leadingAnchor constraintEqualToAnchor:_primaryButton.leadingAnchor],
        [_secondaryButton.trailingAnchor constraintEqualToAnchor:_primaryButton.trailingAnchor],
        [_secondaryButton.topAnchor constraintEqualToAnchor:_primaryButton.bottomAnchor constant:kG2],
        [_secondaryButton.heightAnchor constraintEqualToConstant:kR2],
        [_secondaryButton.bottomAnchor constraintEqualToAnchor:_sheetView.bottomAnchor constant:-kP2],
    ]];
}

// showCheckingState / 进度更新
- (void)updateProgress:(CGFloat)p {
    _progressPercentLabel.text = [NSString stringWithFormat:@"%.0f%%", p * 100];
    [_progressWidthConstraint setActive:NO];
    CGFloat w = (self.view.bounds.size.width - kG2 * 2 - kP2 * 2) * p;
    _progressWidthConstraint = [_progressView.widthAnchor constraintEqualToConstant:w];
    _progressWidthConstraint.active = YES;
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

@end
