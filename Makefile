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

all:
	# Workstation
	#
	# build                   Build the application requirements
	# watch                   Watch for changes and rebuild

build:
	# Build the application requirements
	@

watch:
	# Watch for changes and rebuild
	@$(LS) $(WATCH_FILES) | $(ENTR) -r $(MAKE) start
