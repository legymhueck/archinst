#!/bin/bash

# Check if we're root
if [[ "$UID" -ne 0 ]]; then
    echo "This script needs to be run as root!" >&2
    exit 3
fi

# Config options
read -p "Username: " username
lsblk
read -p "Drive: " drive
target="/dev/"$drive
rootmnt="/mnt"
locale="en_US.UTF-8"
locale2="de_DE.UTF-8"
keymap="de-latin1"
timezone="Europe/Berlin"
hostname="le"
# install whois to be able to use mkpasswd
# SHA512 hash of password.
# To generate, run 'mkpasswd -m sha-512'
# Prefix any $ symbols with \ .
# The entry below is the hash of 'password'
user_password="\$6\$/VBa6GuBiFiBmi6Q\$yNALrCViVtDDNjyGBsDG7IbnNR0Y/Tda5Uz8ToyxXXpw86XuCVAlhXlIvzy1M8O.DWFB6TRCia0hMuAJiXOZy/"

# To fully automate the setup, change badidea=no to yes, and enter a cleartext password for the disk encryption 

# Packages to pacstrap
pacstrappacs=(
    base
    base-devel
    btrfs-progs
    cryptsetup
    dosfstools
    e2fsprogs
    efivar
    firewalld
    git
    kitty
    linux
    linux-firmware
    intel-ucode
    lsd
    mc
    micro
    nano
    networkmanager
    nm-connection-editor
    vim
    p7zip
    pipewire
    pipewire-alsa
    pipewire-pulse
    pipewire-jack
    polkit-kde-agent
    python-pip
    python-setuptools
    sbctl
    starship
    sudo
    udisks2
    unzip
    util-linux
    whois
    wireplumber
    xdg-user-dirs
    zip
)

# Partition
echo "Creating partitions..."
sgdisk -Z "$target"
sgdisk \
    -n1:0:+512M -t 1:ef00 -c 1:EFI \
    -N2         -t 2:8304 -c 2:ROOT \
    "$target"

# Reload partition table
sleep 2
partprobe -s "$target"
sleep 2

# Create file systems
echo "Making File Systems..."
mkfs.vfat -F32 -n EFI /dev/disk/by-partlabel/EFI
mkfs.btrfs -f -L ROOT /dev/disk/by-partlabel/ROOT

# Mount the root, and create + mount the EFI directory
echo "Mounting File Systems..."
mount /dev/disk/by-partlabel/ROOT "$rootmnt"
mkdir "$rootmnt"/efi -p
mount -t vfat /dev/disk/by-partlabel/EFI "$rootmnt"/efi

# Update pacman mirrors and then pacstrap base install
echo "Pacstrapping..."
reflector --country DE --age 12 --latest 3 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
pacstrap -K $rootmnt "${pacstrappacs[@]}"
genfstab -U /mnt >> /mnt/etc/fstab

# Add our locale to locale.gen
echo "Generate locale"
sed -i -e "/^#"$locale"/s/^#//" "$rootmnt"/etc/locale.gen
sed -i -e "/^#"$locale2"/s/^#//" "$rootmnt"/etc/locale.gen

# Remove any existing config files that may have been pacstrapped, systemd-firstboot will then regenerate them
rm "$rootmnt"/etc/{machine-id,localtime,hostname,shadow,locale.conf} ||
systemd-firstboot --root "$rootmnt" \
	--keymap="$keymap" --locale="$locale" \
	--locale-messages="$locale" --timezone="$timezone" \
	--hostname="$hostname" --setup-machine-id \
	--welcome=false
arch-chroot "$rootmnt" locale-gen

# Add the local user
echo "Adding user..."
arch-chroot "$rootmnt" useradd -G wheel -m -p "$user_password" "$username"

# Uncomment the wheel group in the sudoers file
echo "Uncommenting wheel group in sudoers..."
sed -i -e '/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^# //' "$rootmnt"/etc/sudoers

# Create a basic kernel cmdline, we're using DPS so we don't need to have anything here really, but if the file doesn't exist, mkinitcpio will complain
echo "quiet rw" > "$rootmnt"/etc/kernel/cmdline

# Change the HOOKS in mkinitcpio.conf to use systemd hooks
sed -i \
    -e 's/base udev/base systemd/g' \
    -e 's/keymap consolefont/sd-vconsole sd-encrypt/g' \
    "$rootmnt"/etc/mkinitcpio.conf

# Change the preset file to generate a Unified Kernel Image instead of an initram disk + kernel
sed -i \
    -e '/^#ALL_config/s/^#//' \
    -e '/^#default_uki/s/^#//' \
    -e '/^#default_options/s/^#//' \
    -e 's/default_image=/#default_image=/g' \
    -e "s/PRESETS=('default' 'fallback')/PRESETS=('default')/g" \
    "$rootmnt"/etc/mkinitcpio.d/linux.preset

# Read the UKI setting and create the folder structure otherwise mkinitcpio will crash
declare $(grep default_uki "$rootmnt"/etc/mkinitcpio.d/linux.preset)
arch-chroot "$rootmnt" mkdir -p "$(dirname "${default_uki//\"}")"

# Enable the services we will need on start up
echo "Enabling services..."
systemctl --root "$rootmnt" enable systemd-resolved systemd-timesyncd NetworkManager

# Mask systemd-networkd as we will use NetworkManager instead
systemctl --root "$rootmnt" mask systemd-networkd

# Regenerate the ramdisk, this will create our UKI
echo "Generating UKI and installing Boot Loader..."
arch-chroot "$rootmnt" mkinitcpio -p linux
echo "Setting up Secure Boot..."
if [[ "$(efivar -d --name 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode)" -eq 1 ]]; then
arch-chroot "$rootmnt" sbctl create-keys
arch-chroot "$rootmnt" sbctl enroll-keys -m
arch-chroot "$rootmnt" sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi
arch-chroot "$rootmnt" sbctl sign -s "${default_uki//\"}"
else
echo "Not in Secure Boot setup mode. Skipping..."
fi

# Install the systemd-boot bootloader
echo "Installing Boot Loader..."
arch-chroot "$rootmnt" bootctl install --esp-path=/efi

# Lock the root account
echo "Locking root account..."
arch-chroot "$rootmnt" usermod -L root

echo "----------------------------------"
echo " Install complete. Please reboot. "
echo "----------------------------------"

sync
