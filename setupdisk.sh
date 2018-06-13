INS_DISK="${INS_DISK:-/dev/sda}"
INS_EFI_SIZE='+550M'
INS_SWAP_KEY=/etc/SWAP.key
INS_SWAP_SIZE="$(free -m | awk '/^Mem:/ { printf "+%1.fM", $2+1024 }')"

INS_EFI_PART="${INS_DISK}1"
INS_SWAP_PART="${INS_DISK}2"
INS_SLASH_PART="${INS_DISK}3"

INS_PASSWORD="4557UK1035ZN"

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

INS_SLASH_CONTAINER="$(cryptsetup_slash "$INS_PASSWORD" "$INS_SLASH_PART")"

### begin - 03. format btrfs ###
mkfs.btrfs --label SLASH "/dev/mapper/$INS_SLASH_CONTAINER"
### 03. format btrfs - end ###

### begin - 04. mount chroot ###
mount "/dev/mapper/$INS_SLASH_CONTAINER" /mnt
mkdir /mnt/boot
mount "$INS_EFI_PART" /mnt/boot
### 04. mount chroot - end ###

### begin - 05. create key ###
SWAP_KEY="/mnt$INS_SWAP_KEY"
mkdir -p "$(dirname $SWAP_KEY)"
dd bs=512 count=1 if=/dev/random of="$SWAP_KEY" status=none
### 05. create key - end ###

INS_SWAP_CONTAINER="$(cryptsetup_swap "$INS_SWAP_PART" "/mnt$INS_SWAP_KEY")"

### begin - 06. set as swap ###
mkswap --label SWAP "/dev/mapper/$INS_SWAP_CONTAINER"
swapon "/dev/mapper/$INS_SWAP_CONTAINER"
### 06. set as swap - end ###



    
