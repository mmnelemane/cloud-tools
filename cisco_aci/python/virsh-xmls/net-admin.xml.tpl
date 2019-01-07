<network>
  <name>%(_name)</name>
  <uuid>%(_uuid)</uuid>
  <bridge name='virbr%(lab_id)' stp='on' delay='0'/>
  <mac address='52:54:00:%(lab_id):00:01'/>
  <domain name='cloud%(lab_id).suse.cisco-aci.lab'/>
</network>

