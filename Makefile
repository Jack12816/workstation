MAKEFLAGS += --warn-undefined-variables -j1
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:
.PHONY:

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
CP ?= cp
CURL ?= curl
CUT ?= cut
DIFF ?= diff
DOCKER ?= docker
ECHO ?= echo
ENTR ?= entr
FIND ?= find
GEM ?= gem
GETENT ?= getent
GIT ?= git
GREP ?= grep
GVIM ?= gvim
I3_MSG ?= i3-msg
JQ ?= jq
LS ?= ls
MAKEPKG ?= makepkg
MKDIR ?= mkdir
MV ?= mv
NPM ?= npm
NPROC ?= nproc
PACMAN ?= pacman
PASSWD ?= passwd
PRINTF ?= printf
RANKMIRRORS ?= rankmirrors
READ ?= read
RM ?= rm
RUBY ?= ruby
SED ?= sed
SORT ?= sort
SSH ?= ssh
SSH_COPY_ID ?= ssh-copy-id
DATE ?= date
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

all:
	# Workstation
	#
	# shell                   Open an interactive remote connection
	# install-packages        Install all software packages
	# configure               Configure the workstation system
	#
	# build                   Build the application requirements
	# watch                   Watch for changes and rebuild

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
	@$(SUDO) $(GEM) list \
		| $(GREP) -vF '(default:' \
		| $(TR) -d '(' | $(TR) -d ')' | $(TR) -d ',' > packages/gem

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
	# TODO: Implement this.

install-npm-packages:
	# Install all NPM packages
	# TODO: Implement this.

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
	configure-irqbalance

configure-versioned-etc:
	# Configure a versioned /etc via git
	@$(TEST) -d /etc/.git || ($(CD) /etc && $(GIT) init)
	@$(CD) /etc && $(GIT) add -A . \
		&& $(GIT) commit -am 'version-$(shell $(DATE) +%s)'

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
	@$(SUDO) $(PACMAN) --noconfirm -S aria2
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
	@$(CP) etc/udev/rules.d/60-ioschedulers.rules \
		/etc/udev/rules.d/60-ioschedulers.rules
	@$(CP) etc/sysctl.d/network.conf \
		/etc/sysctl.d/network.conf

configure-periodic-trim:
	# Configure periodic TRIM for all discardable filesystems
	@$(PACMAN) --noconfirm -S util-linux
	@$(SYSTEMCTL) enable fstrim.timer

configure-package-compilation:
	# Configure package compilation optimizations
	@$(PACMAN) --noconfirm -S pigz xz pbzip2 zstd expac pacman-contrib
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
	@$(MKDIR) -p /mnt/network/e5.lan
	@$(MKDIR) -p /data/pictures
	@$(MKDIR) -p /data/projects
	@$(MKDIR) -p /data/docs
	@$(MKDIR) -p /data/other
	@$(LN) -s /data/media /mnt/network/e5.lan/media
	@$(LN) -s /data/music /mnt/network/e5.lan/sync/workstation.lan/Music
	@$(LN) -s /data/backup /mnt/network/e5.lan/sync/workstation.lan/Backup

configure-irqbalance:
	# Configure automatic IRQ/CPU balancing
	@$(PACMAN) --noconfirm -S irqbalance
	@$(SYSTEMCTL) enable irqbalance.service
