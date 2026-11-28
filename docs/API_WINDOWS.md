# YK Engine Lite —— Windows 客户端对接 API 文档

> 适用版本：`com.yk.enginelite 31.6.4`（设备 iPhone9,1 / iOS 15.8.8）
> 实测环境：设备 `192.168.1.43`，PC `192.168.1.42`（同一局域网）
> 文档里所有 JSON 都来自真机实测；标「未实现」的路径会返回 `not_ported`。

---

## 1. 端口与角色

| 端口 | 归属 | 是否常驻 | 说明 |
|---|---|---|---|
| **65323** | root 守护进程 `com.yk.enginelite` | 可开关（App「服务开关」） | **主业务口**：触控注入、文件、偏好、录制、加解密、网络代理、系统操作 |
| **65325** | 同一个守护进程的**控制口** | 永远在线 | 服务关掉后仍可用：`/system/*`、`/record/*`、`/touch/*`、`/file/*`、`/prefs/*`、`/health` |
| **65324** | App `com.yk.engine.ui` 自己起的 HTTP | 仅 App 在前台时可达 | App 侧能力：`/health`、`/session/*`、`/executor/*`、`/record/start|stop|tasks`、`/debug/connect` |
| 65322 | 原版 `com.sky.ykpro` | 另装 | 仅作对照，Lite 不依赖它 |

**客户端连接策略（推荐）**

1. 启动先探 `GET http://<ip>:65323/health`；
2. 不通则探 `http://<ip>:65325/health`（服务被关时的兜底口，只有控制类能力）；
3. 需要 App 侧能力（脚本执行器 / 截图等）再探 `65324`，并提示用户把 App 切到前台。

> 三个口的 `/health` 返回里都有 `"localPort"`，可用来判断自己连的是哪个口。

---

## 2. 通用约定

### 2.1 响应信封

成功：

```json
{ "value": { ... } }
```

失败（HTTP 仍可能是 200，**必须看 body**）：

```json
{ "value.error": "not_ported", "value.message": "element 模块未移植到 Lite 构建…" }
```

常见错误码：

| error | 含义 |
|---|---|
| `not_ported` | 该模块 Lite 未实现（见第 12 节清单） |
| `not_found` | 路由或文件不存在 |
| `bad_request` | 参数缺失/非法 |
| `invalid_argument` | 参数类型不对 |
| `empty_sequence` | `points` 为空 |

### 2.2 请求

- 一律 `Content-Type: application/json`，body 为 UTF-8 JSON；
- 单次 body 上限 **16 MB**（`/health` 的 `limits.maxJSONBodyBytes`）；
- GET 也可以用 query 传参（例如 `/file/exists?path=/var/mobile/Media`），服务端优先取 body；
- **无鉴权**：Lite 不校验 `X-YK-Session-Id`（保留 `/session/create` 只为兼容原版客户端）。

### 2.3 坐标

- 单位：**屏幕像素**，原点左上角，`x` 向右、`y` 向下；
- 本机屏幕 **750 × 1334**，`scale = 2`（1 pt = 2 px）；
- `GET /screen/info` 可拿到当前分辨率，客户端不要写死。

```json
{ "value": { "width": 750, "height": 1334, "scale": 2, "dpi": 326,
             "orientation": 1, "orientationName": "portrait",
             "size": { "width": 750, "height": 1334 } } }
```

---

## 3. 健康检查

### `GET /health`（65323 / 65324 / 65325 都有）

```json
{ "value": { "state": "ready", "ready": true, "engine": "reconstructed",
             "message": "YKEngineLite HTTP 服务可用",
             "limits": { "maxJSONBodyBytes": 16777216 },
             "localPort": 65323 } }
```

### `GET /routes`

Lite 不暴露完整路由表：

```json
{ "value": { "schemaVersion": "lite-1.0", "count": 0,
             "note": "Lite 构建不暴露完整 route registry…" } }
```

### `POST /touch/ping`

判活 + 拿守护进程 pid：

```json
{ "value": { "ok": true, "pid": 8124 } }
```

---

## 4. 会话（兼容层）

Lite 不强制，但保留原版语义，方便复用老客户端代码。

| 方法 | 路径 | 请求 | 响应 |
|---|---|---|---|
| POST | `/session/create` | `{}` | `{"value":{"sessionId":"sess_…","state":"active","name":"default"}}` |
| GET | `/session/list` | – | 守护进程只回 `{"value":{"state":"active"}}`；带 `count/sessions` 的是 App 口(65324) |
| DELETE | `/session/all` | – | `{"value":{"deleted":true,"count":N}}` |

---

## 5. 触控注入（65323 / 65325）

所有触控都是 **IOHID 真实注入**，不需要越狱端额外配合；返回里 `sent` 表示事件已投递。

### 5.1 点击

`POST /touch/tap`

```json
{ "x": 375, "y": 700 }
```

```json
{ "value": { "action": "tap", "x": 375, "y": 700, "sent": 1 } }
```

### 5.2 长按

`POST /touch/longPress`

```json
{ "x": 375, "y": 700, "duration": 1.2 }
```

### 5.3 双击

`POST /touch/doubleTap`

```json
{ "x": 375, "y": 700, "gap": 0.08 }
```

### 5.4 滑动

`POST /touch/swipe`

```json
{ "x": 300, "y": 700, "toX": 600, "toY": 700, "duration": 0.3, "steps": 12 }
```

```json
{ "value": { "action": "swipe", "from": [300, 700], "to": [600, 700],
             "steps": 12, "sent": 1 } }
```

> 建议 `steps >= 12`，否则系统可能识别成 fling 而不是拖拽。

### 5.5 Home 键

`POST /touch/home`

```json
{ "count": 1, "hold": 0 }
```

```json
{ "value": { "action": "home", "count": 1, "ok": true } }
```

### 5.6 双指缩放

`POST /touch/pinch` —— 两种写法任选

```json
{ "startPoints": [ { "x": 300, "y": 700 }, { "x": 450, "y": 700 } ],
  "endPoints":   [ { "x": 200, "y": 700 }, { "x": 550, "y": 700 } ],
  "duration": 0.4, "steps": 12 }
```

```json
{ "x": 300, "y": 700, "x2": 450, "y2": 700,
  "ex1": 200, "ey1": 700, "ex2": 550, "ey2": 700,
  "duration": 0.4, "steps": 12 }
```

### 5.7 任意轨迹（录制回放 / 画线都走它）

`POST /touch/sequence`

```json
{ "points": [
    { "x": 200, "y": 650, "touch": 1, "delayMs": 16 },
    { "x": 240, "y": 660, "touch": 1, "delayMs": 16 },
    { "x": 280, "y": 670, "touch": 0, "delayMs": 16 }
  ],
  "delayMs": 16 }
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `x` / `y` | number | 像素坐标 |
| `touch` | 0/1 | 1=按下/移动（按住的帧），0=抬起 |
| `delayMs` | number | 相对上一帧的间隔，缺省用顶层 `delayMs` |
| `finger` | number | 可选，多指时区分手指（1 起） |

### 5.8 不支持

| 路径 | 现状 |
|---|---|
| `/touch/multi` | **未实现**（返回 `not_found: multi`）。多指请用 `/touch/sequence` 的 `finger` 字段 |
| `/touch/showTouches` | 返回 `supported:false`（Lite 无触摸可视化层） |

---

## 6. 录制 / 回放

数据落在设备：`/var/mobile/Library/YKEngineLite/records/rec_<ms>.json`

### 6.1 列表

`GET /record/list`（65323 / 65325）

```json
{ "value": { "records": [
  { "id": "rec_1795867610610",
    "name": "11月28日 20:06",
    "createdAt": 1795867610.61,
    "duration": 10.52,
    "count": 68,
    "steps": [ { "x": 199.99, "y": 649.98, "touch": 1, "delayMs": 16 } ]
  }
] } }
```

### 6.2 保存

`POST /record/save`

```json
{ "name": "登录流程",
  "duration": 12.3,
  "steps": [ { "x": 100, "y": 200, "touch": 1, "delayMs": 16 } ] }
```

```json
{ "value": { "ok": true, "id": "rec_1795872890384", "count": 1 } }
```

### 6.3 回放

`POST /record/play`

```json
{ "id": "rec_1795867610610", "times": 3, "delayMs": 1800 }
```

```json
{ "value": { "ok": true, "id": "rec_1795867610610", "times": 3 } }
```

- **异步**：接口立即返回，守护进程按 `delayMs`（首帧前等待）+ 逐帧注入；
- 播完会发 Darwin 通知把 App 拉回前台（`com.yk.openapp`）；
- 播放期间**不要**并发调用其它触控接口。

### 6.4 删除

`POST /record/remove` → `{"id":"rec_…"}` → `{"value":{"ok":true,"id":"rec_…"}}`

### 6.5 设备侧录制（供参考）

App「录制」页 →「打开录制小球」会在 **SpringBoard 层**浮出 44pt 红球，可以跨 App 采集真实手指轨迹，
完成后落到同一个 `records/` 目录。客户端不需要实现这段，只要用 `/record/list` 读取即可。

---

## 7. 文件系统（root 权限）

> 守护进程以 root 运行，能读写整个数据卷；客户端请自行限制调用范围。
>
> **路径约定**：`/Applications`、`/usr/bin` 这类标准路径在设备上实际位于 roothide 的 jbroot 下：
> `/var/containers/Bundle/Application/.jbroot-D7A0C9962DAD0DA5/...`
> （这台机器固定是 `D7A0C9962DAD0DA5`，换设备要重新取）。
> `/var/mobile/...`、`/var/mobile/Library/...` 是真实路径，可以直接用。

| 方法 | 路径 | 参数 | 响应 `value` |
|---|---|---|---|
| GET/POST | `/file/exists` | `path` | `"file"` / `"directory"` / `false` |
| GET/POST | `/file/size` | `path` | number（字节） |
| GET/POST | `/file/read` | `path` | `{encoding:"utf8"\|"base64", data, size}` |
| POST | `/file/write` | `path`, `data`(utf8 文本) | `true` / `false` |
| POST | `/file/append` | `path`, `data` | `true` / `false` |
| POST | `/file/remove` | `path` | `true` / `false` |
| GET/POST | `/file/list` | `path` | `[{name,path,size,isDirectory}]` |
| GET/POST | `/file/lines` | `path` | `[ "行1", "行2", … ]` |
| GET/POST | `/file/lineCount` | `path` | number |
| GET/POST | `/file/md5` \| `sha1` \| `sha256` \| `sha512` | `path` | hex 字符串 |

示例：

```
POST /file/read  {"path":"/var/mobile/Library/YKEngineLite/http_port"}
→ {"value":{"encoding":"utf8","data":"65323","size":5}}
```

```
GET /file/list?path=/var/mobile/Library/YKEngineLite
→ {"value":[{"name":"records","path":"…/records","size":224,"isDirectory":true}]}
```

**注意**：`/file/write` 只吃 UTF-8 文本；二进制要自己 base64 后分块写 `*.b64`，再让设备侧 base64 解码。
`/file/copy`、`/file/directory/create`、`/file/line/set` 等在原版里有，Lite **未实现**。

---

## 8. 偏好 / plist

### prefs（`NSUserDefaults`）

| 方法 | 路径 | 参数 |
|---|---|---|
| GET/POST | `/prefs/get` | `key`, `namespace`(bundle id，可选) |
| POST | `/prefs/set` | `key`, `value`, `namespace` |
| GET | `/prefs/has` | `key`, `namespace` |
| GET | `/prefs/keys` | `namespace` |
| GET | `/prefs/all` | `namespace` |
| GET | `/prefs/namespaces` | – |

```json
{ "key": "yk.peerDevice", "value": { "name": "MacBook Pro", "ip": "192.168.1.42" } }
```

> **作用域注意**：`/prefs/*` 读写的是**守护进程(root)** 的 defaults 域，
> 拿不到 App(mobile) 自己的偏好（例如 `yk.peerDevice` 在 App 域里，用 daemon 读会是 `null`）。
> 要读 App 侧偏好，请直连 65324 或读 App 容器下的 plist 文件。

### plist

| 方法 | 路径 | 参数 | 现状 |
|---|---|---|---|
| POST | `/plist/read` | `path` | **当前实现有 bug**，实测 500 `data parameter is nil` |
| POST | `/plist/dump` | `path` | 同上 |

**建议**：直接用 `/file/read` 拿内容 —— XML plist 会以 `encoding:"utf8"` 返回文本，
二进制 plist 会以 `encoding:"base64"` 返回，客户端本地解析即可：

```
POST /file/read {"path":"<jbroot>/Applications/YKEngineApp.app/Info.plist"}
→ {"value":{"encoding":"utf8","data":"<?xml version="1.0"…","size":2188}}
```

其它 `/plist/*`（`write`/`createData`/`createDate`）未实现。

---

## 9. 加解密 / 编码（`/crypto/*`）

统一参数：`data`、`key`、`iv`、`aad`、`encoding`、`inputEncoding`、`keyEncoding`、`outputEncoding`（缺省 utf8）。

| 路径 | 关键参数 |
|---|---|
| `POST /crypto/base64/encode`、`/crypto/base64/decode` | `data` |
| `POST /crypto/hex/encode`、`/crypto/hex/decode` | `data` |
| `POST /crypto/url/encode`、`/crypto/url/decode` | `data` |
| `POST /crypto/digest` | `data`, **`algorithm`**(md5/sha1/sha256/sha512) |
| `POST /crypto/hmac` | `data`, `key`, `algorithm` |
| `POST /crypto/pbkdf2` | `password`, `salt`, `iterations`, `keyLength` |
| `POST /crypto/hkdf` | `ikm`, `salt`, `info`, `keyLength` |
| `POST /crypto/randomBytes` | `length` |
| `POST /crypto/encrypt`、`/crypto/decrypt` | `data`, `key`, `iv`, `algo`(AES-CBC 缺省) |
| `POST /crypto/gcm/encrypt`、`/crypto/gcm/decrypt` | `data`, `key`, `iv`, `aad` |

> 注意：`/crypto/md5` 这种「算法当动词」的老写法 **没有**，请用
> `POST /crypto/digest {"data":"abc","algorithm":"md5"}` → `{"value":"900150983cd24fb0d6963f7d28e17f72"}`。

---

## 10. 网络代理（`/network/*`）

| 路径 | 参数 | 响应 `value` |
|---|---|---|
| `POST /network/get` | `url`, `headers`(可选) | `{status, body, headers?}` |
| `POST /network/postJSON` | `url`, `body`, `headers` | 同上 |
| `POST /network/postForm` | `url`, `form` | 同上 |
| `POST /network/request` | `url`, `method`, `body`, `headers` | 同上 |
| `GET /network/cookies` | – | cookie 列表 |
| `GET /network/proxy` | – | 代理配置 |

实测：

```
POST /network/get {"url":"http://192.168.1.42:8080/Packages"}
→ {"value":{"status":200,"body":"Package: com.yk.enginelite\n…"}}
```

> 这个接口的流量走**设备**的网络栈，可用来让设备替你抓内网页面。

---

## 11. 系统操作（`/system/*`）

| 方法 | 路径 | 请求 | 响应 |
|---|---|---|---|
| GET | `/system/service` | – | `{"value":{"on":true,"port":65323}}` |
| POST | `/system/service` | `{"on":true\|false}` | `{"value":{"ok":true,"on":true}}` |
| POST | `/system/respring` | `{}` | `{"value":{"ok":true,"action":"respring"}}`（会黑屏 5–10s） |
| POST | `/system/install` | `{"path":"/var/mobile/Media/x.deb"}` | `{"value":{"ok":true,"exit":0,"dpkg":"…/usr/bin/dpkg"}}` |
| POST | `/system/shell` | `{"command":"id"}` | `{"value":{"output":"…","exitCode":0,…}}` |

**已知限制**：`/system/shell` 目前 `output` 恒为空（子进程被沙箱拦住，`spawnRC` 会显示 0 但无输出）。
装机、改文件请走 `/system/install` 与 `/file/*`；需要 root shell 时改用原版 App 的 `/system/shell`。

---

## 12. App 侧接口（65324，需 App 在前台）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 带 `sessionCount`、`bindErr` |
| POST | `/session/create` | 同守护进程 |
| GET | `/executor/scripts` | 脚本订阅列表 `{scripts,count}` |
| POST | `/executor/scripts/save` | 保存订阅 |
| POST | `/executor/run` | 运行脚本 |
| POST | `/record/start` \| `/record/stop` | App 内录制 |
| GET | `/record/tasks` | App 内录制任务 |
| POST | `/debug/connect` | **调试口**：`{"code":"<二维码内容>"}` 直接喂给扫码连接逻辑（相机不可用时验证用） |

`/debug/connect` 的行为等价于扫码结果：

| code 内容 | 效果 |
|---|---|
| `{"name":"Mac","ip":"47.107.154.171","wan":true}` 且未开广域网 | 弹「当前设备尚未开启广域网，请先开启后再扫码连接。」 |
| `{"name":"MacBook Pro","ip":"192.168.1.42","port":65322}` | 设备行变 `MacBook Pro / IP 192.168.1.42 / 已连接` |
| 解析不到 ip | 弹「二维码无效」 |

---

## 13. 未实现模块清单（返回 `not_ported`）

在 65323 上调用会直接得到 `{"value.error":"not_ported"}`：

```
element  image  ocr  yolo  device(via daemon)  app  vpn  keyboard
archive  internal  wda  executor(daemon侧)  touch/multi
```

**这意味着**：Lite 目前**不能**做「读取界面元素树」和「截屏」——Windows 客户端不能靠 `/element/tree`
定位控件，请用固定坐标或你自己维护的坐标表；如需截图，需要接原版 App（65322）或等 Lite 补上 image 模块。

已实现且可放心使用的模块：`touch`、`file`、`prefs`、`plist(read/dump)`、`crypto`、`network`、
`screen`、`record`、`system`、`session`、`health`、`routes`。

---

## 14. Windows（C#）最小客户端

```csharp
using System.Net.Http;
using System.Text;
using System.Text.Json;

public sealed class YkClient : IDisposable
{
    private readonly HttpClient _http;
    public string BaseUrl { get; }

    public YkClient(string host, int port = 65323)
    {
        BaseUrl = $"http://{host}:{port}";
        _http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        _http.DefaultRequestHeaders.ConnectionClose = false;   // 复用长连接
    }

    public async Task<JsonElement> PostAsync(string path, object body)
    {
        var json = JsonSerializer.Serialize(body);
        using var content = new StringContent(json, Encoding.UTF8, "application/json");
        using var resp = await _http.PostAsync(BaseUrl + path, content);
        var text = await resp.Content.ReadAsStringAsync();
        var doc = JsonDocument.Parse(text);
        var root = doc.RootElement;
        if (root.TryGetProperty("value.error", out var err))
            throw new InvalidOperationException($"{err.GetString()}: " +
                (root.TryGetProperty("value.message", out var m) ? m.GetString() : ""));
        return root.GetProperty("value").Clone();
    }

    public Task TapAsync(int x, int y)          => PostAsync("/touch/tap", new { x, y });
    public Task SwipeAsync(int x1, int y1, int x2, int y2) =>
        PostAsync("/touch/swipe", new { x = x1, y = y1, toX = x2, toY = y2, duration = 0.3, steps = 14 });
    public Task HomeAsync()                     => PostAsync("/touch/home", new { count = 1 });
    public Task<JsonElement> RecordsAsync()     => PostAsync("/record/list", new { });
    public void Dispose() => _http.Dispose();
}
```

调用示例：

```csharp
using var yk = new YkClient("192.168.1.43");
await yk.PostAsync("/system/service", new { on = true });   // 打开服务
await yk.TapAsync(375, 700);
var recs = await yk.RecordsAsync();                          // 读录制列表
```

**客户端注意事项**

1. **坐标是像素**：如果你的 UI 用 pt，记住本机 `scale = 2`；
2. **超时**：`/system/respring` 会立刻返回但设备随后黑屏，客户端要能容忍 10s 内无响应；
3. **服务会被关**：用户点「服务开关」后 65323 就没了，客户端要回落到 65325 或提示用户；
4. **错误在 body 里**：HTTP 200 也可能是失败，必须解析 `value.error`；
5. **不要并发触控**：`/record/play` 期间插入 `/touch/tap` 会打乱轨迹。

---

## 15. 版本与变更

| 版本 | 关键变化 |
|---|---|
| 31.6.4 | 设备行「已连接」样式修复；`/debug/connect` 调试口 |
| 31.6.0 | 回放结束自动把 App 拉回前台 |
| 31.5.7 | SB 悬浮球录制坐标/touch 标志修复 |
| 31.4.x | 桌面图标自愈、`/system/install`、shell 自动探测 |
| 31.0.0 | 双端口模型（65323 业务 / 65325 控制） |

---

如需我补一份 **OpenAPI 3.1 (YAML)** 或 **Postman collection**，说一声，我直接按这份文档生成。
