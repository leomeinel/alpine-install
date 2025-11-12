#!/usr/bin/env sh
###
# File: prepare.sh
# Author: Leopold Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2025 Leopold Meinel & contributors
# SPDX ID: MIT
# URL: https://opensource.org/licenses/MIT
# -----
###

# Fail on error
set -e

# Define functions
log_err() {
    echo "$(basename "${0}"): ${*}"
}
sed_exit() {
    log_err "'sed' didn't replace, report this at https://github.com/leomeinel/arch-install/issues."
    exit 1
}

# Set ${SCRIPT_DIR}
SCRIPT_DIR="$(dirname -- "$(readlink -f -- "${0}")")"

# Configure networking
setup-interfaces
setup-ntp -c busybox

# Install packages that are dependencies for this script and configure repos
setup-apkrepos
## START sed
FILE=/etc/apk/repositories
STRING="^/media/"
grep -q "${STRING}" "${FILE}" || sed_exit
sed -i "\|${STRING}|d" "${FILE}"
STRING="^#\?http://"
grep -q "${STRING}" "${FILE}" || sed_exit
sed -i "s|${STRING}|https://|g" "${FILE}"
## END sed
apk update
xargs -r apk add -q <"${SCRIPT_DIR}/pkgs-prepare.txt"

# Notify user if script has finished successfully
echo "'$(basename "${0}")' has finished successfully."
