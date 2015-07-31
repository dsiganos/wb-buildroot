SDCTS_VERSION = a4b847a35fe4715b01deaee11420240562ff5047
SDCTS_SITE = https://github.com/dsiganos/tspace_active_antenna.git
SDCTS_SITE_METHOD = git
#SDCTS_SITE_DEPENDENCIES =

define SDCTS_FIXUP_SOURCES
	rm -r $(@D)/{README.md,laird_releases,doc,images}
	rm $(@D)/sdcts/sdcts
	mv $(@D)/sdcts $(@D)/sdcts.tmpdir
	mv $(@D)/sdcts.tmpdir/.deps $(@D)
	mv $(@D)/sdcts.tmpdir/* $(@D)
	rmdir $(@D)/sdcts.tmpdir
endef

SDCTS_POST_EXTRACT_HOOKS += SDCTS_FIXUP_SOURCES

$(eval $(autotools-package))
