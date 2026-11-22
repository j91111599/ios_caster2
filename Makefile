TARGET := iphone:clang:latest:14.0
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
	YKEngineLite/Recovered/YKUIModule.m
ykenginelite_FRAMEWORKS = Foundation UIKit Network Security NetworkExtension
ykenginelite_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -Wno-nullability-completeness -IYKEngineLite/Compat -IYKEngineLite/Recovered
ykenginelite_LDFLAGS = -fuse-ld=lld
include $(THEOS_MAKE_PATH)/tool.mk

# ---------- App（SpringBoard 图标 + 界面 + 进程内引擎）----------
APPLICATION_NAME = YKEngineApp
YKEngineApp_FILES = YKEngineLite/App/main.m
YKEngineApp_FRAMEWORKS = UIKit Foundation
YKEngineApp_CFLAGS = -fobjc-arc
YKEngineApp_LDFLAGS = -fuse-ld=lld
YKEngineApp_INSTALL_PATH = /Applications
YKEngineApp_RESOURCE_FILES = YKEngineLite/Resources
include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall -9 ykenginelite 2>/dev/null; launchctl unload /var/containers/Bundle/Application/.jbroot-*/Library/LaunchDaemons/com.yk.enginelite.plist 2>/dev/null; uicache -a"