#!/bin/bash

# References: http://www.beyondlinux.com/2011/06/29/how-to-automate-virtual-machine-creation-and-runing-on-virtualbox-by-command-line/

[ -f `pwd`/vboxenv ] && source `pwd`/vboxenv

IMAGE_NAME="${IMAGE_NAME:-lihlith}"
# ToDo:= Grab from config
DISK_FILE="${DISK_FILE:-/data/lihlith_vm/data.vdi}"
# 100GB, in MB
DISK_SIZE="${DISK_SIZE:-102400}"
IMAGE_RAM=${IMAGE_RAM:-0}
IMAGE_CPU=${IMAGE_CPU:-0}

echo "Config"
echo " - image name: $IMAGE_NAME"
echo " - disk dir: $DISK_FILE"
echo " - disk size: $DISK_SIZE"
echo " - ram: $IMAGE_RAM"
echo " - cpu: $IMAGE_CPU"
echo " - iso_name: $ISO_NAME"
echo " - iso_url: $ISO_URL"

confirm() {
  # call with a prompt string or use a default
  read -r -p "${1:-Are you sure? [y/N]} " response
  case "$response" in
    [yY][eE][sS]|[yY])
        true
        ;;
    *)
        false
        ;;
  esac
}

# image_name
create_vm() {
  local image_name="${1:-$IMAGE_NAME}"
  echo "Create virtual machine: $image_name"
  vboxmanage createvm --name $image_name --register --ostype 'Ubuntu_64' 1>/dev/null 2>/dev/null
  # vboxmanage showvminfo $image_name
}

# image_name
delete_vm() {
  local image_name="${1:-$IMAGE_NAME}"
  echo "Delete virtual machine: $image_name"
  vboxmanage unregistervm $image_name --delete 
}

# disk_file, disk_size
create_disk() {
  local disk_file=${1:-$DISK_FILE}
  local disk_size=${2:-$DISK_SIZE}
  echo "Create disk at $disk_dir with size $disk_size MB"
  vboxmanage createvdi --filename $disk_file --size $disk_size 1>/dev/null 2>/dev/null
}

# disk_file
delete_disk() {
  local disk_file=${1:-$DISK_FILE}
  echo "Delete disk $disk_file"
  rm $disk_file
}

# iso_name, iso_url
get_iso() {
  local iso_file=${1:-$ISO_FILE}
  local iso_url=${2:-$ISO_URL}
  echo "Get $iso_file"
  if [[ ! -f $iso_file ]]; then
    wget $iso_url -O $ISO_FILE
  fi
}

clean_networks() {
  local n_nets=$1
  for (( i = $n_nets; i >= 0; i-- )); do
    vboxmanage dhcpserver remove --ifname "vboxnet${i}" 1>/dev/null 2>/dev/null
    vboxmanage hostonlyif remove "vboxnet${i}" 1>/dev/null 2>/dev/null
  done
}

setup_network() {
  local netname=${1:-vboxnet0}
  local n_nets=$(vboxmanage list hostonlyifs | grep ^Name | wc -l)
  # don't exit on error
  set +e
  if [[ $n_nets -gt 0 ]]; then
    # 0 indexed
    confirm "More Virtual Networks detected, erase them?" && (clean_networks $(( $n_nets - 1 )))
  fi
  set -e
  vboxmanage hostonlyif create
  # 0 indexed
  local n_nets=$(( $(vboxmanage list hostonlyifs | grep ^Name | wc -l) -1 ))
  local network="vboxnet${n_nets}"
  # configure it to use a dhcp server and be visible on host
  vboxmanage dhcpserver add --ifname $network \
    --ip 192.168.60.100 --netmask 255.255.255.0 \
    --lowerip 192.168.60.101 --upperip 192.168.60.254 --enable
  vboxmanage hostonlyif ipconfig $network --ip 192.168.60.1
}

create_vm $IMAGE_NAME
if [[ $? -ne 0 ]]; then
  echo "Machine already exists"
  confirm "Delete machine? [y/N]" && (delete_vm; create_vm $IMAGE_NAME)
fi

create_disk $DISK_FILE $DISK_SIZE
if [[ $? -ne 0 ]]; then
  echo "Disk already exists"
  confirm "Delete disk? [y/N]" && (delete_disk; create_disk $DISK_FILE $DISK_SIZE)
fi

ISO_FILE=$(dirname $DISK_FILE)/$ISO_NAME
get_iso $ISO_FILE $ISO_URL

# exit on error
set -e

echo "Create virtual network"
setup_network

echo "Setup Virtual Machine"
echo " - memory, cpu and network"
n_nets=$(( $(vboxmanage list hostonlyifs | grep ^Name | wc -l) -1 ))
network="vboxnet${n_nets}"
vboxmanage modifyvm $IMAGE_NAME \
  --memory $IMAGE_RAM --cpus $IMAGE_CPU \
  --vram 128 --acpi on --boot1 dvd \
  --nic1 hostonly --hostonlyadapter1 $network \
  --nic2 nat

echo " - boot order"
vboxmanage storagectl $IMAGE_NAME --name "IDE Controller" --add ide
vboxmanage modifyvm $IMAGE_NAME --boot1 dvd --hda $DISK_FILE --sata on

echo " - storage: attach virtual disk to port 0, device 0:"
vboxmanage storageattach $IMAGE_NAME \
  --storagectl "IDE Controller" --port 0 --device 0 \
  --type hdd --medium $DISK_FILE

echo " - storage: attach the ISO to port 1, device 0:"
vboxmanage storageattach $IMAGE_NAME \
  --storagectl "IDE Controller" --port 1 --device 0 \
  --type dvddrive --medium $ISO_FILE

echo " - iso as dvd"
vboxmanage modifyvm $IMAGE_NAME --dvd $ISO_FILE

echo "done"
echo "Virtual Machine Summary"
vboxmanage showvminfo $IMAGE_NAME --details

# When starting the vm, if errors like 
# "The character device /dev/vboxdrv does not exist, please install the
# virtualbox-ose-dkms package and the appropriate headers, most likely 
# linux-headers" occured.
# Then you probably run the following command by root:
# $ modprobe vboxdrv
# $ modprobe vboxnetflt

