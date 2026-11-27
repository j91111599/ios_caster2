# YKEngineApp — iOS 局域网控制端

一个独立的 iOS 应用（Theos 构建，安装到越狱设备），在设备上提供
HTTP 控制 API 与屏幕镜像服务，供 PC 端远程调用。

---

## 1. 项目结构

```
repo_work/
├── Makefile                          Theos 构建脚本（tool + application 双目标）
├── control                           Debian 包元信息
├── YKEngineLite/
│   ├── App/
│   │   ├── main.m                    AppDelegate + 根控制器 + 内置 HTTP 引擎启动
│   │   ├── YKMainView.m              主界面（三页：设备/脚本/录制，frame 布局）
│   │   ├── YKScriptScreens.m         脚本页 / 设置页 / 弹层
│   │   ├── YKAppDispatch.m           路由分发器
│   │   ├── YKMatch.m                 模板匹配（灰度下采样 + ZNCC + 多候选精修）
│   │   ├── YKTouch.m                 触控注入
│   │   ├── YKMirror.m                屏幕镜像（IOSurface 取帧 + JPEG + WebSocket）
│   │   ├── Info.plist                Bundle 配置（含本地网络权限声明）
│   │   └── entitlements.plist        签名权限
│   ├── Compat/
│   │   ├── YKHTTPServerCompat.m      POSIX socket 实现的极简 HTTP 服务
│   │   └── SSZipArchiveCompat.m      压缩解压兼容层
│   ├── Recovered/                    业务模块（文件/加密/网络/UI 指令等）
│   └── Resources/AppIcon60x60@2x.png
└── .github/workflows/build.yml       CI：Ubuntu + Theos，产出 .deb
```

---

## 2. 构建与安装

### 本地构建

```bash
export THEOS=~/theos
make package THEOS_PACKAGE_ARCH=iphoneos-arm64e FINALPACKAGE=1 DEBUG=0
```

产物：`packages/com.yk.enginelite_<版本>_iphoneos-arm64e.deb`

### CI 构建

推送到 GitHub 后自动构建，产物上传为 artifact 并复制到 `dist/`。

### 安装

- Sileo / Zebra：添加本地源，安装 `com.yk.enginelite`
- 或 `dpkg -i *.deb`

**注意**：安装后必须刷新图标缓存（`uicache`），否则 LaunchServices
不注册应用，启动会静默失败且不产生崩溃日志。

---

## 3. 运行时架构

```
┌─────────────────────────────────────────┐
│ YKEngineApp（App 进程）                  │
│                                          │
│  AppDelegate                             │
│    └── YKRootVC                          │
│          ├── YKMainView（三页 UI）        │
│          └── HTTPServer :65324           │
│                └── YKAppDispatchPath()   │
│                     ├── file / prefs     │
│                     ├── crypto / screen  │
│                     ├── network / device │
│                     ├── image / touch    │
│                     └── mirror :65330    │
└─────────────────────────────────────────┘
        ▲                        ▲
        │ HTTP :65324            │ WebSocket :65330
   PC 客户端（控制指令）      PC 客户端（屏幕镜像）
```

### 端口

| 端口 | 协议 | 用途 |
|---|---|---|
| 65324 | HTTP | 控制 API（约 380 条路由） |
| 65330 | WebSocket | MJPEG 屏幕镜像 |

**两个端口都必须监听 `0.0.0.0`**，否则 PC 无法直连（只能本机访问）。

---

## 4. HTTP API 概览

统一响应包封：

```json
{ "value": <任意> }
{ "value": { "error": "code", "message": "说明" } }
```

### 主要路由族

| 路由 | 说明 |
|---|---|
| `GET /health` | 健康检查（含 `bindErr` 诊断字段） |
| `GET /screen/info` | 屏幕尺寸 / DPI / 缩放 |
| `GET /device/info` | 设备型号 / 系统 / uuid / locale |
| `POST /file/write` | 写文件（支持 base64） |
| `POST /crypto/digest` | 摘要计算（sha256 / md5 等） |
| `POST /image/capture` | 截屏（返回 imageId） |
| `POST /image/findImage` | 模板匹配（返回坐标与分数） |
| `POST /image/findColor` | 找色 |
| `POST /touch/tap` | 点击注入 |
| `POST /mirror/start` | 启动镜像服务 |
| `POST /mirror/grab` | 单帧抓取（base64 JPEG） |
| `GET /debug/ui` | 导出当前视图树 JSON |

---

## 5. 关键实现细节

### 5.1 HTTP 服务（YKHTTPServerCompat）

自实现 POSIX socket 服务（不用 Network.framework，避免 listener 配置冲突）。

```objc
HTTPServer *srv = [HTTPServer new];
srv.port = 65324;
srv.interface = @"any";       // 0.0.0.0；"loopback" 只绑 127.0.0.1
[srv get:@"/health" withBlock:^(RouteRequest *req, RouteResponse *res) { ... }];
[srv setDefaultHandler:^(RouteRequest *req, RouteResponse *res) { ... }];
[srv start:&err];
```

### 5.2 屏幕镜像（YKMirror）

```
IOSurface 取帧缓冲 → CGBitmapContext → JPEG（ImageIO 硬件编码）
   → WebSocket 二进制帧（服务端不掩码）
```

系统的屏幕捕获函数通过 `dlsym` 动态获取，不静态链接系统私有框架。

### 5.3 模板匹配（YKMatch）

纯 C 实现，不依赖 OpenCV：

1. 转灰度，按整数因子下采样
2. ZNCC（零均值归一化互相关）粗搜
3. 保留 top-K 候选
4. 全分辨率 ±f 邻域精修
5. 距离 NMS 去重

750×1334 场景约 170 ms，匹配分数可达 1.0。

### 5.4 UI 布局（YKMainView）

**纯 frame 布局，不用 Auto Layout。**

早前版本用约束实现，出现过 `NSISEngine tryUsingArtificialVariableToAddConstraint`
异常导致启动崩溃；改为 frame 后问题消失。

三页通过 `hidden` 切换：

```objc
- (void)ykShowPageObj:(id)o {
    NSInteger i = [o integerValue];
    _devScroll.hidden    = (i != 0);
    _scriptScroll.hidden = (i != 1);
    _recordScroll.hidden = (i != 2);
}
```

> 注意：`performSelector:withObject:` 传的是对象指针。方法参数若声明为 `NSInteger`
> （基本类型）会收到对象地址值，导致判断错乱。参数必须用 `id` 再转。

---

## 6. 权限与签名

`entitlements.plist` 必需项：

```xml
<key>application-identifier</key><string>com.yk.engine.ui</string>
<key>com.apple.developer.team-identifier</key><string>YKRE</string>
<key>platform-application</key><true/>
<key>com.apple.private.security.no-sandbox</key><true/>
<key>container-required</key><false/>
```

**签名规则：**

- LaunchDaemon：必须 `ldid -S ent.plist`
- **UIApplication：不要二次签名**。Theos 已做 ad-hoc 签名，再 `ldid -S`
  会写坏 `LC_CODE_SIGNATURE`，导致 LaunchServices 静默拒绝启动（无崩溃日志）

`Info.plist` 必需的权限声明：

```xml
<key>NSLocalNetworkUsageDescription</key><string>...</string>
<key>NSBonjourServices</key><array><string>_ykengine._tcp</string></array>
```

缺少时 iOS 14+ 会静默丢弃局域网入向连接。

---

## 7. 已知问题（当前待解决）

### 引擎端口不监听

**现象**

- App 启动后界面正常显示
- 但 `192.168.1.43:65324` 从 PC 扫描为 closed
- 设备上其他端口（如另一个 App 的 65322）正常

**已尝试的修复**

| 版本 | 改动 | 结果 |
|---|---|---|
| 9.0.3 | `interface` 从 `loopback` 改为 `any` | 仍不监听 |
| 9.0.4 | 加 `NSLocalNetworkUsageDescription` + bind fallback + `/health` 暴露 `bindErr` | 仍不监听 |
| 9.0.5 | 构造函数强制启动（遍历窗口树找根 VC 调 `startEngineIfNeeded`） | 待验证 |

**排查方向**

1. 确认 `startEngineIfNeeded` 是否真的被调用（方法首行写文件/日志）
2. 打印 `[_srv start:&err]` 的返回值与 `err`
3. 检查 bind 是否被沙箱拒绝（即使有 `no-sandbox` entitlement）
4. 检查 App 启动后是否被系统很快终止（内存 / 签名 / 崩溃）
5. 用 `GET /health` 的 `bindErr` 字段确认 bind 结果——端口不通说明没执行到 bind

---

## 8. 版本历史（近期）

| 版本 | 内容 |
|---|---|
| 8.0.5 | 三页 UI 完成（设备 / 脚本 / 录制） |
| 9.0.0 | 新增屏幕镜像模块（IOSurface + JPEG + WebSocket） |
| 9.0.1–9.0.2 | 修复 IOSurface 头文件缺失、类型冲突 |
| 9.0.3 | 引擎绑定改为 0.0.0.0 |
| 9.0.4 | 本地网络权限 + bind fallback |
| 9.0.5 | 构造函数强制启动引擎 |

---

## 9. 调试技巧

### 调用 API

```bash
curl http://192.168.1.43:65324/health
curl -X POST http://192.168.1.43:65324/image/capture \
     -H 'Content-Type: application/json' -d '{}'
```

### 导出视图树

```bash
curl http://192.168.1.43:65324/debug/ui | python -m json.tool
```

### 检查签名

```bash
codesign -d --entitlements - /path/to/YKEngineApp.app
ldid -e /path/to/YKEngineApp.app/YKEngineApp
```

### 读取设备日志

```bash
idevicesyslog | grep YKEngineLite
```

---

## 10. 环境要求

- Theos + iOS SDK（CI 用 Ubuntu + 系统 clang/lld 交叉编译）
- 目标设备：iOS 13+，arm64 / arm64e，越狱环境
- 包架构：`iphoneos-arm64e`
