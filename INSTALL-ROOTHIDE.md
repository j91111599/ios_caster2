# 在 roothide 设备上部署 YKEngineLite（实测流程）

本机设备：iPhone 8 Plus（iPhone9,1，T8060），iOS 15.8.8，**roothide** 越狱，dpkg 架构 `iphoneos-arm64e`。

## 一、正常安装（Sileo）

把 `dist/com.yk.enginelite_0.1.0_iphoneos-arm64.deb` 加进源安装即可。roothide 会把
包内的 `/var/jb/...` 前缀**剥离**，实际落到 JBROOT：

```
JBROOT = /var/containers/Bundle/Application/.jbroot-XXXX
├── usr/bin/ykenginelite
└── Library/LaunchDaemons/com.yk.enginelite.plist
```

因此 `ls /var/jb/usr/bin/ykenginelite` 会报 not found —— **这是正常的**，别被误导。

## 二、三个必须踩过的坑（都已修在源码/plist 里）

| 现象 | 原因 | 处理 |
|---|---|---|
| 启动即 `listener 创建失败` | `nw_listener_create_with_port` + `nw_parameters_set_local_endpoint` 冲突 | 改用 POSIX socket（`socket/bind/listen/accept`） |
| 守护进程频繁重启、日志出现重复 `bind 失败 errno=48` | 向已关闭连接 `write()` 触发 **SIGPIPE** 直接杀死进程 | `main.m` 里 `signal(SIGPIPE, SIG_IGN)` |
| 只能写自己容器内，`/var/mobile`、`/tmp` 全部 `false` | 二进制无 entitlements，被套默认沙盒 | `ldid -S ent.plist`，授予 `platform-application` + `com.apple.private.security.no-sandbox` |

另外 plist 需带 roothide 的 `__Patched = true` 标记（与原版 `com.sky.yklaunchd.plist` 一致）。

## 三、手动部署（不依赖 Sileo）

```bash
J=/var/containers/Bundle/Application/.jbroot-XXXX

# 1) 放二进制
cp ykenginelite $J/usr/bin/ && chmod 755 $J/usr/bin/ykenginelite

# 2) entitlements（关键）
cat > $J/tmp/ykent.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>platform-application</key><true/>
  <key>com.apple.private.security.no-sandbox</key><true/>
  <key>com.apple.private.security.storage.AppDataContainers</key><true/>
  <key>com.apple.private.security.container-required</key><false/>
  <key>get-task-allow</key><true/>
</dict></plist>
EOF
ldid -S$J/tmp/ykent.plist $J/usr/bin/ykenginelite

# 3) LaunchDaemon（ProgramArguments 必须是 JBROOT 绝对路径）
cat > $J/Library/LaunchDaemons/com.yk.enginelite.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.yk.enginelite</string>
  <key>ProgramArguments</key><array><string>$J/usr/bin/ykenginelite</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>UserName</key><string>root</string>
  <key>ProcessType</key><string>Interactive</string>
  <key>__Patched</key><true/>
</dict></plist>
EOF

# 4) 启动
launchctl unload $J/Library/LaunchDaemons/com.yk.enginelite.plist 2>/dev/null
launchctl load -w $J/Library/LaunchDaemons/com.yk.enginelite.plist
```

## 四、验证

```bash
# Lite 只监听 loopback，需在设备上访问（或用原版引擎当客户端）
h=z_$(date +%s)
curl -s http://127.0.0.1:65323/health
curl -s -X POST http://127.0.0.1:65323/crypto/digest \
     -d '{"data":"hello","algorithm":"sha256"}'
# → 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
```

从 PC 侧可以直接用原版的 `/network/get` 当代理打 Lite（见 `tools/proxy_diff.py`）：

```bash
python tools/proxy_diff.py \
  --engine http://<device>:65322 --lite http://127.0.0.1:65323 \
  --golden live/baseline.json --out live/DIFF_REPORT.md
```

## 五、实测结论

以原版 65322 的 18 条基线用例逐条对打 Lite 65323：**18/18 PASS（100%）**，
覆盖 health / screen×4 / file×3 / prefs / crypto×7（含 4 条错误路径的状态码与文案）。

报告：`live/DIFF_REPORT.md`（本仓库外，工程侧生成）。
