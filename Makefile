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
ASD ?= asd
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
ID ?= id
JQ ?= jq
LN ?= ln
LS ?= ls
MAKEPKG ?= makepkg
MKDIR ?= mkdir
MKINITCPIO ?= mkinitcpio
MV ?= mv
NODE ?= node
NPM ?= npm
NPROC ?= nproc
PACMAN ?= pacman
PARALLEL ?= parallel
PASSWD ?= passwd
PKGFILE ?= pkgfile
PLYMOUTH_SET_DEFAULT_THEME ?= plymouth-set-default-theme
PRINTF ?= printf
PSD ?= psd
RANKMIRRORS ?= rankmirrors
READ ?= read
RM ?= rm
RUBY ?= ruby
SED ?= sed
SORT ?= sort
SSH_COPY_ID ?= ssh-copy-id
SSH ?= ssh
SUDO ?= sudo
SYSCTL ?= sysctl
SYSTEMCTL ?= systemctl
TAIL ?= tail
TEE ?= tee
TEST ?= test
TIMEDATECTL ?= timedatectl
TOC ?= docs/toc
TR ?= tr
USERADD ?= useradd
XARGS ?= xargs
YAY ?= yay

# check-root:
ifneq ($(USER),root)
	# The workstation suite MUST be run as root. (not as $(USER))
	@$(EXIT) 1
endif

# include check-root

.reown:
	@$(CHOWN) $(UNPRIVILEGED_USER):$(UNPRIVILEGED_USER) -R .

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
	@$(MAKE) --no-print-directory .reown

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
	@$(CD) /etc && $(GIT) add -A . && ( \
		$(GIT) diff-index --quiet HEAD \
		|| $(GIT) commit -am 'version-$(shell $(DATE) +%s)' \
	)

commit: .reown
	# Commit the current state of the workstation repository
	@$(SUDO) -u $(UNPRIVILEGED_USER) $(SHELL) -c '\
		$(GIT) add -A . \
		&& ($(GIT) diff-index --quiet HEAD || \
			$(GIT) -c "commit.gpgsign=false" commit --quiet \
				-am "Automated backup. ($(shell $(DATE) +%s))") \
		&& $(GIT) pull --quiet \
		&& $(GIT) push --quiet'

configure: \
	configure-versioned-etc \
	configure-bootloader \
	configure-network \
	configure-time-sync \
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
	configure-smart-monitoring \
	configure-printer \
	configure-cron \
	configure-beep \
	configure-sound \
	configure-backups \
	configure-perf-monitoring \
	configure-browser-profiles \
	configure-docker \
	configure-boot-splash

configure-versioned-etc:
	# Configure a versioned /etc via git
	@$(TEST) -d /etc/.git || ( \
		$(CD) /etc; \
		$(GIT) init; \
		$(GIT) config user.email 'etc@localhost'; \
		$(GIT) config user.name 'Workstation'; \
	)
	@$(MAKE) --no-print-directory etc-commit

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

configure-network:
	# Configure the network interfaces
	@$(PACMAN) --needed --noconfirm -S networkmanager libteam
	@$(MKDIR) -p /etc/udev/rules.d/
	@$(CP) etc/udev/rules.d/10-network.rules \
		/etc/udev/rules.d/10-network.rules
	@$(CP) etc/NetworkManager/system-connections/team0.nmconnection \
		/etc/NetworkManager/system-connections/team0.nmconnection
	@$(CP) 'etc/NetworkManager/system-connections/team0 slave 1.nmconnection' \
		'/etc/NetworkManager/system-connections/team0 slave 1.nmconnection'
	@$(CP) 'etc/NetworkManager/system-connections/team0 slave 2.nmconnection' \
		'/etc/NetworkManager/system-connections/team0 slave 2.nmconnection'
	@$(CHMOD) 600 /etc/NetworkManager/system-connections/*
	@$(SYSTEMCTL) enable NetworkManager.service
	@$(SYSTEMCTL) restart NetworkManager.service
	@$(MKINITCPIO) -p linux

configure-time-sync:
	# Configure network-based time synchronization
	@$(CP) etc/systemd/timesyncd.conf /etc/systemd/timesyncd.conf
	@$(SYSTEMCTL) enable systemd-timesyncd.service
	@$(SYSTEMCTL) restart systemd-timesyncd.service
	@$(TIMEDATECTL) set-ntp true
	@$(TIMEDATECTL) status
	@$(TIMEDATECTL) timesync-status

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
	@$(CP) etc/systemd/logind.conf \
		/etc/systemd/logind.conf
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
	@$(CP) etc/sysctl.d/kernel.conf \
		/etc/sysctl.d/kernel.conf
	@$(SYSCTL) --system
	@$(SYSTEMCTL) daemon-reload

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
	@$(TEST) -L /data/media \
		|| $(LN) -sf /mnt/network/e5.lan/media /data/media
	@$(TEST) -L /data/music \
		|| $(LN) -sf /mnt/network/e5.lan/sync/workstation.lan/Music /data/music
	@$(TEST) -L /data/backup \
		|| $(LN) -sf /mnt/network/e5.lan/sync/workstation.lan/Backup /data/backup
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

configure-smart-monitoring:
	# Configure SMART disk monitoring
	@$(PACMAN) --needed --noconfirm -S smartmontools  libnotify procps-ng
	@$(MKDIR) -p /usr/share/smartmontools/smartd_warning.d
	@$(CP) etc/smartd.conf /etc/smartd.conf
	@$(CP) usr/share/smartmontools/smartd_warning.d/smartdnotify \
		/usr/share/smartmontools/smartd_warning.d/smartdnotify
	@$(CHMOD) +x /usr/share/smartmontools/smartd_warning.d/smartdnotify
	@$(SYSTEMCTL) enable smartd.service
	@$(SYSTEMCTL) restart smartd.service

test-smart-monitoring: configure-smart-monitoring
	# Test the UPS configuration
	@$(SED) -i 's/^\(DEVICESCAN .*\)/\1 -M test/g' /etc/smartd.conf
	@$(SYSTEMCTL) restart smartd.service
	#
	# Now you should have received an email and a system notification.
	#
	@$(MAKE) --no-print-directory configure-smart-monitoring

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

configure-backups: configure-cron
	# Configure automated backups of the system
	@$(PACMAN) --needed --noconfirm -S rdiff-backup rsync
	@$(MKDIR) -p /etc/cron.hourly
	@$(CP) etc/cron.hourly/sync-data /etc/cron.hourly/sync-data
	@$(CP) etc/cron.hourly/backup /etc/cron.hourly/backup
	@$(CHMOD) +x /etc/cron.hourly/*

configure-perf-monitoring:
	# Configure performance monitoring
	@$(PACMAN) --needed --noconfirm -S pcp cockpit packagekit \
		cockpit-pcp cockpit-dashboard cockpit-machines cockpit-podman
	@$(SUDO) -u $(UNPRIVILEGED_USER) $(YAY) --needed --noconfirm -S tuned
	@$(SYSTEMCTL) enable tuned.service
	@$(SYSTEMCTL) enable pmcd.service
	@$(SYSTEMCTL) enable pmlogger.service
	@$(SYSTEMCTL) restart tuned.service
	@$(SYSTEMCTL) restart pmcd.service
	@$(SYSTEMCTL) restart pmlogger.service

configure-browser-profiles:
	# Configure the user browser profiles
	@$(eval RTDIR=/run/user/$(shell $(ID) -u $(UNPRIVILEGED_USER)))
	@$(eval CNFDIR=/home/$(UNPRIVILEGED_USER)/.config)
	@$(PACMAN) --needed --noconfirm -S profile-sync-daemon
	@$(MKDIR) -p $(CNFDIR)/psd/
	@$(MKDIR) -p $(CNFDIR)/systemd/user/psd-resync.timer.d/
	@$(CP) home/.config/psd/psd.conf $(CNFDIR)/psd/psd.conf
	@$(CP) home/.config/systemd/user/psd-resync.timer.d/frequency.conf \
		$(CNFDIR)/systemd/user/psd-resync.timer.d/frequency.conf
	@$(CHOWN) $(UNPRIVILEGED_USER):$(UNPRIVILEGED_USER) -R \
		/home/$(UNPRIVILEGED_USER)
	@$(SUDO) -u $(UNPRIVILEGED_USER) XDG_RUNTIME_DIR=$(RTDIR) \
		$(SYSTEMCTL) --user enable psd.service
	@$(SUDO) -u $(UNPRIVILEGED_USER) XDG_RUNTIME_DIR=$(RTDIR) \
		$(SYSTEMCTL) --user start psd.service
	@$(SUDO) -u $(UNPRIVILEGED_USER) XDG_RUNTIME_DIR=$(RTDIR) \
		$(PSD) preview

configure-docker:
	# Configure the Docker service
	@$(PACMAN) --needed --noconfirm -S docker docker-compose \
		podman podman-compose anything-sync-daemon
	@$(MKDIR) -p /etc/systemd/system/asd-resync.timer.d
	@$(MKDIR) -p /etc/systemd/system/docker-sync-notify.service.d
	@$(CP) etc/asd.conf /etc/asd.conf
	@$(CP) etc/systemd/system/asd-resync.timer.d/frequency.conf \
		/etc/systemd/system/asd-resync.timer.d/frequency.conf
	@$(CP) etc/systemd/system/docker.service.d/override.conf \
		/etc/systemd/system/docker.service.d/override.conf
	@$(CP) etc/systemd/system/docker-sync-notify.service.d/notify.sh \
		/etc/systemd/system/docker-sync-notify.service.d/notify.sh
	@$(CP) etc/systemd/system/docker-sync-notify.service \
		/etc/systemd/system/docker-sync-notify.service
	@$(CHMOD) +x /etc/systemd/system/docker-sync-notify.service.d/notify.sh
	@$(SYSTEMCTL) daemon-reload
	@$(SYSTEMCTL) enable asd.service
	@$(SYSTEMCTL) enable docker.service
	@$(SYSTEMCTL) enable docker-sync-notify.service
	@$(SYSTEMCTL) stop docker.service
	@$(SYSTEMCTL) restart asd.service
	@$(SYSTEMCTL) start docker.service
	@$(SYSTEMCTL) restart docker-sync-notify.service

configure-boot-splash:
	# Configure a boot splash animation
	@$(PACMAN) -Qq | $(GREP) '^plymouth$$' >/dev/null 2>&1 \
		|| $(SUDO) -u $(UNPRIVILEGED_USER) $(YAY) --needed --noconfirm -S \
			plymouth
	@$(PACMAN) -Qq | $(GREP) '^plymouth-theme-connect-git$$' >/dev/null 2>&1 \
		|| $(SUDO) -u $(UNPRIVILEGED_USER) $(YAY) --needed --noconfirm -S \
			plymouth-theme-connect-git
	@$(CP) etc/mkinitcpio.conf \
		/etc/mkinitcpio.conf
	@$(CP) etc/plymouth/plymouthd.conf \
		/etc/plymouth/plymouthd.conf
	@$(CP) etc/systemd/system/sddm-plymouth.service.d/override.conf \
		/etc/systemd/system/sddm-plymouth.service.d/override.conf
	@$(CP) etc/systemd/system/plymouth-quit.service.d/override.conf \
		/etc/systemd/system/plymouth-quit.service.d/override.conf
	@$(CP) etc/systemd/system/plymouth-quit-wait.service.d/override.conf \
		/etc/systemd/system/plymouth-quit-wait.service.d/override.conf
	@$(CP) etc/systemd/system/plymouth-deactivate.service.d/override.conf \
		/etc/systemd/system/plymouth-deactivate.service.d/override.conf
	@$(SYSTEMCTL) disable sddm.service
	@$(SYSTEMCTL) enable sddm-plymouth.service
	@$(PLYMOUTH_SET_DEFAULT_THEME) -R connect
