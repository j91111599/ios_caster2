# YKEngine-Lite — 重建引擎的可编译工程

把 `dump/Recovered/` 里从二进制重建出来的模块，编成一个**可安装、可运行**的守护进程，
在设备上重新提供一套与远控Pro 同构的 HTTP 面（默认 `127.0.0.1:65323`，避开原版 65322）。

> 工程可信度：路由与参数、包封、鉴权全部对齐真机实测（见 `PROTOCOL_FINAL.md`）。

---

## 一、编译（GitHub Actions，无需本地 macOS）

1. 新建 GitHub 仓库，把本目录内容推到根（`.github/` 必须在根）；
2. Actions → `build` → Run workflow；
3. Artifacts 下载 `ykenginelite-deb`，得到 `com.yk.enginelite_0.1.0_iphoneos-arm64.deb`。

## 二、安装与验证

```sh
dpkg -i com.yk.enginelite_0.1.0_iphoneos-arm64.deb
launchctl load /var/jb/Library/LaunchDaemons/com.yk.enginelite.plist

curl -s http://127.0.0.1:65323/health
# {"value":{"state":"ready","ready":true,"message":"YKEngineLite HTTP 服务可用",...}}

curl -s -X POST http://127.0.0.1:65323/file/write -d '{"path":"/tmp/lite.txt","data":"hi"}'
curl -s "http://127.0.0.1:65323/file/read?path=/tmp/lite.txt"
curl -s http://127.0.0.1:65323/screen/info
curl -s -X POST http://127.0.0.1:65323/crypto/base64/encode -d '{"data":"hello"}'
curl -s -X POST http://127.0.0.1:65323/ui/label/show -d '{"id":"l1","text":"hello"}'
```

日志：`/var/mobile/Library/YKEngineLite/engine.log`
端口文件：`/var/mobile/Library/YKEngineLite/http_port`

## 三、编译进来的模块（6/12）

| 模块 | 路由 | 状态 | 依赖 |
|---|---|---|---|
| `YKHTTPRouter` | app 15（路由协议/参数辅助/包封） | ✅ 编译 | 自带 compat HTTPServer |
| `YKUtilityModules` | file 21 / prefs 11 / plist 6 / archive 7 / screen 6 | ✅ 编译 | zip/unzip CLI（archive） |
| `YKCryptoNetworkModules` | crypto 21 / network 21 / 服务级 32 / internal 2 | ✅ 编译 | CommonCrypto / Security |
| `YKUIModule` | ui 245（通用派发器） | ✅ 编译 | UIKit |

## 四、未移植模块及原因（返回 501 not_ported）

| 模块 | 路由 | 原因 |
|---|---|---|
| `YKTouchInjector` | touch 8 | 需 `IOHIDEventSystemClient` 私有 API + `com.apple.system-task-ports` |
| `YKElementBridge` | element 15 | 需 Accessibility/XCUITest 私有通道 |
| `YKVisionEngine` | image 53 / ocr 9 / yolo 12 | 需 OpenCV 4.12 + ncnn/PP-OCRv5 模型 |
| `YKPackageInstaller` | app install 相关 | 需 MobileInstallation / InstallCoordination / TrollStore |
| `YKRecordEngine` | record 11 | 可编译，本版未接线（纯 Foundation，接入成本低） |
| `YKDeviceControl` | device 49 / system 28 / vpn 6 / keyboard 11 | 需 NetworkExtension 权限与私有状态读取 |

> 这些不是"做不到"，而是要么依赖私有 API（需越狱 entitlement 与平台适配），
> 要么依赖第三方算法库（应直接 link 上游，而不是重写）。

## 五、目录

```
.
├── Makefile                             # Theos tool 构建
├── control                              # deb 元数据
├── layout/Library/LaunchDaemons/…plist  # 开机自启
├── YKEngineLite/
│   ├── main.m                           # 入口 + 按模块分派
│   ├── Compat/
│   │   ├── YKHTTPServerCompat.h/.m      # NWListener HTTP 服务器 + 会话/CORS/审计
│   │   ├── HTTPServer.h / RouteRequest.h / RouteResponse.h   # 转发头
│   │   └── SSZipArchive.h / SSZipArchiveCompat.m              # 压缩兼容层
│   └── Recovered/                       # 直接来自 dump/Recovered（未改动逻辑）
└── .github/workflows/build.yml
```

## 六、已知限制

1. `main.m` 用通配 handler 统一分派，`/routes` 不返回完整 registry（Lite 版不谎报）；
2. `archive` 依赖设备上的 `zip/unzip`（Procursus 一般自带），缺失时返回失败并记日志；
3. 会话鉴权默认关闭（`requiresSessionHeader = NO`），需要时在 `main.m` 打开，行为与真机一致；
4. 编译出的二进制运行在 root（与 LaunchDaemon 一致），文件类路由因此拥有全盘读写能力。
