MAKEFLAGS += --warn-undefined-variables -j1
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:
.PHONY: check-root

# Environment Variables
UNPRIVILEGED_USER ?= jack
GROUPS ?= lp,wheel,uucp,lock,video,audio,vboxusers,docker
IP ?= 10.0.0.99

# Less volatile settings
WATCH_FILES ?= README.md
PACMAN_MIRRORS_URL ?= https://www.archlinux.org/mirrorlist/?country=DE&protocol=https&use_mirror_status=on

export UNPRIVILEGED_USER

# Host binaries
AWK ?= awk
BASH ?= bash
BOOTCTL ?= bootctl
BUNDLE ?= bundle
CAT ?= cat
CD ?= cd
CHMOD ?= chmod
CHOWN ?= chown
CP ?= cp
CURL ?= curl
CUT ?= cut
DATE ?= date
DIFF ?= diff
DOCKER ?= docker
ECHO ?= echo
ENTR ?= entr
EXIT ?= exit
FIND ?= find
GEM ?= gem
GETENT ?= getent
GIT ?= git
GREP ?= grep
GVIM ?= gvim
I3_MSG ?= i3-msg
JQ ?= jq
LN ?= ln
LS ?= ls
MAKEPKG ?= makepkg
MKDIR ?= mkdir
MV ?= mv
NODE ?= node
NPM ?= npm
NPROC ?= nproc
PACMAN ?= pacman
PARALLEL ?= parallel
PASSWD ?= passwd
PKGFILE ?= pkgfile
PRINTF ?= printf
RANKMIRRORS ?= rankmirrors
READ ?= read
RM ?= rm
RUBY ?= ruby
SED ?= sed
SORT ?= sort
SSH_COPY_ID ?= ssh-copy-id
SSH ?= ssh
SUDO ?= sudo
SYSTEMCTL ?= systemctl
TAIL ?= tail
TEE ?= tee
TEST ?= test
TOC ?= toc
TR ?= tr
USERADD ?= useradd
XARGS ?= xargs
YAY ?= yay

check-root:
ifneq ($(USER),root)
	# The workstation suite MUST be run as root. (not as $(USER))
	@$(EXIT) 1
endif

include check-root

all:
	# Workstation
	#
	# shell                   Open an interactive remote connection
	# install-packages        Install all software packages
	# configure               Configure the workstation system
	#
	# build                   Build the application requirements
	# watch                   Watch for changes and rebuild
	# update                  Update all runtime lists

shell: shell-id-authorization
	# Connect to the remote machine
	@$(SSH) \
		-o PreferredAuthentications=publickey \
		-o PubkeyAuthentication=yes \
		$(UNPRIVILEGED_USER)@$(IP)

shell-id-authorization:
	# Probe SSH connection
	@($(SSH) \
		-o PreferredAuthentications=publickey \
		-o PubkeyAuthentication=yes \
		$(UNPRIVILEGED_USER)@$(IP) \
		exit) \
		|| ( \
			$(ECHO) '# Install the current SSH id to the new system'; \
			$(SSH_COPY_ID) \
				-o PreferredAuthentications=password \
				-o PubkeyAuthentication=no \
				$(UNPRIVILEGED_USER)@$(IP); \
		)

build: \
	update-readme-toc

watch:
	# Watch for changes and rebuild
	@$(LS) $(WATCH_FILES) | $(ENTR) $(MAKE) build

update: \
	update-readme-toc \
	update-extra-packages-list \
	update-npm-packages-list \
	update-gem-packages-list \
	update-pkgfile-database

update-readme-toc:
	# Update the README.md table of contents
	@$(ECHO) '<!-- TOC-START -->' > README.md.toc
	@$(TOC) README.md | $(SED) '/^$$/d' >> README.md.toc
	@$(ECHO) '<!-- TOC-END -->' >> README.md.toc
	@$(SED) \
		-e '/<!-- TOC-START -->/,/<!-- TOC-END -->/!b' \
		-e '/<!-- TOC-END -->/!d;r README.md.toc' \
		-e 'd' README.md > README.md.new
	@$(MV) -f README.md.new README.md
	@$(RM) README.md.toc

update-pacman-mirror-list:
	# Update and rank all german pacman mirrors
	@$(SUDO) $(PACMAN) --noconfirm -S pacman-contrib
	@$(CURL) -s "$(PACMAN_MIRRORS_URL)" \
		| $(SED) -e 's/^#Server/Server/' -e '/^#/d' \
		| $(RANKMIRRORS) -n 5 - \
		> etc/pacman.d/mirrorlist

update-extra-packages-list:
	# Update the extra packages list from the current system
	@$(PACMAN) -Qqe > packages/extra

update-npm-packages-list:
	# Update the npm packages list from the current system
	@$(NPM) list -g --depth=0 2>/dev/null \
		| $(GREP) '@' \
		| $(CUT) -d' ' -f2 \
		| $(SED) -e 's/@/ /g' > packages/npm || true

update-gem-packages-list:
	# Update the gem packages list from the current system
	@$(SUDO) -u $(UNPRIVILEGED_USER) $(GEM) query \
		| $(GREP) -vF '(default:' \
		| $(TR) -d '(' | $(TR) -d ')' | $(TR) -d ',' > packages/gem

update-pkgfile-database:
	# Update the pkgfile database
	@$(PKGFILE) --update

workstation: \
	install-packages \
	configure

install-packages: \
	install-base-packages \
	install-yay \
	configure-pacman \
	install-groups-packages \
	install-extra-packages \
	install-gem-packages \
	install-npm-packages

install-base-packages:
	# Install all base packages
	@$(CAT) packages/base \
		| $(GREP) -vP '^#|^$$$$' | $(TR) '\n' ' ' | $(XARGS) -r -I{} \
			$(SHELL) -c '$(SUDO) $(PACMAN) \
				-S --needed --noconfirm {}'

install-yay: configure-sudoers configure-gpg
	# Install the AUR pacman manager Yay
ifeq ($(shell which yay),)
	@$(PACMAN) --noconfirm -S --needed git base-devel
	@$(RM) -rf /tmp/yay /tmp/makepkg
	@$(GIT) clone https://aur.archlinux.org/yay.git /tmp/yay
	@$(CHMOD) ugo+rwx -R /tmp/yay
	@$(CD) /tmp/yay && $(SUDO) -u $(UNPRIVILEGED_USER) \
		$(MAKEPKG) --noconfirm -si
endif

install-groups-packages:
	# Install all base packages
	@$(CAT) packages/groups \
		| $(GREP) -vP '^#|^$$$$' | $(TR) '\n' ' ' | $(XARGS) -r -I{} \
			$(SHELL) -c '$(SUDO) $(PACMAN) \
				-S --needed --noconfirm {}'

install-extra-packages:
	# Take care of all glitches
	@glitches/uninstall-minimal-vim
	@glitches/uninstall-rxvt-unicode
	@glitches/install-gamin
	# Check for missing extra packages
	@$(PACMAN) -Qq | $(SORT) -u > /tmp/pkgs.actual
	@$(CAT) packages/extra | $(SORT) -u > /tmp/pkgs.expected-extra
	@$(DIFF) --new-line-format='' --unchanged-line-format='' \
		/tmp/pkgs.expected-extra /tmp/pkgs.actual \
		| $(GREP) -vP '^#|^$$$$' > /tmp/pkgs.missing || true
	# Install all extra packages
	@$(CAT) /tmp/pkgs.missing \
		| $(GREP) -vP '^#|^$$$$' | $(TR) '\n' ' ' | $(XARGS) -r -I{} \
			$(SHELL) -c '$(SUDO) -u $(UNPRIVILEGED_USER) $(YAY) \
				-S --needed --noconfirm {}' || true

install-gem-packages:
	# Install all Ruby Gem packages
	@$(PACMAN) --needed --noconfirm -S parallel
	@$(RM) -rf /tmp/gems /tmp/gems.actual
	@$(SUDO) -u $(UNPRIVILEGED_USER) $(GEM) query > /tmp/gems.actual
	@$(CAT) packages/gem | $(GREP) -vP '^#|^$$$$' | while $(READ) line; do \
			name=$$($(ECHO) "$$line" | $(CUT) -d ' ' -f1); \
			$(ECHO) "$$line" | $(CUT) -d ' ' -f2- | $(TR) ' ' "\n" \
				| while $(READ) version; do \
					$(ECHO) "$${name}|$${version}" >> /tmp/gems; \
				done; \
		done
	@$(PARALLEL) -a /tmp/gems -j30 --bar --colsep '\|' \
		--retry-failed --retries 5 \
		'$(GREP) -P "^{1} .*[ (]{2}[ ,)]" /tmp/gems.actual \
				>/dev/null 2>&1 \
			|| $(SUDO) -u $(UNPRIVILEGED_USER) \
				$(GEM) install --conservative {1} -v "= {2}"'
	@$(RM) -rf /tmp/gems /tmp/gems.actual

install-npm-packages:
	# Install all NPM packages
	@$(CAT) packages/npm | $(GREP) -vP '^#|^$$$$' | while $(READ) line; do \
		name=$$($(ECHO) "$$line" | $(CUT) -d ' ' -f1); \
		$(ECHO) "$$line" | $(CUT) -d ' ' -f2- | $(TR) ' ' "\n" \
			| while $(READ) version; do \
				[ $$(NODE_PATH=/usr/lib/node_modules $(NODE) -p \
					"require('$${name}/package.json').version" \
					2>/dev/null) \
					== "$$version" 2>/dev/null ] \
					&& $(ECHO) "$$name@$$version installed" \
					|| $(NPM) -g install "$${name}@$${version}"; \
			done; \
		done

etc-commit:
	# Commit the current state of /etc
	@$(CD) /etc && $(GIT) add -A . \
		&& $(GIT) commit -am 'version-$(shell $(DATE) +%s)'

commit:
	# Commit the current state of the workstation repository
	@$(SUDO) -u $(UNPRIVILEGED_USER) $(SHELL) -c '\
		$(GIT) add -A . \
		&& $(GIT) commit -am "Automated backup. ($(shell $(DATE) +%s))" \
		&& $(GIT) pull \
		&& $(GIT) push'

configure: \
	configure-versioned-etc \
	configure-bootloader \
	configure-pacman \
	configure-gpg \
	configure-directories \
	configure-user \
	configure-sudoers \
	configure-package-compilation \
	configure-periodic-trim \
	configure-sysctl \
	configure-watchdogs \
	configure-irqbalance \
	configure-amdgpu \
	configure-ups \
	configure-printer \
	configure-cron \
	configure-beep \
	configure-sound

configure-versioned-etc:
	# Configure a versioned /etc via git
	@$(TEST) -d /etc/.git || ( \
		$(CD) /etc; \
		$(GIT) init; \
		$(GIT) config user.email 'etc@localhost'; \
		$(GIT) config user.name 'Workstation'; \
	)
	$(MAKE) --no-print-directory etc-commit

configure-bootloader: \
	update-bootloader \
	install-bootloader-config

update-bootloader:
	# Update the bootloader
	@$(BOOTCTL) update

install-bootloader-config:
	# Update the bootloader settings
	@$(CP) boot/loader/loader.conf /boot/loader/loader.conf
	@$(CP) boot/loader/entries/arch.conf /boot/loader/entries/arch.conf

configure-pacman:
	# Configure pacman
	@$(CP) etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist
	@$(SUDO) $(PACMAN) -Sy
	@$(SUDO) $(PACMAN) --needed --noconfirm -S aria2
	@$(CP) etc/pacman.conf /etc/pacman.conf
	@$(SUDO) $(PACMAN) -Sy

configure-gpg: configure-user
	# Configure a GPG keyserver
	@$(MKDIR) -p /root/.gnupg
	@$(MKDIR) -p /home/$(UNPRIVILEGED_USER)/.gnupg
	@$(CP) home/.gnupg/dirmngr.conf \
		/root/.gnupg/dirmngr.conf
	@$(CP) home/.gnupg/dirmngr.conf \
		/home/$(UNPRIVILEGED_USER)/.gnupg/dirmngr.conf

configure-user:
	# Configure the dropped priviledge user
	@$(GETENT) passwd $(UNPRIVILEGED_USER) >/dev/null || ( \
		$(USERADD) -m -G $(GROUPS) -s /bin/bash $(UNPRIVILEGED_USER); \
		$(PASSWD) $(UNPRIVILEGED_USER); \
	)

configure-sysctl:
	# Update system controls
	@$(MKDIR) -p /etc/modules-load.d
	@$(MKDIR) -p /etc/udev/rules.d
	@$(MKDIR) -p /etc/sysctl.d/
	@$(CP) etc/modules-load.d/network.conf \
		/etc/modules-load.d/network.conf
	@$(CP) etc/udev/rules.d/60-ioschedulers.rules \
		/etc/udev/rules.d/60-ioschedulers.rules
	@$(CP) etc/sysctl.d/network.conf \
		/etc/sysctl.d/network.conf
	@$(CP) etc/sysctl.d/virtual-memory.conf \
		/etc/sysctl.d/virtual-memory.conf
	@$(CP) etc/sysctl.d/files.conf \
		/etc/sysctl.d/files.conf

configure-periodic-trim:
	# Configure periodic TRIM for all discardable filesystems
	@$(PACMAN) --needed --noconfirm -S util-linux
	@$(SYSTEMCTL) enable fstrim.timer

configure-package-compilation:
	# Configure package compilation optimizations
	@$(PACMAN) --needed --noconfirm -S pigz xz pbzip2 zstd expac pacman-contrib
	@$(CP) etc/makepkg.conf /etc/makepkg.conf

configure-watchdogs:
	# Configure the disabiling of watchdogs
	@$(CP) etc/sysctl.d/disable_watchdog.conf \
		/etc/sysctl.d/disable_watchdog.conf
	@$(CP) etc/modprobe.d/disable_watchdog.conf \
		/etc/modprobe.d/disable_watchdog.conf

configure-sudoers: configure-user
	# Configure sudoers
	@$(ECHO) '$(UNPRIVILEGED_USER) ALL=(ALL) NOPASSWD: ALL' \
		> /etc/sudoers.d/$(UNPRIVILEGED_USER)
	@$(CHMOD) 0440 /etc/sudoers.d/$(UNPRIVILEGED_USER)

configure-directories:
	# Configure system directories
	@$(MKDIR) -p /data/pictures
	@$(MKDIR) -p /data/projects
	@$(MKDIR) -p /data/docs
	@$(MKDIR) -p /data/other
	@$(MKDIR) -p /mnt/network/e5.lan
	@$(LN) -sf /mnt/network/e5.lan/media /data/media
	@$(LN) -sf /mnt/network/e5.lan/sync/workstation.lan/Music /data/music
	@$(LN) -sf /mnt/network/e5.lan/sync/workstation.lan/Backup /data/backup
	@$(CHOWN) $(UNPRIVILEGED_USER):$(UNPRIVILEGED_USER) -R /data

configure-irqbalance:
	# Configure automatic IRQ/CPU balancing
	@$(PACMAN) --needed --noconfirm -S irqbalance
	@$(SYSTEMCTL) enable irqbalance.service
	@$(SYSTEMCTL) restart irqbalance.service

configure-amdgpu:
	# Configure the AMD GPU/X11
	@$(PACMAN) --needed --noconfirm -S \
		xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon libva-mesa-driver \
		mesa-vdpau libvdpau-va-gl libva-vdpau-driver gstreamer-vaapi \
		gst-plugins-bad
	@$(SUDO) -u $(UNPRIVILEGED_USER) $(YAY) -S --needed --noconfirm \
		radeontop
	@$(CP) etc/X11/xorg.conf.d/20-amdgpu.conf \
		/etc/X11/xorg.conf.d/20-amdgpu.conf

test-ups-finish: configure-ups
configure-ups:
	# Configure the APC UPS
	@$(PACMAN) --needed --noconfirm -S apcupsd
	@$(CP) etc/apcupsd/apcupsd.conf /etc/apcupsd/apcupsd.conf
	@$(SYSTEMCTL) enable apcupsd.service
	@$(SYSTEMCTL) restart apcupsd.service

test-ups: configure-ups
	# Test the UPS configuration
	@$(SED) -i 's/^TIMEOUT .*/TIMEOUT 1/g' /etc/apcupsd/apcupsd.conf
	@$(SYSTEMCTL) restart apcupsd.service
	#
	# Now remove wall power from the UPS.
	# Observe that the machine powers down, in short order.

configure-printer:
	# Configure the printer
	@$(PACMAN) --needed --noconfirm -S cups
	@$(SYSTEMCTL) enable cups.service
	@$(SYSTEMCTL) restart cups.service

configure-cron:
	# Configure the cron service
	@$(PACMAN) --needed --noconfirm -S cronie
	@$(MKDIR) -p /etc/cron.minutely
	@$(CP) etc/cron.d/0minutely /etc/cron.d/0minutely
	@$(SYSTEMCTL) enable cronie.service
	@$(SYSTEMCTL) restart cronie.service

configure-beep:
	# Configure PC speaker (bell/beep)
	@$(CP) etc/modprobe.d/disable_beep.conf \
		/etc/modprobe.d/disable_beep.conf

configure-sound:
	# Configure sound/audio devices
	@$(CP) etc/modprobe.d/disable_sound.conf \
		/etc/modprobe.d/disable_sound.conf
	@$(CP) etc/pulse/default.pa \
		/etc/pulse/default.pa
