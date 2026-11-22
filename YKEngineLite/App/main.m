//  YKEngineApp — 带图标的 App 外壳（与原版同构：SpringBoard 图标 + 进程内 HTTP 引擎）
#import <UIKit/UIKit.h>
#import <signal.h>

@interface YKRootVC : UIViewController
@end

@implementation YKRootVC {
    UILabel *_status, *_port, *_caps;
    UITextView *_log;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"远控 Pro · 重建版";
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.10 alpha:1];

    UILabel *head = [[UILabel alloc] initWithFrame:CGRectMake(20, 96, 335, 34)];
    head.text = @"远控 Pro";
    head.textColor = [UIColor whiteColor];
    head.font = [UIFont boldSystemFontOfSize:30];
    [self.view addSubview:head];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(20, 132, 335, 20)];
    sub.text = @"重建引擎 · YKEngineLite";
    sub.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    sub.font = [UIFont systemFontOfSize:13];
    [self.view addSubview:sub];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 168, 343, 104)];
    card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    card.layer.cornerRadius = 14;
    [self.view addSubview:card];

    _status = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, 311, 22)];
    _status.text = @"引擎状态：启动中…";
    _status.textColor = [UIColor colorWithRed:0.35 green:0.85 blue:0.55 alpha:1];
    _status.font = [UIFont boldSystemFontOfSize:16];
    [card addSubview:_status];

    _port = [[UILabel alloc] initWithFrame:CGRectMake(16, 38, 311, 20)];
    _port.textColor = [UIColor colorWithWhite:0.75 alpha:1];
    _port.font = [UIFont fontWithName:@"Menlo" size:12];
    [card addSubview:_port];

    _caps = [[UILabel alloc] initWithFrame:CGRectMake(16, 62, 311, 32)];
    _caps.text = @"file · prefs · plist · screen\ncrypto · network · ui  (589 路由已重建)";
    _caps.numberOfLines = 2;
    _caps.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    _caps.font = [UIFont systemFontOfSize:11];
    [card addSubview:_caps];

    _log = [[UITextView alloc] initWithFrame:CGRectMake(16, 288, 343, 460)];
    _log.backgroundColor = [UIColor colorWithWhite:1 alpha:0.04];
    _log.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    _log.font = [UIFont fontWithName:@"Menlo" size:11];
    _log.editable = NO;
    _log.layer.cornerRadius = 12;
    _log.text = @"[boot] YKEngineLite\n";
    [self.view addSubview:_log];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onLog:)
                                                 name:@"YKLog" object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"YKStartEngine" object:nil];
    [self refresh];
}

- (void)onLog:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_log.text = [self->_log.text stringByAppendingString:[n.object description]];
        self->_log.text = [self->_log.text stringByAppendingString:@"\n"];
    });
}

- (void)refresh {
    uint16_t port = (uint16_t)[[NSUserDefaults standardUserDefaults] integerForKey:@"ykPort"] ?: 0;
    _port.text = [NSString stringWithFormat:@"127.0.0.1:%u   POST /session/create", port];
    _status.text = port ? @"引擎状态：运行中" : @"引擎状态：未启动";
    _status.textColor = port ? [UIColor colorWithRed:0.35 green:0.85 blue:0.55 alpha:1]
                             : [UIColor colorWithRed:0.9 green:0.4 blue:0.35 alpha:1];
}
@end

@interface YKAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation YKAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[YKRootVC new]];
    nav.navigationBar.barStyle = UIBarStyleBlack;
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
