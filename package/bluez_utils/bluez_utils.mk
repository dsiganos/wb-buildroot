#############################################################
#
# bluez_utils
#
#############################################################

BLUEZ_UTILS_VERSION = 5.10
BLUEZ_UTILS_SOURCE = bluez-$(BLUEZ_UTILS_VERSION).tar.gz
BLUEZ_UTILS_SITE = $(BR2_KERNEL_MIRROR)/linux/bluetooth
BLUEZ_UTILS_INSTALL_STAGING = YES
BLUEZ_UTILS_DEPENDENCIES = dbus libglib2 readline libical udev
BLUEZ_UTILS_CONF_OPT = --enable-test --enable-tools --disable-systemd
BLUEZ_UTILS_AUTORECONF = YES
BLUEZ_UTILS_LICENSE = GPLv2+ LGPLv2.1+
BLUEZ_UTILS_LICENSE_FILES = COPYING COPYING.LIB

# BlueZ 3.x compatibility
ifeq ($(BR2_PACKAGE_BLUEZ_UTILS_COMPAT),y)
BLUEZ_UTILS_CONF_OPT +=	\
	--enable-hidd	\
	--enable-pand	\
	--enable-sdp	\
	--enable-dund
endif

# audio support
ifeq ($(BR2_PACKAGE_BLUEZ_UTILS_AUDIO),y)
BLUEZ_UTILS_DEPENDENCIES +=	\
	alsa-lib		\
	libsndfile
BLUEZ_UTILS_CONF_OPT +=	\
	--enable-alsa	\
	--enable-audio
else
BLUEZ_UTILS_CONF_OPT +=	\
	--disable-alsa	\
	--disable-audio
endif

# USB support
ifeq ($(BR2_PACKAGE_BLUEZ_UTILS_USB),y)
BLUEZ_UTILS_DEPENDENCIES += libusb
BLUEZ_UTILS_CONF_OPT +=	\
	--enable-usb
else
BLUEZ_UTILS_CONF_OPT +=	\
	--disable-usb
endif

define BLUEZ_UTILS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D package/bluez_utils/S95bluetooth $(TARGET_DIR)/etc/init.d/opt/S95bluetooth
endef

define BLUEZ_UTILS_UNINSTALL_TARGET_CMDS
	rm -f $(TARGET_DIR)/etc/init.d/opt/S95bluetooth
endef

$(eval $(autotools-package))
