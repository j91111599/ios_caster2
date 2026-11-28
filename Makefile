TARGET := iphone:clang:latest:14.0
THEOS_PACKAGE_ARCH = iphoneos-arm64e
THEOS_PACKAGE_FILENAME = com.yk.enginelite_$(THEOS_PACKAGE_VERSION)_iphoneos-arm64e.deb
ARCHS = arm64
INSTALL_TARGET_PROCESSES =

include $(THEOS)/makefiles/common.mk

# ---------- 守护进程（无 UI，局域网/本机 HTTP 引擎）----------
TOOL_NAME = ykenginelite
ykenginelite_FILES = \
	YKEngineLite/main.m \
	YKEngineLite/Compat/YKHTTPServerCompat.m \
	YKEngineLite/Compat/SSZipArchiveCompat.m \
	YKEngineLite/Recovered/YKCryptoNetworkModules.m \
	YKEngineLite/Recovered/YKUtilityModules.m \
	YKEngineLite/Recovered/YKUIModule.m YKEngineLite/App/YKUIFlows.m \
	YKEngineLite/App/YKTouch.m
ykenginelite_FRAMEWORKS = Foundation UIKit Network Security NetworkExtension
ykenginelite_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -Wno-nullability-completeness -IYKEngineLite/Compat -IYKEngineLite/Recovered
ykenginelite_LDFLAGS = -fuse-ld=lld
ykenginelite_CODESIGN_FLAGS = -SYKEngineLite/App/daemon.entitlements.plist
include $(THEOS_MAKE_PATH)/tool.mk

# ---------- App（SpringBoard 图标 + 界面 + 进程内引擎）----------
APPLICATION_NAME = YKEngineApp
YKEngineApp_FILES = YKEngineLite/App/main.m YKEngineLite/App/YKMainView.m YKEngineLite/App/YKScriptScreens.m YKEngineLite/App/YKAppDispatch.m YKEngineLite/App/YKMatch.m YKEngineLite/App/YKTouch.m YKEngineLite/App/YKMirror.m YKEngineLite/App/YKUIFlows.m YKEngineLite/Compat/YKHTTPServerCompat.m YKEngineLite/Compat/SSZipArchiveCompat.m YKEngineLite/Recovered/YKUtilityModules.m YKEngineLite/Recovered/YKCryptoNetworkModules.m YKEngineLite/Recovered/YKUIModule.m
YKEngineApp_FRAMEWORKS = UIKit Foundation Network CoreVideo ImageIO
YKEngineApp_CFLAGS = -fobjc-arc -Wno-arc-retain-cycles -Wno-nullability-completeness -F$(THEOS_PROJECT_DIR)/Frameworks -I$(THEOS_PROJECT_DIR)/Frameworks/opencv2.framework/Headers -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -Wno-nullability-completeness -IYKEngineLite/Compat -IYKEngineLite/Recovered -Wno-unused-const-variable -Wno-unused-function
CLANG_RT = $(shell ls /usr/lib/llvm-*/lib/clang/*/lib/darwin/libclang_rt.ios.a 2>/dev/null | head -1)
YKEngineApp_LDFLAGS = -fuse-ld=lld $(CLANG_RT) -Wl,-U,___isPlatformVersionAtLeast
YKEngineApp_CODESIGN_FLAGS = -SYKEngineLite/App/entitlements.plist
YKEngineApp_INSTALL_PATH = /Applications
YKEngineApp_INFO_PLIST = YKEngineLite/App/Info.plist
YKEngineApp_RESOURCE_FILES = YKEngineLite/Resources/AppIcon60x60@2x.png YKEngineLite/App/Info.plist
# ---------- SpringBoard 触控注入 ----------

include $(THEOS_MAKE_PATH)/application.mk

# ---------- launcher ----------
TOOL_NAME = yklaunch
yklaunch_FILES = YKEngineLite/launcher.m
yklaunch_FRAMEWORKS = Foundation
yklaunch_CFLAGS = -fobjc-arc
yklaunch_LDFLAGS = -fuse-ld=lld
yklaunch_CODESIGN_FLAGS = -SYKEngineLite/App/launcher.entitlements.plist
include $(THEOS_MAKE_PATH)/tool.mk


# ---- SpringBoard 触控注入 tweak ----
TWEAK_NAME = YKSpringTouch
YKSpringTouch_FILES = YKTouchSpring/YKSBProbe.m
YKSpringTouch_CFLAGS = -fobjc-arc -Wno-nullability-completeness -Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable
YKSpringTouch_FRAMEWORKS = UIKit Foundation CoreFoundation
YKSpringTouch_LDFLAGS = -fuse-ld=lld
YKSpringTouch_CFLAGS += -I$(THEOS)/vendor/include
YKSpringTouch_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk


after-install::
	install.exec "killall -9 ykenginelite 2>/dev/null; launchctl unload /var/containers/Bundle/Application/.jbroot-*/Library/LaunchDaemons/com.yk.enginelite.plist 2>/dev/null; uicache -a"
