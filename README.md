# (Almost) unattended installation script for Arch Linux.

- This script is intended to be used to install Arch Linux on a new machine with minimal user interaction.
- It uses UKIs, i.e. Unified Kernel Images, to boot the system.
- If the TPM is in setup mode, the script will sign the UKI with the TPM.

## User interaction is required for

- username
- scecifying the disk the system will be installed on
- Setting the LUKS encryption password

## Presets

- Hostname. It is set to "archlinux"
- Start password is set to "password"
  - Can be changed on first login with the command 'passwd'.
- For security reasons, the root account is disabled.
- Timezone is set to "Europe/Berlin"
- Locale is set to "en_US.UTF-8" and "de_DE.UTF-8".
- Keyboard layout is set to "de-latin1-nodeadkeys"
- Disk is partitioned with a 512MB EFI partition and the rest is used for the root partition.
- The root partition is formatted with btrfs.
  - Compression can later be enabled in `/etc/fstab`, e. g. by adding `compress=zstd:1` (for best read performance) or `compress=zstd:3` (for more focus on compression ratio) to the options.
