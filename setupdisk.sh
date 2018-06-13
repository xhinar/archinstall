INS_DISK="${INS_DISK:-/dev/sda}"
INS_EFI_SIZE='+550M'
INS_SWAP_KEY=/etc/SWAP.key
INS_SWAP_SIZE="$(free -m | awk '/^Mem:/ { printf "+%1.fM", $2+1024 }')"

INS_EFI_PART="${INS_DISK}1"
INS_SWAP_PART="${INS_DISK}2"
INS_SLASH_PART="${INS_DISK}3"

### begin - create_partitions ###
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
  "INS_DISK"
### create_partitions - end ###
  
### begin - format fat 32 ###
mkfs.fat -F32 "$INS_EFI_PART"
### format fat 32 - end ###
