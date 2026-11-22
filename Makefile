TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES =

include $(THEOS)/makefiles/common.mk

TOOL_NAME = ykenginelite

ykenginelite_FILES = main.m \
	Compat/YKHTTPServerCompat.m \
	Compat/SSZipArchiveCompat.m \
	Recovered/YKCryptoNetworkModules.m \
	Recovered/YKUtilityModules.m \
	Recovered/YKUIModule.m \
	Recovered/YKHTTPRouter.m

ykenginelite_FRAMEWORKS = Foundation UIKit Network Security NetworkExtension
ykenginelite_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
ykenginelite_LDFLAGS = -lobjc

include $(THEOS_MAKE_PATH)/tool.mk

after-install::
	install.exec "launchctl unload /var/jb/Library/LaunchDaemons/com.yk.enginelite.plist 2>/dev/null; launchctl load /var/jb/Library/LaunchDaemons/com.yk.enginelite.plist"
