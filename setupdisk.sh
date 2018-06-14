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
mkfs.fat -F32 "$INS_EFI_PART"
### 02. format fat32 - end ###

### begin - 03. cryptsetup slash ###
echo "$INS_PASSWORD" | cryptsetup luksFormat --batch-mode "$INS_ROOT_PART" --key-file -
echo "$INS_PASSWORD" | cryptsetup open "$INS_ROOT_PART" "$INS_ROOT_CONTAINER" --key-file -
### 03. cryptsetup_slash - end ###


### begin - 04. format btrfs ###
mkfs.btrfs --label SLASH "/dev/mapper/$INS_ROOT_CONTAINER"
### 04. format btrfs - end ###

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


### begin pacstrap script to install the base package group ###
pacstrap /mnt base base-devel
### pacstrap script to install the base package group - end ###

### begin - generating the fstab ###
genfstab -U /mnt >> /mnt/etc/fstab
### generating the fstab - end ###

### begin - chroot-ing into /mnt ###
arch-chroot /mnt /bin/bash
### chroot-ing into /mnt - end ###

### begin ###
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
hwclock --systohc --utc
echo LANG=en_US.UTF-8 > /etc/locale.conf
export LANG=en_US.UTF-8
echo P4ndArX > /etc/hostname
passwd
### end ###

    
