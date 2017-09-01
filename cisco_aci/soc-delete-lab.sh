#!/bin/bash

DISKFILES="soc-control1.qcow2 soc-control1-cinder.qcow2 soc-control2.qcow2 soc-control2-cinder.qcow2 compute1.qcow2 compute2.qcow2"
VMIMAGES="compute1 compute2 soc-admin soc-control1 soc-control2"
LABNUM="$1"

if [[ -z "$1" ]] || [[ ! "$1" =~ ^[0][1-6]$ ]]; then
  echo "Usage: "$(basename "$0")" <LAB NUM>"
  echo "   where <LAB NUM> is 01 through 06"
  exit 1
fi

echo "Removing NAT forwarding for lab${LABNUM}"
sed -i /${LABNUM}soc-admin/d /etc/libvirt/hooks/qemu
#while test $(iptables -L | grep -c 01soc-admin) -gt 0; do 
#  /usr/sbin/iptables -D FORWARD -o virbr0 -d  $GUEST_IP -j ACCEPT
#  /usr/sbin/iptables -t nat -D PREROUTING -p tcp --dport $HOST_PORT -j DNAT --to $GUEST_IP:$GUEST_PORT
#done

echo "Removing /etc/hosts entry for ${LABNUM}soc-admin"
sed -i /${LABNUM}soc-admin/d /etc/hosts

echo "Destroying and undefining lab$LABNUM"
for list in $VMIMAGES; do
  virsh destroy "$LABNUM$list"
  virsh undefine "$LABNUM$list"
done
virsh net-destroy "$LABNUM"admin
virsh net-undefine "$LABNUM"admin

echo "Deleting disk images"
rm -f /var/lib/libvirt/images/"$LABNUM"soc-admin.qcow2
for list in $DISKFILES; do
  rm -f /var/lib/libvirt/images/"$LABNUM$list"
done

echo "Removing the screen session ${LABNUM}soclab"
kill -9 $(screen -ls | grep ${LABNUM}soclab | cut -d'.' -f1)
screen -q -wipe
