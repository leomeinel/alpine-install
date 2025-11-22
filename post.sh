#!/usr/bin/env bash
###
# File: post.sh
# Author: Leopold Johannes Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2025 Leopold Johannes Meinel & contributors
# SPDX ID: Apache-2.0
# URL: https://www.apache.org/licenses/LICENSE-2.0
###

# FIXME: This is not usable at the moment, just my notes.
exit

apk update
apk upgrade
vi /etc/apk/repositories
# Uncomment community
apk add htop neovim fastfetch eza bat lxc bridge lxcfs lxc-download xz lxc-templates lxc-bridge iptables lsblk debootstrap rsync openssh doas

# Edit /etc/ssh/sshd_config.d/50-alpine-install.conf
addgroup ssh-allow
adduser systux ssh-allow
adduser systux wheel

doas rc-update add dnsmasq.lxcbr0 boot
doas service dnsmasq.lxcbr0 start

doas sh -c 'printf "%s\n" "dhcp-host=debian-forgejo-runner,10.44.10.20" >>/etc/lxc/dnsmasq.conf'

# Distribution:
# debian
# Release:
# trixie
# Architecture:
# arm64

doas rc-update add cgroups boot
doas lxc-start -n debian-forgejo-runner

doas sh -c 'lxc-create -n guest1 -f /etc/lxc/default.conf -t download'

doas service dnsmasq.lxcbr0 restart
