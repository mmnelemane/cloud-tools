# Some Raw documentation to help running devstack in OpenSuse Leap using vagrant box.

Running Leap with Vagrant

1. Download image : http://download.opensuse.org/repositories/openSUSE:/Leap:/42.1:/Images/images/openSUSE-Leap-42.1-JeOS-for-OpenStack-Cloud.x86_64.qcow2

2. Create metadata.json:
cat > metadata.json << EOF
{
      "provider"     : "libvirt",
      "format"       : "qcow2",
      "virtual_size" : 24
}
EOF
virtual_size is obtained using "file <imagename>.qcow2" 
"openSUSE-Leap-42.1-JeOS-for-OpenStack-Cloud.x86_64.qcow2: QEMU QCOW Image (v3), 25769803776 bytes"
virtual_size = 25769803776/1024/1024/1024

3. Create the box
tar cvzf openSUSE_Leap_42.1.box ./metadata.json ./Vagrantfile openSUSE-Leap-42.1-JeOS-for-OpenStack-Cloud.x86_64.qcow2

4. Add box
vagrant box add openSUSE_Leap_42.1.box --name opensuse

5. Bring up and SSH into the vagrant VM using Vagrantfile_leap

6. Prepare the devstack environment once inside the VM with:
git clone https://github.com/SUSE-Cloud/automation.git

zypper install git-core
zypper install python-python-subunit
zypper install bridge-utils
zypper install python-pip python3-pip
pip install -U os-testr # to avoid the error due to generate-subunit: commmand not found.
# Edit /etc/hosts to add the output of hostname as resolver for 127.0.0.1 as below
   127.0.0.1      <hostname>
   export PATH=$PATH:/usr/sbin
   sudo bash -x qa_devstack.sh
# Edit automation/scripts/jenkins/qa_devstack.sh to clone only if the devstack folder is not available 
