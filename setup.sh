#!/usr/bin/env bash
###
# File: setup.sh
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
    /usr/bin/logger -s -p local0.err <<<"$(basename "${0}"): ${*}"
}
log_warning() {
    /usr/bin/logger -s -p local0.warning <<<"$(basename "${0}"): ${*}"
}
sed_exit() {
    log_err "'sed' didn't replace, report this at https://github.com/leomeinel/arch-install/issues."
    exit 1
}

# Source config
SCRIPT_DIR="$(dirname -- "$(readlink -f -- "${0}")")"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}"/install.conf

# Groups
addgroup -S proc

# Configure base system
setup-devd mdev
setup-keymap "${KEYLAYOUT}" "${KEYLAYOUT}"
setup-hostname -n "${HOSTNAME}"."${DOMAIN}"
## Configure /etc/hosts
{
    echo "127.0.0.1  localhost localhost.localdomain"
    echo "127.0.1.1  ${HOSTNAME}.${DOMAIN}	${HOSTNAME}"
    echo "::1  ip6-localhost ip6-localhost.localdomain ip6-loopback ip6-loopback.localdomain"
    echo "ff02::1  ip6-allnodes"
    echo "ff02::2  ip6-allrouters"
} >/etc/hosts
rc-service hostname restart
sleep 10
setup-timezone -z "${TIMEZONE}"
setup-user -a -k "${SYSUSER_PUBKEY}" -g proc "${SYSUSER}"
passwd "${SYSUSER}"
passwd root
setup-sshd

# Unmount everything from /mnt
mountpoint -q /mnt &&
    umount -AR /mnt

# Load kernel modules
modprobe btrfs

# Prompt user for RAID
read -rp "Set up RAID? (Type 'yes' in capital letters): " choice
case "${choice}" in
"YES")
    ## Detect disks
    readarray -t DISKS < <(lsblk -drnpo NAME -I 259,8,254 | tr -d "[:blank:]")
    # FIXME: This is only supported by eudev
    # DISKS_LENGTH="${#DISKS[@]}"
    # for ((i = 0; i < DISKS_LENGTH; i++)); do
    #     if udevadm info -q property --property=ID_BUS --value "${DISKS[${i}]}" | grep -q "usb"; then
    #         unset 'DISKS[${i}]'
    #         continue
    #     fi
    #     DISKS=("${DISKS[@]}")
    # done
    if [[ "${#DISKS[@]}" -lt 2 ]]; then
        log_err "There are less than 2 disks attached."
        exit 1
    fi
    if [[ "${#DISKS[@]}" -gt 2 ]]; then
        log_warning "There are more than 2 disks attached."
        lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254
        ### Prompt user to select 2 RAID members
        read -rp "Which disk should be the first RAID member? (Type '/dev/sdX' fex.): " choice0
        read -rp "Which disk should be the second RAID member? (Type '/dev/sdY' fex.): " choice1
        if [[ "$(tr -d "[:space:]" <<<"${choice0}")" != "$(tr -d "[:space:]" <<<"${choice1}")" ]] && lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254 "${choice0}" "${choice1}"; then
            echo "Using '${choice0}' and '${choice1}' for installation."
            DISKS=(
                "${choice0}"
                "${choice1}"
            )
        else
            log_err "Drives not suitable for installation."
            exit 1
        fi
    fi
    ## Set size for partition of larger disk
    SIZE1="$(lsblk -drnbo SIZE "${DISKS[0]}" | tr -d "[:space:]")"
    SIZE2="$(lsblk -drnbo SIZE "${DISKS[1]}" | tr -d "[:space:]")"
    ### Check that both drives are over 10GiB
    if [[ "${SIZE1}" -lt 10737418240 ]] || [[ "${SIZE2}" -lt 10737418240 ]]; then
        log_err "Drive too small for installation."
        exit 1
    fi
    if [[ "${SIZE1}" -eq "${SIZE2}" ]]; then
        DISK1="${DISKS[0]}"
        DISK2="${DISKS[1]}"
        PART_SIZE=0
    else
        log_warning "The attached disks don't have the same size."
        log_warning "The larger disk will have unpartitioned space remaining."
        if [[ "${SIZE1}" -gt "${SIZE2}" ]]; then
            DISK1="${DISKS[0]}"
            DISK2="${DISKS[1]}"
            PART_SIZE="$((-(("${SIZE1}" - "${SIZE2}") / 1024)))K"
        else
            DISK1="${DISKS[1]}"
            DISK2="${DISKS[0]}"
            PART_SIZE="$((-(("${SIZE2}" - "${SIZE1}") / 1024)))K"
        fi
    fi
    ## Prompt user to confirm erasure
    read -rp "Erase '${DISK1}' and '${DISK2}'? (Type 'yes' in capital letters): " choice
    case "${choice}" in
    "YES")
        echo "Erasing '${DISK1}' and '${DISK2}'..."
        ;;
    *)
        log_err "User aborted erasing '${DISK1}' and '${DISK2}'."
        exit 1
        ;;
    esac
    ;;
*)
    ## Prompt user for disk
    ## INFO: USB will be valid to allow external SSDs
    lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254,179
    echo "INFO: You can't use the same drive for '/boot' and '/'."
    read -rp "Which disk do you want to use for /boot? (Type '/dev/sdX' fex.): " choice
    if lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254,179 "${choice}"; then
        ### Set DISK1
        BOOT1="${choice}"
        echo "Erasing '${BOOT1}'..."
    else
        log_err "Drive not suitable for installation."
        exit 1
    fi
    lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254,179
    read -rp "Which disk do you want to erase? (Type '/dev/sdX' fex.): " choice
    if lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254,179 "${choice}"; then
        ### Set DISK1
        DISK1="${choice}"
        ### Check that the drive is over 10GiB
        SIZE1="$(lsblk -drnbo SIZE "${DISK1}" | tr -d "[:space:]")"
        if [[ "${SIZE1}" -lt 10737418240 ]]; then
            log_err "Drive too small for installation."
            exit 1
        fi
        echo "Erasing '${DISK1}'..."
    else
        log_err "Drive not suitable for installation."
        exit 1
    fi
    ;;
esac

# Check that "${BOOT1}" != "${DISK1}"
if [[ "${BOOT1}" == "${DISK1}" ]]; then
    log_err "You can't use the same drive for '/boot' and '/'."
    exit 1
fi

# Erase disks
## Deactivate all vgs
vgchange -an || true
## Stop all mdadm RAIDs
mdadm -Ss || true
## Unmount disks that might be mounted by install
mountpoint -q /.modloop &&
    umount -AR /.modloop
findmnt -S "${BOOT1}" >/dev/null 2>&1 &&
    umount "${BOOT1}"
findmnt -S "${DISK1}" >/dev/null 2>&1 &&
    umount "${DISK1}"
for partition in $(lsblk -rnpo TYPE,NAME "${BOOT1}" | grep "part" | sed 's/part//g' | tr -d " "); do
    findmnt -S "${partition}" >/dev/null 2>&1 &&
        umount "${partition}"
done
for partition in $(lsblk -rnpo TYPE,NAME "${DISK1}" | grep "part" | sed 's/part//g' | tr -d " "); do
    findmnt -S "${partition}" >/dev/null 2>&1 &&
        umount "${partition}"
done
## Use dd, sgdisk and wipefs to wipe the header and more to make sure that it is erased
sgdisk -o "${BOOT1}" || true
sgdisk -Z "${BOOT1}" || true
wipefs -a "${BOOT1}"
dd if=/dev/zero of="${DISK1}" bs=1M conv=fsync count=1000
sgdisk -o "${DISK1}" || true
sgdisk -Z "${DISK1}" || true
wipefs -a "${DISK1}"
dd if=/dev/zero of="${DISK1}" bs=1M conv=fsync count=8192
if [[ -n "${DISK2}" ]]; then
    sgdisk -o "${DISK2}" || true
    sgdisk -Z "${DISK2}" || true
    wipefs -a "${DISK2}"
    dd if=/dev/zero of="${DISK2}" bs=1M conv=fsync count=8192
fi
## Prompt user if they want to secure wipe the whole disk
if [[ -n "${DISK2}" ]]; then
    read -rp "Secure wipe '${DISK1}' and '${DISK2}'? (Type 'yes' in capital letters): " choice
    if [[ "${choice}" == "YES" ]]; then
        dd if=/dev/urandom of="${DISK1}" bs="$(stat -c "%o" "${DISK1}")" conv=fsync || true
        dd if=/dev/urandom of="${DISK2}" bs="$(stat -c "%o" "${DISK2}")" conv=fsync || true
    fi
else
    read -rp "Secure wipe '${BOOT1}'? (Type 'yes' in capital letters): " choice
    if [[ "${choice}" == "YES" ]]; then
        dd if=/dev/urandom of="${BOOT1}" bs="$(stat -c "%o" "${BOOT1}")" conv=fsync || true
    fi
    read -rp "Secure wipe '${DISK1}'? (Type 'yes' in capital letters): " choice
    if [[ "${choice}" == "YES" ]]; then
        dd if=/dev/urandom of="${DISK1}" bs="$(stat -c "%o" "${DISK1}")" conv=fsync || true
    fi
fi

# Partition disks
sgdisk -n 0:0:+1G -t 1:ef00 "${BOOT1}"
if [[ -n "${DISK2}" ]]; then
    sgdisk -n 0:0:"${PART_SIZE}" -t 1:fd00 "${DISK1}"
    sgdisk -n 0:0:0 -t 1:fd00 "${DISK2}"
else
    sgdisk -n 0:0:0 -t 1:8300 "${DISK1}"
fi

# Scan /sys and populate
mdev -fs

# Configure raid and encryption
BOOT1P1="$(lsblk -rnpo TYPE,NAME "${BOOT1}" | grep "part" | sed 's/part//g' | sed -n '1p' | tr -d "[:space:]")"
DISK1P1="$(lsblk -rnpo TYPE,NAME "${DISK1}" | grep "part" | sed 's/part//g' | sed -n '1p' | tr -d "[:space:]")"
if [[ -n "${DISK2}" ]]; then
    DISK2P1="$(lsblk -rnpo TYPE,NAME "${DISK2}" | grep "part" | sed 's/part//g' | sed -n '1p' | tr -d "[:space:]")"
    ## Configure raid1
    RAID_DEVICE=/dev/md/md0
    mdadm -Cv --homehost=any -N md0 -l 1 -n 2 -e default -b internal "${RAID_DEVICE}" "${DISK1P1}" "${DISK2P1}"
fi

# Configure lvm
if [[ -z "${DISK2}" ]]; then
    pvcreate "${DISK1P1}"
    vgcreate vg0 "${DISK1P1}"
else
    pvcreate "${RAID_DEVICE}"
    vgcreate vg0 "${RAID_DEVICE}"
fi
lvcreate -l "${DISK_ALLOCATION[0]}" vg0 -n lv0
lvcreate -l "${DISK_ALLOCATION[1]}" vg0 -n lv1
lvcreate -l "${DISK_ALLOCATION[2]}" vg0 -n lv2
lvcreate -l "${DISK_ALLOCATION[3]}" vg0 -n lv3
lvcreate -l "${DISK_ALLOCATION[4]}" vg0 -n lv4

# Format boot
mkfs.fat -n BOOT -F32 "${BOOT1P1}"

# Configure mounts
## Create subvolumes
SUBVOLUMES_LENGTH="${#SUBVOLUMES[@]}"
create_subs0() {
    mkfs.btrfs -L "${3}" "${4}"
    mount "${4}" /mnt
    btrfs subvolume create /mnt/@"${2}"
    btrfs subvolume create /mnt/@"${2}"_snapshots
    create_subs1 "${1}"
    umount /mnt
}
create_subs1() {
    for ((a = 0; a < SUBVOLUMES_LENGTH; a++)); do
        if [[ "${SUBVOLUMES[${a}]}" != "${1}" ]] && grep -q "^${1}" <<<"${SUBVOLUMES[${a}]}"; then
            btrfs subvolume create /mnt/@"${CONFIGS[${a}]}"
            btrfs subvolume create /mnt/@"${CONFIGS[${a}]}"_snapshots
        fi
    done
}
LV0=/dev/mapper/vg0-lv0
LV1=/dev/mapper/vg0-lv1
LV2=/dev/mapper/vg0-lv2
LV3=/dev/mapper/vg0-lv3
LV4=/dev/mapper/vg0-lv4
for ((i = 0; i < SUBVOLUMES_LENGTH; i++)); do
    case "${SUBVOLUMES[${i}]}" in
    /)
        mkfs.btrfs -L ROOT "${LV0}"
        mount "${LV0}" /mnt
        btrfs subvolume create /mnt/@
        btrfs subvolume create /mnt/@snapshots
        umount /mnt
        ;;
    /usr/)
        create_subs0 "${SUBVOLUMES[${i}]}" "${CONFIGS[${i}]}" "USR" "${LV1}"
        ;;
    /nix/)
        create_subs0 "${SUBVOLUMES[${i}]}" "${CONFIGS[${i}]}" "NIX" "${LV2}"
        ;;
    /var/)
        create_subs0 "${SUBVOLUMES[${i}]}" "${CONFIGS[${i}]}" "VAR" "${LV3}"
        ;;
    /home/)
        create_subs0 "${SUBVOLUMES[${i}]}" "${CONFIGS[${i}]}" "HOME" "${LV4}"
        ;;
    esac
done
## Mount subvolumes
OPTIONS0="noatime,space_cache=v2,compress=zstd,ssd,discard=async,subvol=/@"
OPTIONS1="nodev,noatime,space_cache=v2,compress=zstd,ssd,discard=async,subvol=/@"
OPTIONS2="nodev,nosuid,noatime,space_cache=v2,compress=zstd,ssd,discard=async,subvol=/@"
OPTIONS3="noexec,nodev,nosuid,noatime,space_cache=v2,compress=zstd,ssd,discard=async,subvol=/@"
mount_subs0() {
    mount -m -o "${3}${2}" -t btrfs "${4}" /mnt"${1}"
    mount -m -o "${OPTIONS3}${2}_snapshots" -t btrfs "${4}" /mnt"${1}".snapshots
    mount_subs1 "${1}" "${3}" "${4}"
}
mount_subs1() {
    for ((a = 0; a < SUBVOLUMES_LENGTH; a++)); do
        if [[ "${SUBVOLUMES[${a}]}" != "${1}" ]] && grep -q "^${1}" <<<"${SUBVOLUMES[${a}]}"; then
            if { grep -q "^${1}log/" <<<"${SUBVOLUMES[${a}]}"; } || { grep -q "^${1}lib/" <<<"${SUBVOLUMES[${a}]}" && ! grep -q "^${1}lib/flatpak/" <<<"${SUBVOLUMES[${a}]}"; }; then
                mount -m -o "${OPTIONS3}${CONFIGS[${a}]}" -t btrfs "${3}" /mnt"${SUBVOLUMES[${a}]}"
            else
                mount -m -o "${2}${CONFIGS[${a}]}" -t btrfs "${3}" /mnt"${SUBVOLUMES[${a}]}"
            fi
            mount -m -o "${OPTIONS3}${CONFIGS[${a}]}_snapshots" -t btrfs "${3}" /mnt"${SUBVOLUMES[${a}]}".snapshots
        fi
    done
}
for ((i = 0; i < SUBVOLUMES_LENGTH; i++)); do
    case "${SUBVOLUMES[${i}]}" in
    /)
        mount -m -o "${OPTIONS0}" -t btrfs "${LV0}" /mnt"${SUBVOLUMES[${i}]}"
        mount -m -o "${OPTIONS3}snapshots" -t btrfs "${LV0}" /mnt"${SUBVOLUMES[${i}]}".snapshots
        ;;
    /usr/)
        mount_subs0 "${SUBVOLUMES[${i}]}" "${CONFIGS[${i}]}" "${OPTIONS1}" "${LV1}"
        ;;
    /nix/)
        mount_subs0 "${SUBVOLUMES[${i}]}" "${CONFIGS[${i}]}" "${OPTIONS1}" "${LV2}"
        ;;
    /var/)
        mount_subs0 "${SUBVOLUMES[${i}]}" "${CONFIGS[${i}]}" "${OPTIONS2}" "${LV3}"
        ;;
    /home/)
        mount_subs0 "${SUBVOLUMES[${i}]}" "${CONFIGS[${i}]}" "${OPTIONS2}" "${LV4}"
        ;;
    esac
done
## tmpfs
mount -m -o "noexec,nodev,nosuid,size=80%" -t tmpfs tmpfs /mnt/dev/shm
### FIXME: Ideally, /tmp should be noexec; See: https://github.com/NixOS/nix/issues/10492
mount -m -o "nodev,nosuid,mode=1700,size=80%" -t tmpfs tmpfs /mnt/tmp
mount -m -o "noexec,nodev,nosuid,gid=proc,hidepid=2" -t proc proc /mnt/proc
## /boot
OPTIONS4="noexec,nodev,nosuid,noatime,fmask=0077,dmask=0077"
mount -m -o "${OPTIONS4}" -t vfat "${BOOT1P1}" /mnt/boot

# Execute setup-disk
setup-disk -L -m sys /mnt

# Append /mnt/boot/usercfg.txt
{
    echo "# alpine-install"
    echo "## nvme"
    echo "dtparam=pciex1"
    echo "dtparam=pciex1_gen=3"
} >/mnt/boot/usercfg.txt

# Append /mnt/boot/cmdline.txt
sed -i "1s|$| rootflags=${OPTIONS0}|" /mnt/boot/cmdline.txt

# Remove duplicate mount for /tmp in /mnt/etc/fstab
## START sed
FILE=/mnt/etc/fstab
STRING=$'^tmpfs\t/tmp\ttmpfs\tnosuid,nodev\t0\t0$'
grep -q "${STRING}" "${FILE}" || sed_exit
sed -i "\|${STRING}|d" "${FILE}"
STRING="subvolid=[^[:space:],]*,\?"
grep -q "${STRING}" "${FILE}" || sed_exit
sed -i "s/${STRING}//g" "${FILE}"
STRING=",[[:space:]]0[[:space:]]0$"
grep -q "${STRING}" "${FILE}" || sed_exit
sed -i "s/${STRING}/\t0 0/g" "${FILE}"
## END sed

# Notify user if script has finished successfully
echo "'$(basename "${0}")' has finished successfully."
