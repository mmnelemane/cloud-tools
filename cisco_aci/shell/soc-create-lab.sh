#!/bin/bash

# USE SOCLAB01 FOR CREATING AND PATCHING ANY TEMPLATES!!! 

DISKFILES="soc-control1.qcow2 soc-control1-cinder.qcow2 soc-control2.qcow2 soc-control2-cinder.qcow2 compute1.qcow2 compute2.qcow2"

usage() {
  echo "Usage: "$(basename "$0")" [OPTIONS] [FUNCTION]"
  echo
  echo "   -h or --help"
  echo "   -n<NUM> or --labnum=<NUM> must be 01 to 06 with a function"
  echo "   -v<VER> or --socversion=<VER> defines the SOC version for a function" 
  echo
  echo "Functions"
  echo "   -c or --create - will create a new lab from an prebuilt admin image" 
  echo "   -l or --list-backups - list all lab backups located in /var/lib/libvirt/images/<NUM>backups"
  echo "   -b<IMAGE NAME> or --backup-lab=<IMAGE NAME> - backup lab in /var/lib/libvirt/images/<NUM>backups"
  echo "   -r<IMAGE NAME> or --restore-lab=<IMAGE NAME> - restore lab from backup location"
  echo "   -d<IMAGE NAME> or --delete-lab=<IMAGE NAME> - delete lab from backup location"
  echo "   -f<NAME> or --function=<NAME> - with no function specified list available functions or run the function"
}

check_function() {
  # $1 is the function
  if test "${1}" != ""; then
    echo "Only one function can be specified at a time"
    exit 2
  fi
}

check_labnum() {
  # $1 is the lab number
  if test -z ${1}; then
    echo "-n or --labnum is required"
    exit 2
  fi
}

check_socver() {
  # $1 is the soc version
  if test -z ${1}; then
    echo "-v or --socversion is required"
    exit 2
  fi
}

list_functions() {
  echo "Available functions are:"
  echo "   define_lab_net - defines the virtual network for the specified labnum"
  echo "   define_lab_vms - defines the virtual machines for the specified labnum"
  echo "   copy_admin_image - copies a socadmin disk image and modifies it for the specified labnum"
  echo "   create_node_disks - create empty disk files for each OpenStack node"
  echo "   create_screens - create screens for each VM for the specified labnum"
}

define_lab_net() {
  # $1 is the lab number
  TEMPXML=$(mktemp -d)
  BASTIONIP=$(grep ^$1: /root/virsh-xmls/lab-ip-defs.conf | cut -d':' -f2)
  echo "Defining lab network for ${1}soclab"
  cp /root/virsh-xmls/net-admin.xml ${TEMPXML}
  for list in $(ls -1 ${TEMPXML}); do
  #  echo ${TEMPXML}/${list}
    sed -i s/XX/${1}/g ${TEMPXML}/${list}
    sed -i s/UUID/$(uuidgen)/ ${TEMPXML}/${list}
  done
  virsh net-define ${TEMPXML}/net-admin.xml
  virsh net-autostart ${1}admin
  virsh net-start ${1}admin
  echo "Adding NAT forwarding for lab${1}"
  sed -i /^#VMNAME:GUEST_IP/a\ ${1}soc-admin:192.168.100.${BASTIONIP}:80:400${BASTIONIP} /etc/libvirt/hooks/qemu
  echo "Adding /etc/hosts entry for ${1}soc-admin"
  echo "192.168.100.${BASTIONIP} ${1}soc-admin" >> /etc/hosts
  rm -rf $TEMPXML
}

define_lab_vms() {
  # $1 is the lab number
  TEMPXML=$(mktemp -d)
  echo "Defining lab VMs for $1soclab"
  cp /root/virsh-xmls/*.xml "$TEMPXML"
  rm -rf "$TEMPXML"/net-*.xml
  for computevms in 1 2; do
    for niccnt in 1 2; do
      OLDIFS="$IFS"
      IFS=$'\n'
      for list in $(grep ^"$1":"$computevms":"$niccnt" /root/virsh-xmls/lab-hostdev-nics.conf); do
      #  echo $list
        sed -i '/^HOSTDEV/a\
    <hostdev mode="subsystem" type="pci" managed="yes">\
      <source>\
        <address domain="0x0000" SRCBUSADDR/>\
      </source>\
      <address type="pci" domain="0x0000" VMBUSADDR/>\
    </hostdev>' "$TEMPXML/compute$computevms".xml
      done
      SRCBUSADDR=$(echo $list | cut -d':' -f4)
      sed -i s/SRCBUSADDR/$SRCBUSADDR/ "$TEMPXML/compute$computevms".xml
      VMBUSADDR=$(echo $list | cut -d':' -f5)
      sed -i s/VMBUSADDR/$VMBUSADDR/ "$TEMPXML/compute$computevms".xml
      IFS=$OLDIFS
    done
    sed -i '/^HOSTDEV/d' "$TEMPXML/compute$computevms".xml
  done
  for list in $(ls -1 $TEMPXML); do
  #  echo "$TEMPXML/$list"
    sed -i s/XX/"$1"/g "$TEMPXML/$list"
    sed -i s/UUID/$(uuidgen)/ "$TEMPXML/$list"
    virsh define "$TEMPXML/$list"
  done
  rm -rf "$TEMPXML"
}

copy_admin_image() {
  # $1 is the lab number
  # $2 is the soc version
  echo "Copying soc-admin template disk image"
  cp /var/lib/libvirt/images/soc${2}-admin.qcow2.before-install-suse-cloud.patched /var/lib/libvirt/images/${1}soc-admin.qcow2
  
  echo "Modifying ${1}soc-admin disk image"
  while test -e /tmp/guestmount${1}.used; do
    echo "Waiting for a process started by "$(cat /tmp/guestmount${1}.used)" to complete..."
    sleep 1
  done
  echo $$ > /tmp/guestmount${1}.used
  TEMPMNT=$(mktemp -d)
  guestmount -a /var/lib/libvirt/images/${1}soc-admin.qcow2 -m /dev/sda2 --rw ${TEMPMNT}
  BASTIONIP=$(grep ^${1}: /root/virsh-xmls/lab-ip-defs.conf | cut -d':' -f2)
  sed -i s/192.168.100.30/192.168.100.${BASTIONIP}/ ${TEMPMNT}/etc/sysconfig/network/ifcfg-eth1
  sed -i s/192.168.100.30/192.168.100.${BASTIONIP}/ ${TEMPMNT}/etc/hosts
  sed -i s/192.168.100.30/192.168.100.${BASTIONIP}/ ${TEMPMNT}/etc/crowbar/network.json
  guestunmount ${TEMPMNT}
  rm -f /tmp/guestmount${1}.used
  rm -rf ${TEMPMNT}
}

create_node_disks() {
  # $1 is the lab number
  echo "Creating empty disks for each Openstack node"
  for list in $DISKFILES; do
    qemu-img create -f qcow2 /var/lib/libvirt/images/${1}${list} 40G
  done
}

list_backups() {
  # $1 is the lab number
  # $2 is the soc version
  # backup.list format
    # soc version
    # backup name
    # backup comment
  if [ ! -f /var/lib/libvirt/images/${1}backups/backup.list ]; then
    touch /var/lib/libvirt/images/${1}backups/backup.list
  fi
  echo -e "Backup name\t\tComment\n"
  OLDIFS=${IFS}
  IFS=$'\n'
  for list in $(grep ^${2}: /var/lib/libvirt/images/${1}backups/backup.list); do
    BUNAME=$(echo ${list} | cut -d':' -f2)
    BUCMNT=$(echo ${list} | cut -d':' -f3-)
    if [ ${#BUNAME} -lt 8 ]; then
      echo -e "${BUNAME}\t\t\t${BUCMNT}\n"
    else
      echo -e "${BUNAME}\t\t${BUCMNT}\n"
    fi
  done
  IFS=${OLDIFS}
}

backup_lab() {
  # $1 is the lab number
  # $2 is the soc version
  # $3 in the backup name
  # backup.list format
    # soc version
    # backup name
    # backup comment
  if [ ! -f /var/lib/libvirt/images/${1}backups/backup.list ]; then
    touch /var/lib/libvirt/images/${1}backups/backup.list
  fi
  if [ $(grep -c ^${2}:${3} /var/lib/libvirt/images/${1}backups/backup.list) -gt 0 ]; then
    echo "Backup not created because duplicate backup name specified."
    exit 3
  fi
  echo -n "Enter a comment for this backup: "
  read CMNT
  echo
  for list in $(ls /var/lib/libvirt/images/${1}*.qcow2); do
    dest=$(basename ${list})
    echo "Copying ${dest}..."
    #touch /var/lib/libvirt/images/${1}backups/${dest}.${3}
    cp --sparse=always ${list} /var/lib/libvirt/images/${1}backups/${dest}.${3}
  done
  echo "${2}:${3}:${CMNT}" >> /var/lib/libvirt/images/${1}backups/backup.list
}

restore_lab() {
  # $1 is the lab number
  # $2 is the soc version
  # $3 in the backup name
  if [ ! -f /var/lib/libvirt/images/${1}backups/backup.list ]; then
    touch /var/lib/libvirt/images/${1}backups/backup.list
  fi
  if [ $(grep -c ^${2}:${3} /var/lib/libvirt/images/${1}backups/backup.list) -eq 0 ]; then
    echo "Unable to restore backup because lab name is not found."
    exit 3
  fi
  echo -n "Are you sure you want to restore the ${3} backup? (Must type YES) "
  read ANS
  if [ "$ANS" = "YES" ]; then
    for list in $(ls /var/lib/libvirt/images/${1}backups/*.qcow2.${3}); do
      src=$(basename ${list})
      dest=$(echo ${src} | cut -d'.' -f1,2)
      echo "Copying ${src}..."
      cp --sparse=always /var/lib/libvirt/images/${1}backups/${src} /var/lib/libvirt/images/${dest}
    done
  else
    echo -e "\nNot restoring the backup because YES was not entered."
    exit 1
  fi
}

delete_lab() {
  # $1 is the lab number
  # $2 is the soc version
  # $3 in the backup name
  if [ ! -f /var/lib/libvirt/images/${1}backups/backup.list ]; then
    touch /var/lib/libvirt/images/${1}backups/backup.list
  fi
  if [ $(grep -c ^${2}:${3} /var/lib/libvirt/images/${1}backups/backup.list) -eq 0 ]; then
    echo "Unable to delete backup because lab name is not found."
    exit 3
  fi
  echo -n "Are you sure you want to delete the ${3} backup? (Must type YES) "
  read ANS
  if [ "$ANS" = "YES" ]; then
    rm /var/lib/libvirt/images/${1}backups/*.${3}
    sed -i /^${2}:${3}:/d /var/lib/libvirt/images/${1}backups/backup.list
    echo -e "\nBackup ${3} removed."
  else
    echo -e "\nNot deleting the backup because YES was not entered."
    exit 1
  fi
}

create_screens() {
  # $1 is the lab number
  echo "Creating a screen session with windows for each VM"
  screen -h 1000 -dmS ${1}soclab -t ${1}lab-host
  screen -S ${1}soclab -X screen -t ${1}soc-admin
  screen -S ${1}soclab -X screen -t soc-control1
  screen -S ${1}soclab -X screen -t soc-control2
  screen -S ${1}soclab -X screen -t compute1
  screen -S ${1}soclab -X screen -t compute2
}

if test -z "$1"; then
  echo "soc-create-lab.sh --help for details!"
  exit 1
fi

# Used getopt example from http://www.bahmanm.com/blogs/command-line-options-how-to-parse-in-bash-using-getopt

# set an initial value for any flags
LABNUM=""
SOCVER=""
FUNCTION=""
ARG1=""

# read the options
TEMP=`getopt -o hn:v:clr:b:d:f:: --long help,labnum:,socversion:,create,list-images,restore-image:,backup-image:,delete-image:,function:: -n 'soc-create-lab.sh' -- "$@"`
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -h|--help)
            usage
            exit 1 ;;
        -n|--labnum)
            if [[ ! "$2" =~ ^[0][1-6]$ ]]; then
                echo "$1 must be 01 to 06"
                exit 1
            fi
            LABNUM="$2"; shift 2 ;;
        -v|--socversion) 
            case "$2" in
                6)
                  SOCVER=6 ;;
                7)
                  SOCVER=7 ;;
                *)
                  echo "$1 must be either 6 or 7!"
                  exit 3 ;;
            esac ; shift 2 ;;
        -c|--create) 
            check_function $FUNCTION
            FUNCTION=c ; shift ;;
        -l|--list-images) 
            check_function $FUNCTION
            FUNCTION=l ; shift ;;
        -b|--backup-image) 
            check_function $FUNCTION
            FUNCTION=b 
            ARG1=$2
            shift 2 ;;
        -r|--restore-image) 
            check_function $FUNCTION
            FUNCTION=r
            ARG1=$2
            shift 2 ;;
        -d|--delete-image) 
            check_function $FUNCTION
            FUNCTION=d 
            ARG1=$2
            shift 2 ;;
        -f|--function)
            check_function $FUNCTION
            FUNCTION=f
            ARG1=$2
            shift 2 ;;
        --) shift ; break ;;
        *) echo "soc-create-lab.sh --help for details!" ; exit 1 ;;
    esac
done

# just for testing to make sure the proper variables are set
#echo "LABNUM = $LABNUM"
#echo "SOCVER = $SOCVER"
#echo "FUNCTION = $FUNCTION"
#echo "ARG1 = $ARG1"
#echo

case "$FUNCTION" in
    c)
        check_labnum $LABNUM
        check_socver $SOCVER
        define_lab_net $LABNUM
        define_lab_vms $LABNUM
        copy_admin_image $LABNUM $SOCVER
        create_node_disks $LABNUM
        create_screens $LABNUM
        ;;
    l)
        check_labnum $LABNUM
        check_socver $SOCVER
        list_backups $LABNUM $SOCVER
        ;;
    b)
        check_labnum $LABNUM
        check_socver $SOCVER
        backup_lab $LABNUM $SOCVER $ARG1 
        ;;
    r)
        check_labnum $LABNUM
        check_socver $SOCVER
        restore_lab $LABNUM $SOCVER $ARG1
        ;;
    d)
        check_labnum $LABNUM
        check_socver $SOCVER
        delete_lab $LABNUM $SOCVER $ARG1
        ;;
    f)
        if [ -z $ARG1 ]; then
          list_functions
        else
          check_labnum $LABNUM
          check_socver $SOCVER
          eval $ARG1 $LABNUM $SOCVER
        fi
        ;;
    *) echo "No function specified.  Exiting..." ; exit 1 ;;
esac

exit 0
