MAKEFLAGS += --warn-undefined-variables -j1
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:
.PHONY:

# Host binaries
DOCKER ?= docker
SYSTEMCTL ?= systemctl
CP ?= cp

all: build install start

build:
	# Build the Docker image
	@$(DOCKER) build -t 'backups:latest'  .

install:
	# Install the systemd/docker service
	@$(CP) docker-backups.service /etc/systemd/system/docker-backups.service
	@$(SYSTEMCTL) systemctl daemon-reload
	@$(SYSTEMCTL) enable docker.service
	@$(SYSTEMCTL) enable docker-backups.service

start:
	# Start the backups container
	@$(SYSTEMCTL) restart docker-backups.service
	@$(SYSTEMCTL) status docker-backups.service
