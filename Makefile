MAKEFLAGS += --warn-undefined-variables -j1
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:
.PHONY:

# Environment Variables
WATCH_FILES ?= README.md

# Host binaries
AWK ?= awk
BASH ?= bash
BUNDLE ?= bundle
CAT ?= cat
CD ?= cd
CHMOD ?= chmod
CURL ?= curl
CUT ?= cut
DOCKER ?= docker
ECHO ?= echo
FIND ?= find
GIT ?= git
GREP ?= grep
GVIM ?= gvim
I3_MSG ?= i3-msg
JQ ?= jq
MKDIR ?= mkdir
MV ?= mv
NPROC ?= nproc
READ ?= read
RM ?= rm
RUBY ?= ruby
SED ?= sed
SORT ?= sort
SUDO ?= sudo
SYSTEMCTL ?= systemctl
TAIL ?= tail
TEE ?= tee
TEST ?= test
ENTR ?= entr
XARGS ?= xargs
LS ?= ls
TOC ?= toc

all:
	# Workstation
	#
	# build                   Build the application requirements
	# watch                   Watch for changes and rebuild

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

configure: \
	configure-bootloader \
	configure-sysctl \
	configure-package-compilation \
	configure-periodic-trim \
	configure-watchdogs

configure-bootloader: \
	update-bootloader \
	install-bootloader-config

update-bootloader:
	# Update the bootloader
	@bootctl update

install-bootloader-config:
	# Update the bootloader settings
	@$(CP) boot/loader/loader.conf /boot/loader/loader.conf
	@$(CP) boot/loader/entries/arch.conf /boot/loader/entries/arch.conf

configure-sysctl:
	# Update system controls

configure-periodic-trim:
	# Configure periodic TRIM for all discardable filesystems
	@pacman -S util-linux
	@systemctl enable fstrim.timer

configure-package-compilation:
	# Configure package compilation optimizations
	@pacman -S pigz xz pbzip2 zstd expac pacman-contrib
	@$(CP) etc/makepkg.conf /etc/makepkg.conf

configure-watchdogs:
	# Configure the disabiling of watchdogs
	@$(CP) etc/sysctl.d/disable_watchdog.conf \
		/etc/sysctl.d/disable_watchdog.conf
	@$(CP) etc/modprobe.d/disable_watchdog.conf \
		/etc/modprobe.d/disable_watchdog.conf
