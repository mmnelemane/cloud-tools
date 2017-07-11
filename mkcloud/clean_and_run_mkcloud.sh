# A basic script to help automation of cleanup of the system loop devices along
# with the volumes and recreating the environment and then starting a cloud
# setup on the local machine. Plan to improve this script to more mature levels
# to handle more complex system issues automatically during deployment.

if [ -z "$1" ]
then
    echo "Usage: ./clean_and_run_mkcloud.sh <cloud_type>"
    echo "Values for <cloud_type>:"
    echo " basic    --> for regular 2 node cloud"
    echo " ceph     --> for regular cloud with ceph backend"
    echo " ha_basic --> for basic ha cloud with 4 nodes"
    echo " ha_ceph  --> for ha cloud with Ceph backend storage"
    exit 1;
fi

#Clearing and removing all the mapper devices
dms="$(sudo dmsetup ls)"
arr="$(echo $dms | tr "\n" " ")"

# Ensure cloud-admin node is not running before trying to clear the mapper
# devices for the node.
sudo virsh destroy cloud-admin
sudo virsh undefine cloud-admin

#clear all the mapper devices and remove them to free the loop device
for x in $arr
do
   dev_name="$(echo $x head -n1 | awk '{print $1;}')"
   if [ "$dev_name" == "No" ]
   then
       echo "No more mapper devices to clear"
       break
   fi
   dev="/dev/mapper/$dev_name"
   echo "Deleting device > $dev"
   cmd="sudo dmsetup clear $dev"
   echo "Executing command: $cmd"
   read -s -n 1 key
   resp="$($cmd)"
   cmd="sudo dmsetup remove $dev"
   echo "Executing command: $cmd"
   read -s -n 1 key
   resp="$($cmd)"
done

arr="$(sudo lvs --noheadings --options lv_name | tr -d "\n")"
for lv in $arr
do
    cmd="sudo lvremove -f /dev/cloud/$lv"
    echo "Executing command: $cmd"
    read -s -n 1 key
    resp="$($cmd)"
done
sudo vgremove -f cloud
sudo partprobe

# Clearing the loop device
lodev="$(sudo losetup --list --noheadings | awk '{print $1;}')"
loarr="$(echo $lodev)" 
for x in $loarr
do
    lo_name="$(echo $x head -n1 | awk '{print $1;}')"
    cmd="sudo losetup --detach-all $lo_name"
    echo "Executing command: $cmd"
    resp="$($cmd)"
done

#Create a new loop device
sudo losetup -f mkcloud.disk

#Execution of mkcloud script as per the command line option
option=$1

run_par="sudo env cloudpv=/dev/loop0 cloudsource=develcloud6 TESTHEAD=1"
echo "The option selected by you is $option"
read -s -n 1 key
if [ "$option" == "ceph" ]
then
    run_par+=" nodenumber=3 want_ceph=1"
elif [ "$option" == "ha_ceph" ]
then
    run_par+=" nodenumber=6 want_ceph=1 hacloud=1
    clusterconfig='data+network+services=2'"
elif [ "$option" == "ha_basic" ]
then
    run_par+=" nodenumber=4 hacloud=1 clusterconfig='data+network+services=2'"
elif [ "$option" == "basic" ]
then
    run_par+=""
fi

run_exec="$run_par ./mkcloud cleanup prepare setupadmin addupdaterepo
runupdate prepareinstcrowbar instcrowbar rebootcrowbar setupnodes instnodes
proposal"

mkcloud_cmd="$run_exec"
echo "Executing mkcloud command as follows: Confirm: $mkcloud_cmd"
read -s -n 1 key
resp="$($mkcloud_cmd)"

echo "MKCLOUD deployment ended with result: $resp"

