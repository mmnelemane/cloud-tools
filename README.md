###########################################################
# File: Readme.txt
# Author: Madhu Mohan Nelemane (mmnelemane@suse.com)
############################################################

This file consists of notes and important information regarding setting up and
troubleshooting the Cisco ACI lab environment. This file shall be updated as
and when the scripts are updated.

********************************************************
     Lab restore for HA (Controller and Compute)
********************************************************

The ha lab backup does not work with soc-create-lab.sh.

* The template xml files for VMs in /root/virsh-xmls which is used by
  soc-create-lab.sh do not have the appropriate nic definitions for an HA
  deployment.  The *.xml files in 01sbsa-ha/ do:

* soc-create-lab.sh only restores from 01backups while the ha backups are in
  01sbsa-ha/. 
* Most importantly, running the HA configuration on the server that in the
  Cisco lab slows it down especially when multiple labs are running at the same
  time.

For these reasons, we should use a few manual steps to restore the HA lab as
detailed below.

```
  cd /var/lib/libvirt/images/
  virsh destroy 01iscsi
  virsh undefine 01iscsi
  rm 01iscsi*
  soc-delete-lab.sh 01
  soc-create-lab.sh -n01 -v6 -fdefine_lab_net
  soc-create-lab.sh -n01 -v6 -fcreate_screens
  for list in $(ls -1 01sbsa-ha/*.xml); 
  do echo ${list};
    destname=$(basename ${list} | cut -d'.' -f1);
    virsh define ${list};
  done
  for list in $(ls -1 01sbsa-ha/*.qcow2.working_ha_gbp);
  do echo ${list};
    destname=$(basename ${list} | cut -d'.' -f1,2);
    rsync --sparse --progress ${list} ${destname};
  done
```

* Start 01iscsi and 01soc-admin
* Wait until soc-admin is up and start 01soc-control1

The following steps below are needed to get the lab fully working. The reason
is when the iscsi server is restored and restarted, the WWIDs change for some
reason. This means that you will need to go into the control and compute
nodes to update the WWIDs so they can access shared storage for sbd, postgres
and rabbitmq.  

# FIXME: Need to investigate why the WWIDs change and if its possible to either
avoid it or find a way to automatically update the control and compute nodes
with the changed WWIDs.

* Log into 01soc-control1 and do the following steps:

```
  multipath -ll  (copy the output to temp file)
  vi /etc/multipath.conf
```

* Copy the wwid for the 200M lun (deviceid 3:0:0:0 and 2:0:0:0) in the temp
  file and replace the wwid for sbd in /etc/multipath.conf
* Copy the wwid for the 15G lun (deviceid 3:0:0:1 and 2:0:0:1) in the temp
  file and replace the wwid for database in /etc/multipath.conf
* Copy the wwid for the 15G lun (deviceid 3:0:0:2 and 2:0:0:2) in the temp
  file and replace the wwid for rabbitmq in /etc/multipath.conf

```
  multipath -F
  multipath
  multipath -ll  (Verify the output looks correct)
```

* On 01soc-admin:

`scp soc-control1:/etc/multipath.conf ~`

* Reboot 01soc-control1
* Start 01soc-control2
* On 01soc-admin: 

`scp multipath.conf soc-control2:/etc/multipath.conf`
* Reboot 01soc-control2
* Start 01compute1 and 01compute2
* On 01soc-admin: 

`scp multipath.conf compute1:/etc/multipath.conf`

* On 01soc-admin:

`scp multipath.conf compute2:/etc/multipath.conf`

* Reboot 01compute1 and 01compute2

Be patient as it may take some time for the all of the resources to fully
start.

