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

# Set desired keymap
loadkeys us

# Set large font
#setfont latarcyrheb-sun32

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
