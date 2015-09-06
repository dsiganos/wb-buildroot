SDCTS_VERSION = custom
SDCTS_SITE = $(TOPDIR)/../../sdcts
SDCTS_SITE_METHOD = local
SDCTS_AUTORECONF = YES
#SDCTS_SITE_DEPENDENCIES =

$(eval $(autotools-package))
