//  YKUIFlows.m —— App 内的交互流程（与原版一致）
//    · 扫码页：扫一扫连接设备 / 添加脚本（黑底 + 四角框 + 扫描线 + 相册识别 + 脚本码输入）
//    · 弹窗：修改设备名称 / 确定重启用户空间
//    · 系统动作：重启用户空间
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <spawn.h>

extern char **environ;

#define YK_BLUE [UIColor colorWithRed:0.141 green:0.631 blue:0.945 alpha:1.0]

#pragma mark - 通用弹窗

void YKAlert(UIViewController *host, NSString *title, NSString *message,
             NSArray<NSString *> *buttons, void (^onIndex)(NSInteger idx)) {
    if (!host) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                              message:message
                                                       preferredStyle:UIAlertControllerStyleAlert];
    for (NSInteger i = 0; i < (NSInteger)buttons.count; i++) {
        [a addAction:[UIAlertAction actionWithTitle:buttons[i]
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *x) {
            if (onIndex) onIndex(i);
        }]];
    }
    [host presentViewController:a animated:YES completion:nil];
}

void YKAlertRename(UIViewController *host, NSString *current, void (^onSave)(NSString *name)) {
    if (!host) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"修改设备名称"
                                                              message:nil
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = current ?: @"";
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleDefault handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *x) {
        UITextField *tf = a.textFields.firstObject;
        NSString *t = [tf.text stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length && onSave) onSave(t);
    }]];
    [host presentViewController:a animated:YES completion:nil];
}

void YKAlertRestart(UIViewController *host, void (^onConfirm)(void)) {
    YKAlert(host, @"确定重启用户空间?",
            @"该操作会重启用户空间，并断开当前 PC 连接。仅在远控服务或 SpringBoard 插件异常时使用。",
            @[@"取消", @"确定"], ^(NSInteger i) {
        if (i == 1 && onConfirm) onConfirm();
    });
}

#pragma mark - 系统动作

BOOL YKRequestRestartUserspace(void) {
    NSString *url = @"http://127.0.0.1:65325/system/respring";
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    r.HTTPMethod = @"POST";
    r.timeoutInterval = 2.0;
    r.HTTPBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    __block BOOL ok = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:r
        completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        ok = (e == nil);
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    if (ok) return YES;

    pid_t pid = 0;
    char *argv[] = { (char *)"/usr/bin/killall", (char *)"-9", (char *)"SpringBoard", NULL };
    int rc = posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, argv, environ);
    return rc == 0;
}

#pragma mark - 扫码 / 添加脚本页

@interface YKScanViewController : UIViewController <AVCaptureMetadataOutputObjectsDelegate,
                                                    UIImagePickerControllerDelegate,
                                                    UINavigationControllerDelegate>
@property (nonatomic, copy) NSString *pageTitle;
@property (nonatomic, copy) void (^onCode)(NSString *code);
@property (nonatomic, assign) BOOL scriptMode;
@end

@implementation YKScanViewController {
    AVCaptureSession *_session;
    AVCaptureVideoPreviewLayer *_preview;
    UIView *_scanBox;
    UIView *_scanLine;
    UILabel *_hint;
    UITextField *_codeField;
    BOOL _animating;
    BOOL _handled;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;

    UIView *nav = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 64)];
    nav.backgroundColor = YK_BLUE;
    [self.view addSubview:nav];

    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    back.frame = CGRectMake(4, 20, 44, 44);
    [back setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    back.tintColor = [UIColor whiteColor];
    [back addTarget:self action:@selector(ykBack) forControlEvents:UIControlEventTouchUpInside];
    [nav addSubview:back];

    UILabel *title = [UILabel new];
    title.text = self.pageTitle ?: @"扫一扫连接设备";
    title.font = [UIFont boldSystemFontOfSize:20];
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.frame = CGRectMake(0, 30, W, 26);
    [nav addSubview:title];

    CGFloat boxW = 240, boxH = 240;
    _scanBox = [[UIView alloc] initWithFrame:CGRectMake((W - boxW) / 2, 170, boxW, boxH)];
    _scanBox.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_scanBox];

    CAShapeLayer *corners = [CAShapeLayer layer];
    corners.frame = _scanBox.bounds;
    corners.strokeColor = YK_BLUE.CGColor;
    corners.fillColor = [UIColor clearColor].CGColor;
    corners.lineWidth = 4;
    corners.lineCap = kCALineCapRound;
    UIBezierPath *p = [UIBezierPath bezierPath];
    CGFloat L = 34;
    // 左上
    [p moveToPoint:CGPointMake(0, L)]; [p addLineToPoint:CGPointMake(0, 0)];
    [p addLineToPoint:CGPointMake(L, 0)];
    // 右上
    [p moveToPoint:CGPointMake(boxW - L, 0)]; [p addLineToPoint:CGPointMake(boxW, 0)];
    [p addLineToPoint:CGPointMake(boxW, L)];
    // 右下
    [p moveToPoint:CGPointMake(boxW, boxH - L)]; [p addLineToPoint:CGPointMake(boxW, boxH)];
    [p addLineToPoint:CGPointMake(boxW - L, boxH)];
    // 左下
    [p moveToPoint:CGPointMake(L, boxH)]; [p addLineToPoint:CGPointMake(0, boxH)];
    [p addLineToPoint:CGPointMake(0, boxH - L)];
    corners.path = p.CGPath;
    [_scanBox.layer addSublayer:corners];

    _scanLine = [[UIView alloc] initWithFrame:CGRectMake(8, 0, boxW - 16, 2)];
    _scanLine.backgroundColor = YK_BLUE;
    [_scanBox addSubview:_scanLine];

    _hint = [UILabel new];
    _hint.text = @"请将二维码对准扫码框中心";
    _hint.font = [UIFont systemFontOfSize:15];
    _hint.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    _hint.textAlignment = NSTextAlignmentCenter;
    _hint.numberOfLines = 2;
    _hint.frame = CGRectMake(20, CGRectGetMaxY(_scanBox.frame) + 36, W - 40, 44);
    [self.view addSubview:_hint];

    UIButton *album = [UIButton buttonWithType:UIButtonTypeSystem];
    album.frame = CGRectMake((W - 232) / 2, CGRectGetMaxY(_hint.frame) + 22, 232, 48);
    [album setTitle:@"  从相册识别二维码" forState:UIControlStateNormal];
    [album setImage:[UIImage systemImageNamed:@"photo.on.rectangle"] forState:UIControlStateNormal];
    album.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    album.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.92];
    album.layer.cornerRadius = 24;
    [album setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    album.tintColor = [UIColor whiteColor];
    [album addTarget:self action:@selector(ykPickAlbum) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:album];

    if (self.scriptMode) {
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(20, H - 96, W - 40, 64)];
        bar.backgroundColor = [UIColor colorWithWhite:0.35 alpha:0.55];
        bar.layer.cornerRadius = 14;
        [self.view addSubview:bar];

        _codeField = [UITextField new];
        _codeField.textColor = [UIColor whiteColor];
        _codeField.attributedPlaceholder = [[NSAttributedString alloc]
            initWithString:@"输入脚本码"
                attributes:@{ NSForegroundColorAttributeName: [UIColor colorWithWhite:0.85 alpha:1.0] }];
        _codeField.font = [UIFont systemFontOfSize:17];
        _codeField.frame = CGRectMake(16, 12, bar.bounds.size.width - 130, 40);
        _codeField.returnKeyType = UIReturnKeyDone;
        [_codeField addTarget:self action:@selector(ykSubmitCode)
             forControlEvents:UIControlEventEditingDidEndOnExit];
        [bar addSubview:_codeField];

        UIButton *ok = [UIButton buttonWithType:UIButtonTypeSystem];
        ok.frame = CGRectMake(bar.bounds.size.width - 104, 10, 94, 44);
        [ok setTitle:@"确定" forState:UIControlStateNormal];
        ok.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        ok.backgroundColor = YK_BLUE;
        ok.layer.cornerRadius = 22;
        [ok setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [ok addTarget:self action:@selector(ykSubmitCode) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:ok];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ykStartCamera];
    _animating = YES;
    [self ykAnimateLine];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _animating = NO;
    [_session stopRunning];
}

- (void)ykBack {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)ykAnimateLine {
    if (!_animating) return;
    __weak typeof(self) ws = self;
    [UIView animateWithDuration:1.8 delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        __strong typeof(ws) sf = ws; if (!sf) return;
        sf->_scanLine.frame = CGRectMake(8, sf->_scanBox.bounds.size.height - 4,
                                         sf->_scanBox.bounds.size.width - 16, 2);
    } completion:^(BOOL f) {
        __strong typeof(ws) sf = ws; if (!sf || !sf->_animating) return;
        sf->_scanLine.frame = CGRectMake(8, 0, sf->_scanBox.bounds.size.width - 16, 2);
        [sf ykAnimateLine];
    }];
}

- (void)ykSubmitCode {
    NSString *code = [_codeField.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!code.length) return;
    [self ykHandleCode:code];
}

- (void)ykHandleCode:(NSString *)code {
    if (_handled) return;
    _handled = YES;
    NSString *c = [code copy];
    [self dismissViewControllerAnimated:YES completion:^{
        if (self.onCode) self.onCode(c);
    }];
}

#pragma mark 相机

- (void)ykStartCamera {
    AVAuthorizationStatus st = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (st == AVAuthorizationStatusDenied || st == AVAuthorizationStatusRestricted) {
        _hint.text = @"摄像头不可用，可从相册选择二维码";
        [self ykShowCameraDenied];
        return;
    }
    if (st == AVAuthorizationStatusAuthorized) { [self ykSetupSession]; return; }
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!granted) {
                self->_hint.text = @"摄像头不可用，可从相册选择二维码";
                [self ykShowCameraDenied];
            } else {
                [self ykSetupSession];
            }
        });
    }];
}

- (void)ykSetupSession {
    if (_session) return;
    _session = [AVCaptureSession new];
    AVCaptureDevice *dev = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!dev) return;
    AVCaptureDeviceInput *in = [AVCaptureDeviceInput deviceInputWithDevice:dev error:NULL];
    if (!in || ![_session canAddInput:in]) return;
    [_session addInput:in];

    AVCaptureMetadataOutput *out = [AVCaptureMetadataOutput new];
    if ([_session canAddOutput:out]) {
        [_session addOutput:out];
        [out setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
        if ([out.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode])
            out.metadataObjectTypes = @[ AVMetadataObjectTypeQRCode ];
    }

    _preview = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    _preview.frame = self.view.bounds;
    _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:_preview atIndex:0];
    [_session startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputMetadataObjects:(NSArray<AVMetadataObject *> *)objects
       fromConnection:(AVCaptureConnection *)conn {
    for (AVMetadataObject *o in objects) {
        if ([o isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) {
            NSString *code = ((AVMetadataMachineReadableCodeObject *)o).stringValue;
            if (code.length) {
                [_session stopRunning];
                [self ykHandleCode:code];
                return;
            }
        }
    }
}

- (void)ykShowCameraDenied {
    YKAlert(self, @"相机权限未授权",
            @"请在(设置->隐私->相机)中授权应用使用相机，或直接从本地相册识别二维码。",
            @[@"知道了", @"从相册选择"], ^(NSInteger i) {
        if (i == 1) [self ykPickAlbum];
    });
}

#pragma mark 相册

- (void)ykPickAlbum {
    UIImagePickerController *p = [UIImagePickerController new];
    p.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        NSString *code = [self ykDecodeQR:img];
        if (code.length) {
            [self ykHandleCode:code];
        } else {
            YKAlert(self, @"未识别到二维码", @"请选择包含二维码的图片重试。", @[@"好"], nil);
        }
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)ykDecodeQR:(UIImage *)img {
    if (!img.CGImage) return nil;
    CIDetector *d = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil
                                       options:@{ CIDetectorAccuracy: CIDetectorAccuracyHigh }];
    NSArray *fs = [d featuresInImage:[CIImage imageWithCGImage:img.CGImage]];
    for (CIQRCodeFeature *f in fs) if (f.messageString.length) return f.messageString;
    return nil;
}

@end

UIViewController *YKPresentScan(UIViewController *host, BOOL scriptMode,
                                NSString *title, void (^onCode)(NSString *code)) {
    if (!host) return nil;
    YKScanViewController *vc = [YKScanViewController new];
    vc.pageTitle = title;
    vc.scriptMode = scriptMode;
    vc.onCode = onCode;
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [host presentViewController:vc animated:YES completion:nil];
    return vc;
}
