# 说明：Recovered/YKHTTPRouter.m 为文档级重建（引用引擎原语 YKOpenApplication 等），
# 不参与 Lite 编译；其路由契约由 main.m 的 app 分派覆盖。
TARGET := iphone:clang:latest:14.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES =

include $(THEOS)/makefiles/common.mk

TOOL_NAME = ykenginelite

ykenginelite_FILES = \
	YKEngineLite/main.m \
	YKEngineLite/Compat/YKHTTPServerCompat.m \
	YKEngineLite/Compat/SSZipArchiveCompat.m \
	YKEngineLite/Recovered/YKCryptoNetworkModules.m \
	YKEngineLite/Recovered/YKUtilityModules.m \
	YKEngineLite/Recovered/YKUIModule.m

ykenginelite_FRAMEWORKS = Foundation UIKit Network Security NetworkExtension
ykenginelite_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable \
	-IYKEngineLite/Compat -IYKEngineLite/Recovered
ykenginelite_LDFLAGS = -fuse-ld=lld

include $(THEOS_MAKE_PATH)/tool.mk

after-install::
	install.exec "launchctl unload /var/jb/Library/LaunchDaemons/com.yk.enginelite.plist 2>/dev/null; launchctl load /var/jb/Library/LaunchDaemons/com.yk.enginelite.plist"