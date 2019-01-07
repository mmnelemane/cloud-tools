# Copyright 2017 SUSE Linux GnmBH
# All Rights Reserved.
#    Author: Madhu Mohan Nelemane  - mmnelemane@suse.com
#    File:   acilab.py
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#

from __future__ import print_function

import argparse
import os
import re
import sys
import ConfigParser
import fileinput
import shutil
import guestfs

def _get_config(section, param):
    config = ConfigParser.ConfigParser()
    config.read('acilab.conf')
    return config.get(section, param)

def _make_xml_from_template(template_file, variables, xml_file):
    fxml = open(xml_file, 'wr')
    xml_str = open(template_file, 'r').read() % variables
    fxml.write(xml_str)

def _define_lab_net(lab_id):
    bastion_ip = _get_config("lab%s" % lab_id, "ip_start")
    template_dir = _get_config("default", "template_dir")
    xml_dir = _get_config("default", "xml_dir")
    net_id = "%sadmin" % lab_id
    net_uuid = uuid.uuid1()
    variables = { '_name': net_id,
                  'lab_id': lab_id,
                  '_uuid': net_uuid }
    _make_xml_from_template("%s/net-admin.xml.tpl" % 
        template_dir, variables, "%s/net-admin.xml" % xml_dir)

    # Define and start the admin network
    os.system("virsh net-define %s/net-admin.xml" % xml_dir)
    os.system("virsh net-autostart %s" % net_id)
    os.system("virsh net-start %s" % net_id)

    # Add NAT Forwarding rule
    lab_ip_prefix = _get_config("default", "lab_ip_prefix")
    bastion_full_ip = "%s.%s" % (lab_ip_prefix, bastion_ip)
    bastion_str = "%ssoc-admin:%s:80:400%s" % (lab_id, bastion_full_ip, bastion_ip)
    qemu_hook_file = open('/etc/libvirt/hooks/qemu', 'r+')
    text_to_search = "#VMNAME:GUEST_IP"
    for line in fileinput.input(qemu_hook_file):
        if text_to_search in line:
            qemu_hook_file.write(line.replace(text_to_search, bastion_str))
        else:
            pass
    qemu_hook_file.close()

    # Adding /etc/hosts entry for soc-admin
    host_file = open("/etc/hosts", 'r+')
    host_file.write("%s   %ssoc-admin" % (bastion_full_ip, lab_id))


def _define_lab_vms(lab_id):
    # TODO (mmnelemane): This function currently prepares xmls with only 2 
    # interfaces. It should be updated to be flexible in choosing the number
    # of interfaces and corresponding bus address assignment.
    num_computes = _get_config("default", "number_of_computes")
    nic_count = _get_config("default", "nic_count_in_compute")
    template_dir = _get_config("default", "template_dir")
    xml_dir = _get_config("default", "xml_dir")

    for vms in range(1, num_computes + 1):
        bus_addresses = []
        for nic in range(1, nic_count + 1):
            src_bus = _get_config("nic%d:%d:%d" % (lab_id, vms, nic) , 'src_bus')
            src_slot = _get_config("nic%d:%d:%d" % (lab_id, vms, nic), 'src_slot')
            src_function = _get_config("nic%d:%d:%d" % (lab_id, vms, nic), 'src_function')
            vm_bus = _get_config("nic%d:%d:%d" % (lab_id, vms, nic), 'vm_bus')
            vm_slot = _get_config("nic%d:%d:%d" % (lab_id, vms, nic), 'vm_slot')
            vm_function = _get_config("nic%d:%d:%d" % (lab_id, vms, nic), 'vm_function')
            srcbusaddr = "bus='%s' slot='%s' function='%s'" % (src_bus, src_slot, src_function)
            vmbusaddr = "bus='%s' slot='%s' function='%s'" % (vm_bus, vm_slot, vm_function)
            bus_addresses.append({'src_bus_address': srcbusaddr,
                                   'vm_bus_address': vmbusaddr })
        vm_uuid = uuid.uuid1()
        template_vars = { 'lab_id': lab_id,
                          '_uuid': vm_uuid,
                          'src_bus_address_nic1': bus_addresses[0]['src_bus_address'],
                          'vm_bus_address_nic1': bus_addresses[0]['vm_bus_address'],
                          'src_bus_address_nic2': bus_addresses[1]['src_bus_address'],
                          'vm_bus_address_nic2': bus_addresses[1]['vm_bus_address'] } 
        _make_xml_from_template("%s/soc-compute.xml.tpl" % template_dir,
            template_vars, "%s/%dsoc-compute%d.xml" % (xml_dir, lab_id, vms))

        os.system("virsh define %s/%dsoc-compute%d.xml" % (xml_dir, lab_id, vms))


def _copy_admin_image(lab_id, soc_version):
    # Modifying the Admin Guest Image
    # TODO (mmnelemane): Extend this to modify the raw SLE image instead
    # of the prebuilt admin image.
    image_path = _get_config('default', 'libvirt_image_path')
    bastion_ip = _get_config("lab%s" % lab_id, 'ip_start')

    # Copy an existing saved image.
    shutil.copy("%s/soc%s-admin.qcow2.before-install-suse-cloud.patched" 
        % (image_path, soc_version),
        "%s/%ssoc-admin.qcow2"
        % (image_path, lab_id))

    # Locally mount the admin image
    gfs = guestfs.GuestFS(python_return_dict=True)
    local_mountpoint = "/tmp/guestmount%s.used" % lab_id
    os.mkdir(local_mountpoint)
    gfs.mount_local("/tmp/guestmount%s.used" % lab_id)

    # Update New Bastion IP in the config files of the mounted image
    new_ip = "192.168.100.%s" % bastion_ip
    for source in ["etc/sysconfig/network/ifcfg-eth1",
                   "etc/hosts",
                   "etc/crowabr/network.json"]:
        dest = open("%s/source" % local_mountpoint, "w")
        f_content = dest.read()
        f_content = re.sub(r'192.168.100.30', new_ip, f_content)
        dest.seek(0)
        dest.truncate()
        dest.write(f_content)
        dest.close()

    # Unmount the local image
    g.umount(local_mountpoint)

    # Delete the mount point 
    shutil.rmtree(local_mountpoint)


def _create_node_disks(lab_id):
    # TODO (mmnelemane): Figure out a way to avoid this hard-coding
    # Instead a better method of either fetching the file names or
    # recording them in the config file should be devised.
    image_path = _get_config("default", "libvirt_image_path")
    disk_files = ["soc-control1.qcow2",
                  "soc-control1-cinder.qcow2",
                  "soc-control2.qcow2",
                  "soc-control2-cinder.qcow2",
                  "compute1.qcow2",
                  "compute2.qcow2"]
    for disk in disk_files:
        os.system("qemu-img create -f qcow2 %s/%s%s 40G" % (image_path, lab_id, disk))


def create_lab(args):
    lab_id = args.lab_id
    with_ha = args.with_ha

    _define_lab_net(lab_id)
    _define_lab_vms(lab_id)
    _copy_admin_image(lab_id)
    _create_node_disks(lab_id)


def list_backups(args):
    # [{ 'name' : 'backup_name'
    #   'lab_id': <lab_id>
    #   'soc-version': '6'
    #   'path': <image_path> 
    #   'comment': <description/comment> }]

    lab_id = args.lab_id
    soc_version = args.soc_version

    backup_file = _get_config('default', 'backup_file')
    bf = open(backup_file, 'r')
    bk_list = [eval(x) for x in filter(None, bf.read().split('\n'))]
    
    if len(bk_list) == 0:
        print("No Backups Available.")
        return

    print("|lab_id".ljust(10),
          "|soc-version".ljust(10),
          "|name".ljust(20),
          "|path".ljust(30),
          "|comment".ljust(50))

    for item in bk_list:
        print(item['lab_id'].ljust(10),
              str(item['soc-version']).ljust(10),
              item['name'].ljust(20),
              item['path'].ljust(30),
              item['comment'].ljust(50))


def _check_if_backup_exists(backup_name, backup_file):
    ret_val = False;
    bf = open(backup_file, 'r')
    bk_list = [eval(x) for x in filter(None, bf.read().split('\n'))]
    for item in bk_list:
        if item.name == backup_name:
            ret_val = True
    return ret_val
    

def backup_lab(args):
    # The backups are recorded as a list of dictionaries in the specified
    # backup record file and retrieved through list_backups() function.
    # The file is also used by the restore_lab() to fetch the right images
    # and deploy them from its properties. Only the backups listed here can
    # be restored.
    # [{ 'name' : 'backup_name'
    #   'lab_id': <lab_id>
    #   'soc-version': '6'
    #   'path': <image_path> 
    #   'comment': <description/comment> }]

    lab_id = args.lab_id
    soc_version = args.soc_version
    title = args.title
    comment = args.comment

    backup_file = _get_config('default', 'backup_file')
    backup_path = _get_config('default', 'backup_storage_path')
    image_path = _get_config('default', 'libvirt_image_path')
    backup_name = "%ssoc%d-lab-%s" % (lab_id, soc_version, title)
    backup_record = {'name': backup_name, 'lab_id': lab_id,
        'soc-version': soc_version, 'path': backup_path,
        'commemt': comment }
    if not _check_if_backup_exists(backup_file, backup_name): 
        bf = open(backup_file, 'r+')
        bf.write(backup_record)
    else:
        print("ERROR: Duplicate Backup!!! use a different name/title")
        return

    # Create a backup path for this lab in the default backup folder
    os.mkdir("%s/%sbackups" % (backup_path, lab_id))

    for file_name in os.listdir(image_path):
        if file_name.startswith(lab_id) and file_name.endswith('qcow2'):
            shutil.copy("%s/%s" % (image_path, file_name),
                "%s/%s-%s" % (backup_path, backup_name, file_name))


def restore_lab(args):
    # IODO (mmnelemane): Check if the restore is complted by listing and
    # verifying against the files in backup folder before returning or
    # deleting from the backup entry and provide suitable warning

    lab_id = args.lab_id
    soc_version = args.soc_version
    backup_name = args.backup_name
    with_delete = args.with_delete

    backup_file = _get_config('default', 'backup_file')
    backup_path = _get_config('default', 'backup_storage_path')
    image_path = _get_config('default', 'libvirt_image_path')
    if not _check_if_backup_exists(backup_name, backup_file):
        print("ERROR: Backup with name %s does not exist. Cannot restore" % backup_name)
        return
    if not os.path.exists("%s/%sbackups" % (backup_path, lab_id)):
        print("ERROR: The backup path do not exist for this lab. Cannot restore")
        return
    if not os.listdir("%s/%sbackups" % (backup_path, lab_id)):
        print("ERROR: No backup files for this lab. Cannot restore.")
        return
    for file_name in os.listdir("%s/%sbackups" % (backup_path, lab_id)):
        if file_name.startswith(backup_name) and file_name.endswith('qcow2'):
            base_filename = file_name.split('%s-' % backup_name)[1]
            print("Restoring %s for lab %s" % (base_filename, lab_id))
            shutil.copy(file_name, "%s/%s" % (image_path, base_filename))
            # remove the backup copy once restore is done.
            if (with_delete):
                os.remove("%s/%s" % (backup_path, file_name))
    
    # Delete entry in backup file for this backup if called with delete option
    if with_delete:
        bf = open(backup_file, 'r+')
        lines = bf.readlines()
        bf.seek(0)
        for line in lines:
            if not line.contains(backup_name):
                bf.write(line)
        bf.truncate()
        bf.close()
    else:
        print("WARNING: The files are redundant if the restore is successful. Make sure the\
        file and the entries in the backup record are cleared before creating another backup.")

            
def destroy_lab(args):
    # This function stops all the running VMs, deletes the instances and cache
    # if any and deletes the images in the main image path. It however does not
    # create or delete any of the backups. You need to use the backup functions
    # to work with the backup images.

    lab_id = args.lab_id
    soc_version = args.soc_version

    image_path = _get_config('default', 'libvirt_image_path')
    domain_names = []
    conn = libvirt.open('qemu:///system')
    if conn == None:
        print("Failed to open connection to qemu:///system", file=sys.stderr)
        return

    domains = conn.listAllDomains()
    if domains == None:
        print("Failed to get a list of domainIDs", file=sys.stderr)
        conn.close()
        return

    print("Active Domains:")
    if len(domains) == 0:
        print('  None')
    else:
        for domain in domains:
            print(' '+str(domain.name()))
            domain_names.append(domain.name())

    # Destroy and Undefine the lab instances.
    if len(domain_names) == 0:
        print ("No virtual Domains found to destroy")
    else:
        for domain in domain_names:
            dom = conn.lookupByName(domain)
            dom.shutdown()
            dom.destroy()
            dom.undefine()

    conn.close()


def list_labs():
    # TODO (mmnelemane): Implementation to list all available labs
    pass


def show_lab(args):
    # TODO (mmnelemane): Implementation to show data from the input lab
    lab_id = args.lab_id


def parse_args():
    parser = argparse.ArgumentParser(description="Useful commands for the ACI setup.")
    subparsers = parser.add_subparsers(help='sub-command help')

    parser_create_lab = subparsers.add_parser(
        'create', help='Create lab from existing or new images')
    parser_create_lab.add_argument('--lab-id', metavar='ID', type=str)
    parser_create_lab.add_argument('--with-ha', metavar='ID', type=bool)
    parser_create_lab.set_defaults(func=create_lab)

    parser_delete_lab = subparsers.add_parser(
        'destroy', help='Destroy and undefined the specified lab with artifacts')
    parser_delete_lab.add_argument('--lab-id', metavar='ID', type=str)
    parser_delete_lab.set_defaults(func=destroy_lab)

    parser_backup_lab = subparsers.add_parser(
        'backup', help='Backup current lab in the given location')
    parser_backup_lab.add_argument('--lab-id', metavar='ID', type=str)
    parser_backup_lab.add_argument('--soc-version', metavar='ID', type=str)
    parser_backup_lab.add_argument('--title', metavar='ID', type=str)
    parser_backup_lab.add_argument('--comment', metavar='ID', type=str)
    parser_backup_lab.set_defaults(func=backup_lab)

    parser_list_backups = subparsers.add_parser(
        'list-backups', help='Lists the available backup entries')
    parser_list_backups.add_argument('--lab-id', metavar='ID', type=str)
    parser_list_backups.add_argument('--soc-version', metavar='ID', type=str)
    parser_list_backups.set_defaults(func=list_backups)

    parser_restore_lab = subparsers.add_parser(
        'restore', help='Restores lab from the available backups')
    parser_restore_lab.add_argument('--lab-id', metavar='ID', type=str)
    parser_restore_lab.add_argument('--soc-version', metavar='ID', type=str)
    parser_restore_lab.add_argument('--backup-name', metavar='ID', type=str)
    parser_restore_lab.add_argument('--with-delete', metavar='ID', type=bool)
    parser_restore_lab.set_defaults(func=restore_lab)

    parser_list_labs = subparsers.add_parser(
        'list', help='List all available labs')
    parser_list_labs.set_defaults(func=list_labs)

    parser_show_lab = subparsers.add_parser(
        'show', help='Show details of the given lab')
    parser_show_lab.add_argument('--lab-id', metavar='ID', type=str)
    parser_show_lab.set_defaults(func=show_lab)

    return parser.parse_args()


def main():
    args = parse_args()
    args.func(args)

if __name__=="__main__":
    main()


# This function is still under comment only as documentation
# It can be removed when this is documented properly elsewhere.
# def _create_screens():
#     # $1 is the lab number
#     echo "Creating a screen session with windows for each VM"
#     screen -h 1000 -dmS ${1}soclab -t ${1}lab-host
#     screen -S ${1}soclab -X screen -t ${1}soc-admin
#     screen -S ${1}soclab -X screen -t soc-control1
#     screen -S ${1}soclab -X screen -t soc-control2
#     screen -S ${1}soclab -X screen -t compute1
#     screen -S ${1}soclab -X screen -t compute2

