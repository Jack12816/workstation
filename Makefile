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
