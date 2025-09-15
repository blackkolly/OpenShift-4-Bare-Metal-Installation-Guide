Node Boot Parameters
For each node, you'll need to customize the boot parameters with your specific network details. Here are the parameters updated for your environment:
Bootstrap Node (10.18.0.10):
coreos.inst.install_dev=sda 
coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz 
coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/bootstrap.ign ip=10.18.0.10::10.18.0.1:255.255.255.0:bootstrap.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

Master Nodes:
Master-1 (10.18.0.11):
coreos.inst.install_dev=sda 
coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz 
coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/master.ign ip=10.18.0.11::10.18.0.1:255.255.255.0:master-1.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

Master-3 (10.18.0.13):
coreos.inst.install_dev=sda 
coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz 
coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/master.ign ip=10.18.0.13::10.18.0.1:255.255.255.0:master-3.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

Worker Nodes:
Worker-1 (10.18.0.21):
coreos.inst.install_dev=sda 
coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz 
coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/worker.ign ip=10.18.0.21::10.18.0.1:255.255.255.0:worker-1.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

Worker-2 (10.18.0.22):
coreos.inst.install_dev=sda 
coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz 
coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/worker.ign ip=10.18.0.22::10.18.0.1:255.255.255.0:worker-2.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

Worker-3 (10.18.0.23):
coreos.inst.install_dev=sda 
coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz 
coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/worker.ign ip=10.18.0.23::10.18.0.1:255.255.255.0:worker-3.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105
