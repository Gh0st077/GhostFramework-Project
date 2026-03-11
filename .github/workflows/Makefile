TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GhostFramework
GhostFramework_FILES = BypassLoader.mm
GhostFramework_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
