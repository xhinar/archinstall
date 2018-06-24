INS_DISK="${INS_DISK:-/dev/sda}"
INS_EFI_SIZE='+550M'
INS_SWAP_KEY=/etc/SWAP.key
INS_SWAP_SIZE="$(free -m | awk '/^Mem:/ { printf "+%1.fM", $2+1024 }')"

INS_EFI_PART="${INS_DISK}1"
INS_SWAP_PART="${INS_DISK}2"
INS_ROOT_PART="${INS_DISK}3"

INS_ROOT_CONTAINER="ROOT"
INS_SWAP_CONTAINER="SWAP"
INS_PASSWORD="4557UK1035ZN"

### begin - 00. wipe disk with random data ###
cryptsetup open --type plain "$INS_DISK" container --key-file /dev/random
dd if=/dev/zero of=/dev/mapper/container bs=250M status=progress || true
cryptsetup close container
### 00. wipe disk with random data - end ###


### begin - 01. create_partitions ###
sgdisk \
  --clear \
  --new 1::"$INS_EFI_SIZE" \
      --change-name 1:EFI \
      --typecode 1:ef00 \
  --new 2::"$INS_SWAP_SIZE" \
      --change-name 2:LUKS_SWAP \
      --typecode 2:8300 \
  --new 3:: \
      --change-name 3:LUKS_SLASH \
      --typecode 3:8300 \
  "$INS_DISK"
### 01. create_partitions - end ###
  
### begin - 02. format fat32 ###
### mkfs.fat -F32 "$INS_EFI_PART"
### moved to 04d. mount the EFI partition
### 02. format fat32 - end ###

### begin - 03. cryptsetup slash ###
echo "$INS_PASSWORD" | cryptsetup luksFormat --batch-mode "$INS_ROOT_PART" --key-file -
echo "$INS_PASSWORD" | cryptsetup open "$INS_ROOT_PART" "$INS_ROOT_CONTAINER" --key-file -
### 03. cryptsetup_slash - end ###


### begin - 04. format btrfs ###
mkfs.btrfs --label SLASH "/dev/mapper/$INS_ROOT_CONTAINER"
### 04. format btrfs - end ###

### begin - 04a. mount partition ###
mkdir -p /mnt/btrfs-root
mount -o defaults,relatime,space_cache /dev/mapper/$INS_ROOT_CONTAINER /mnt/btrfs-root
mkdir -p /mnt/btrfs-root/__active
mkdir -p /mnt/btrfs-root/__snapshot
### 04a. mount partition - end ###

### begin - 04b. create btrfs subvolumes ###
cd /mnt/btrfs-root
btrfs subvolume create __active/rootvol
btrfs subvolume create __active/home
btrfs subvolume create __active/var
btrfs subvolume create __active/opt
### 04b. create btrfs subvolumes - end ###

### begin - 04c. create mountpoints and mount the btrfs subvolumes on the correct hierarchy ###
mkdir -p /mnt/btrfs-active
mount -o defaults,nodev,relatime,space_cache,subvol=__active/rootvol /dev/mapper/$INS_ROOT_CONTAINER /mnt/btrfs-active
# create the mountpoints and mount separately /home, /opt, /var and /var/lib
mkdir -p /mnt/btrfs-active/{home,opt,var,var/lib,boot}
mount -o defaults,nosuid,nodev,relatime,subvol=__active/home /dev/mapper/$INS_ROOT_CONTAINER /mnt/btrfs-active/home
mount -o defaults,nosuid,nodev,relatime,subvol=__active/opt /dev/mapper/$INS_ROOT_CONTAINER /mnt/btrfs-active/opt
mount -o defaults,nosuid,nodev,noexec,relatime,subvol=__active/var /dev/mapper/$INS_ROOT_CONTAINER /mnt/btrfs-active/var
# /var/lib is special, since it's very useful for snapshots of it to be part of the active root volume. 
# To manage that, we bind-mount the directory from the "rootvol" subvolume back inside the var subvolume
mkdir -p /mnt/btrfs-active/var/lib
mount --bind /mnt/btrfs-root/__active/rootvol/var/lib /mnt/btrfs-active/var/lib
# you need to make sure that this directory exists, there's a step below for that
### 04c. create mountpoints and mount the btrfs subvolumes on the correct hierarchy - end ###

### begin - 04d. mount the EFI partition ###
# we're using /boot here, not /boot/efi as some suggest, since our / is encrypted.
# apparently, grub2 can manage this, but I haven't been able to replicate it.
mount -o defaults,nosuid,nodev,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro "$INS_EFI_PART" /mnt/btrfs-active/boot
### 04d. mount the EFI partition -end ###

### begin - 05. mount chroot ###
mount "/dev/mapper/$INS_ROOT_CONTAINER" /mnt
mkdir /mnt/boot
mount "$INS_EFI_PART" /mnt/boot
### 05. mount chroot - end ###

### begin - 06. create key ###
SWAP_KEY="/mnt$INS_SWAP_KEY"
mkdir -p "$(dirname $SWAP_KEY)"
dd bs=512 count=1 if=/dev/random of="$SWAP_KEY" status=none
### 06. create key - end ###

### begin - 07. cryptsetup swap ###
cryptsetup luksFormat --batch-mode "$INS_SWAP_PART" "$SWAP_KEY"
cryptsetup open --key-file="$SWAP_KEY" "$INS_SWAP_PART" "$INS_SWAP_CONTAINER"
### 07. cryptsetup swap - end ###

### begin - 08. set as swap ###
mkswap --label SWAP "/dev/mapper/$INS_SWAP_CONTAINER"
swapon "/dev/mapper/$INS_SWAP_CONTAINER"
### 08. set as swap - end ###


### begin 09. pacstrap script to install the base package group ###
pacstrap /mnt/btrfs-active base base-devel btrfs-progs 
### 09. pacstrap script to install the base package group - end ###

### begin - 10. generating the fstab ###
genfstab -U -p /mnt/btrfs-active >> /mnt/btrfs-active/etc/fstab
vi /mnt/btrfs-active/etc/fstab
# it should look kinda like this:
"""
# /dev/sda1 LABEL=EFI
UUID=1234-ABCD        /boot   vfat rw,nosuid,nodev,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro,discard 0 2
# /dev/sda2 LABEL=Arch\x20Linux
UUID=44444444-4444-4444-4444-4444444444444	/               btrfs   rw,nodev,relatime,ssd,discard,space_cache,subvol=__active/rootvol 0 0
UUID=44444444-4444-4444-4444-4444444444444	/home           btrfs   rw,nodev,nosuid,relatime,ssd,discard,space_cache,subvol=__active/home 0 0
UUID=44444444-4444-4444-4444-4444444444444	/opt            btrfs   rw,nodev,nosuid,relatime,ssd,discard,space_cache,subvol=__active/opt 0 0
UUID=44444444-4444-4444-4444-4444444444444	/var            btrfs   rw,nodev,nosuid,noexec,relatime,ssd,discard,space_cache,subvol=__active/var 0 0
UUID=44444444-4444-4444-4444-4444444444444	/run/btrfs-root btrfs   rw,nodev,nosuid,noexec,relatime,ssd,discard,space_cache 0 0
/run/btrfs-root/__active/rootvol/var/lib   	/var/lib        none    bind 0 0
tmpfs                                   	/tmp            tmpfs   rw,nodev,nosuid 0 0
tmpfs                                   	/dev/shm        tmpfs   rw,nodev,nosuid,noexec 0 0
"""
### 10. generating the fstab - end ###

### begin - 11. chroot into the newly installed system ###
arch-chroot /mnt/btrfs-active bash
### 11. chroot into the newly installed system - end ###

### begin - 12. set up your minimum environment as you wish (as per the Beginner's Guide) ###
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
hwclock --systohc --utc
vi /etc/locale.gen
# search en_US.UTF-8 and deleted the hashtag in front of it
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
export LANG=en_US.UTF-8
echo P4ndArX > /etc/hostname
vi /etc/hosts
"""
127.0.0.1 localhost
::1     localhost
127.0.0.1 P4ndArX.localdomain P4ndArX
"""
passwd
### 12. set up your minimum environment as you wish (as per the Beginner's Guide) - end ###

### begin - 13 - create the /run directory where btrfs-root will eventually be mounted
# this is the step that (04c) above was refering.
mkdir -p /run/btrfs-root
### 13 - create the /run directory where btrfs-root will eventually be mounted - end ###

# 14 - fix the mkinitcpio.conf to contain what we actually need.
vi /etc/mkinitcpio.conf
# on the MODULES section, add "vfat aes_x86_64 crc32c-intel" (and whatever else you know your hardware needs. Mine needs i915 too)
# on the BINARIES section, add "/usr/bin/btrfsck", since it's useful to have in case your filesystem has troubles
# on the HOOKS section: 
#  - add "resume" after "udev" (IF and ONLY IF you want to enable resume support)
#  - add "encrypt" before "filesystems"
#  - remove "fsck" and 
#  - add "btrfs" at the end
#HOOKS="base udev autodetect modconf block filesystems keyboard fsck btrfs"

# 15 - re-generate your initrd images:
mkinitcpio -p linux

# 16 - mount the EFIvarfs directory
# edit: not needed anymore?
# mount the efivarfs filesystem
# mount -t efivarfs efivarfs /sys/firmware/efi/efivars

# 17 - install gummiboot as a bootloader
pacman -S gummiboot
gummiboot --path=/boot install

# 18 - set the bootloader global options
vi /boot/loader/loader.conf
# it should contain:
"""
timeout 4
default arch
editor 0
"""

# 19 - set the bootloader entries
# "arch.conf" is related to "arch" above.. if you your default in /boot/loader/loader.conf is called "bob", this should be "entries/bob.conf"
vi /boot/loader/entries/arch.conf
# now, for this one, a little bit of explaining is needed
# first, get your hands of the output of blkid, specifically the UUIDs of each block device. 
# (the easy way to do this is lsblk -f > /boot/loader/entries/arch.conf, and then edit the file and leave it out as comments)
# for this example, I'm going to mark them like this:
# /dev/sda1 LABEL="EFI"  				UUID=11111111-1111-1111-1111-111111111111
# /dev/sda2 LABEL="SWAP" 				UUID=22222222-2222-2222-2222-222222222222
# /dev/sda3 LABEL="encrypted root"		UUID=33333333-3333-3333-3333-333333333333
# /dev/mapper/root LABEL="Arch Linux" 	UUID=44444444-4444-4444-4444-444444444444
# now, keep these in mind:
#  - 444444... should be the UUID that is present on your fstab, identifying the volume you're mounting. this is your inner encrypted volume
#  - 33333... is the OUTER UUID of your encrypted volume, the actual primary partition on your disk
#  - your DECRYPTED (inner) volume will show as /dev/mapper/luks-3333... . This way, you know which inner volume is inside which outer volume
#  - 2222.... is the swap partition, where you'll be resuming from
"""
title Arch Linux
linux /vmlinuz-linux
initrd	/intel-ucode.img
initrd	/initramfs-linux.img
options cryptdevice=UUID=33333333-3333-3333-3333-333333333333:luks-33333333-3333-3333-3333-333333333333 root=UUID=44444444-4444-4444-4444-444444444444 rootflags=subvol=__active/rootvol  quiet resume=UUID=22222222-2222-2222-2222-222222222222 ro
"""

# 20 - Proceed with the configuration as from the beginner's guide, if you still need anything

# 21 - reboot into your new install
reboot

# 22 - after rebooting and entering your password, finish setting up arch the way you want it.

# 23 - ????

# 24 - Profit

    
