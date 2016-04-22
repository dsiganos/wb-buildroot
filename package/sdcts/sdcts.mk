SDCTS_VERSION = custom
SDCTS_SITE = $(TOPDIR)/../../sdcts
SDCTS_SITE_METHOD = local
SDCTS_AUTORECONF = YES
SDCTS_DEPENDENCIES = msd45n-binaries

$(eval $(autotools-package))
