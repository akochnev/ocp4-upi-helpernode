# Helper Node Quickstart Install

Forked from [christianh814/ocp4-upi-helpernode](https://github.com/christianh814/ocp4-upi-helpernode) in order to customize portions of the OCP4 UPI installation and deployment process. Many thanks to Christian Hernandez for a fantastic base to work from!

This quickstart will get you up and running on `libvirt`. This should work on other environments (i.e. Virtualbox); you just have to figure out how to do the virtual network on your own.

> **NOTE** If you want to use static ips follow [this guide](qs-static.md)

To get started, login to your virtualization server / hypervisor. Example KVM hypervisor kickstarts for [CentOS 7](centos7-hypervisor-ks.cfg) and [RHEL 7](rhel7-hypervisor-ks.cfg) (RHEL 7 kickstart requires edits for RH user account/password or subscription id/activation key prior to launching installation)

```
ssh virt0.example.com
```

...and create a working directory:

```
mkdir ~/ocp4-workingdir
cd ~/ocp4-workingdir
```

## Create Virtual Network

Download the virtual network configuration file, [virt-net.xml](./virt-net.xml):

```
wget https://raw.githubusercontent.com/heatmiser/ocp4-upi-helpernode/master/virt-net.xml
```

Create a virtual network using virt-net.xml (examine settings in virt-net.xml prior to creating via virsh, modification for your environment may be required, however, note that this may impact the IP address scheme utilized in this quickstart):

```
virsh net-define --file virt-net.xml
```

Make sure you set the openshift4 net to autostart on boot:

```
virsh net-autostart openshift4
virsh net-start openshift4
```

## Create CentOS 7 VM or RHEL 7 VM - refer to the appropriate section depending on your OS choice

__Create a CentOS 7 VM__

Download the [Kickstart file](centos7-helper-ks.cfg) for the helper node:

```
wget https://raw.githubusercontent.com/heatmiser/ocp4-upi-helpernode/master/centos7-helper-ks.cfg
```

Edit `centos7-helper-ks.cfg` for your environment and use it to install the helper. The following command installs it "unattended":

> **NOTE** Change the path to the ISO for your environment

```
virt-install --name="ocp4-helper" --vcpus=2 --ram=4096 \
--disk path=/var/lib/libvirt/images/ocp4-helper.qcow2,bus=virtio,size=30 \
--os-variant centos7.0 --network network=openshift4,model=virtio \
--boot menu=on --location /var/lib/libvirt/ISO/CentOS-7-x86_64-Minimal-1810.iso \
--initrd-inject centos7-helper-ks.cfg --extra-args "inst.ks=file:/centos7-helper-ks.cfg" --noautoconsole
```

__Create a RHEL 7 VM__

Download the [Kickstart file](rhel7-helper-ks.cfg) for the helper node:

```
wget https://raw.githubusercontent.com/heatmiser/ocp4-upi-helpernode/master/rhel7-helper-ks.cfg
```

Edit `rhel7-helper-ks.cfg` for your environment and use it to install the helper VM. In the "Register Red Hat Subscription post script section of `rhel7-helper-ks.cfg`, either use your Red Hat account username/password OR subscription org ID and subscription activation key ([more precise selection of a specific subscription](https://access.redhat.com/articles/1378093)) and make sure the credentials combination you are NOT USING is commented out. The following command installs the helper VM "unattended":

> **NOTE** Change the path to the ISO for your environment

```
virt-install --name="ocp4-helper" --vcpus=2 --ram=4096 \
--disk path=/var/lib/libvirt/images/ocp4-helper.qcow2,bus=virtio,size=30 \
--os-variant rhel7.0 --network network=openshift4,model=virtio \
--boot menu=on --location /var/lib/libvirt/ISO/rhel-server-7.7-x86_64-dvd.iso \
--initrd-inject rhel7-helper-ks.cfg --extra-args "inst.ks=file:/rhel7-helper-ks.cfg" --noautoconsole
```

__Helper VM created, continue...__

Both the CentOS and RHEL Kickstarts configure the helper VM with the following network settings (which is based on virtual network configured via [virt-net.xml](./virt-net.xml) utilized  before).

* IP - 192.168.7.77
* NetMask - 255.255.255.0
* Default Gateway - 192.168.7.1
* DNS Server - 8.8.8.8

You can watch the progress by lauching the viewer:

```
virt-viewer --domain-name ocp4-helper
```

Once the installation is complete, the helper VM will shut down.

## Create "empty" VMs for OCP4 cluster (bootstrap, masters, and workers)

Create (but do NOT install) 6 empty VMs. Please follow the [min requirements](https://docs.openshift.com/container-platform/4.1/installing/installing_bare_metal/installing-bare-metal.html#minimum-resource-requirements_installing-bare-metal) for these VMs. 

> Make sure you attached these to the `openshift4` network!

```
storagepool="default"
for i in master{0..2} worker{0..1} bootstrap
do
  if [[ "$i" == "master"* ]]; then
      mem=12288
  else
      mem=8192
  fi
  virt-install --name="ocp4-${i}" \
  --cpu=host --vcpus=4 --ram=${mem} \
  --controller type=scsi,model=virtio-scsi \
  --disk pool=${storagepool},bus=scsi,discard='unmap',format=qcow2,size=120 \
  --os-variant rhel8.0 --network network=openshift4,model=virtio \
  --boot hd,network,menu=on --print-xml > ocp4-$i.xml
  virsh define --file ocp4-$i.xml
done
```

## Prepare the Helper Node

Start the helper VM with the following command:

```
virsh start ocp4-helper
```

Once boot-up has completed, either login to the ocp4-helper console via virt-viewer or ssh into ocp4-helper from a terminal session on the hypervisor:

```
ssh root@192.168.7.77
```

Install `ansible` and `git` and then clone [this repo](https://github.com/heatmiser/ocp4-upi-helpernode.git)

> **NOTE** If you installed your RHEL 7 helper node with the provided rhel7-helper-ks.cfg kickstart, ansible and git are already installed, skip the yum step listed below - otherwise, you will need to enable the `rhel-7-server-rpms` and the `rhel-7-server-extras-rpms` repos via `subscription-manager`:

```
yum -y install ansible git
git clone https://github.com/heatmiser/ocp4-upi-helpernode
cd ocp4-upi-helpernode
```

Edit the [vars.yaml](./vars.yaml) file with the mac addresses of the "blank" VMs. Get the MAC addresses with this command from a terminal session on your hypervisor host:

```
for i in bootstrap master{0..2} worker{0..1}
do
  echo -ne "ocp4-${i}\t" ; virsh dumpxml ocp4-${i} | grep "mac address" | cut -d\' -f2
done
```

## Run the ansible playbook

Run the ansible playbook to setup your helper node:

```
ansible-playbook -e @vars.yaml tasks/main.yml
```

After the playbook has completed, execute `helpernodecheck` to get info about your environment and some install help:


```
/usr/local/bin/helpernodecheck
```

## Create Ignition Configs

Now you can start the installation process. Create an install dir:

```
mkdir ~/ocp4
cd ~/ocp4
```

Next, create an `install-config.yaml` file:

```
cat <<EOF > install-config.yaml
apiVersion: v1
baseDomain: example.com
compute:
- hyperthreading: Enabled
  name: worker
  replicas: 2
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 3
metadata:
  name: ocp4
networking:
  clusterNetworks:
  - cidr: 10.254.0.0/16
    hostPrefix: 24
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '{"auths": ...}'
sshKey: 'ssh-ed25519 AAAA...'
EOF
```

Visit [try.openshift.com](https://cloud.redhat.com/openshift/install) and select "Bare Metal". Then copy the pull secret. Replace `pullSecret` with that pull secret and `sshKey` with your ssh public key making sure to do so within the single quotes.

Next, generate the ignition configs:

```
openshift-install create ignition-configs
```

Finally, copy the ignition files in the `ignition` directory for the webserver:

```
cp ~/ocp4/*.ign /var/www/html/ignition/
restorecon -vR /var/www/html/
```

## Install VMs

Launch `virt-manager`, and boot the VMs (follow the boot order presented after the picture) into the boot menu; and select PXE. You'll be presented with the following picture:

![pxe](images/pxe.png)

Boot/install the VMs in the following order

* Bootstrap
* Masters
* Workers

On your laptop/workstation visit the status page 

```
firefox http://192.168.7.77:9000
```

You'll see the bootstrap turn "green" and then the masters turn "green", then the bootstrap turn "red". This is your indication that you can continue.

## Wait for install

The boostrap VM actually does the install for you; while still on the helper VM in the in the ~/ocp4 directory, you can track the bootstrapping process with the following command:

```
openshift-install wait-for bootstrap-complete --log-level debug
```

Once you see this message below...

```
DEBUG OpenShift Installer v4.1.0-201905212232-dirty 
DEBUG Built from commit 71d8978039726046929729ad15302973e3da18ce 
INFO Waiting up to 30m0s for the Kubernetes API at https://api.ocp4.example.com:6443... 
INFO API v1.13.4+838b4fa up                       
INFO Waiting up to 30m0s for bootstrapping to complete... 
DEBUG Bootstrap status: complete                   
INFO It is now safe to remove the bootstrap resources
```

...you can continue....at this point you can delete the bootstrap server.

## Finish Install

First, login to your cluster. Again, on the helper VM, execute the following in a terminal session:

```
export KUBECONFIG=/root/ocp4/auth/kubeconfig
```

Set up storage for you registry (to use PVs follow [this](https://docs.openshift.com/container-platform/4.1/installing/installing_bare_metal/installing-bare-metal.html#registry-configuring-storage-baremetal_installing-bare-metal)

```
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}'
```

If you need to expose the registry, run this command

```
oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"defaultRoute":true}}'
```

> Note: You can watch the operators running with `oc get clusteroperators`

Watch your CSRs. These can take some time; go get come coffee or grab some lunch. You'll see your nodes' CSRs in "Pending" (unless they were "auto approved", if so, you can jump to the `wait-for install-complete` step)

```
watch oc get csr
```

To approve them all in one shot...

> **NOTE** You need to install `epel-release` in order to install `jq`

```
oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs oc adm certificate approve
```

Check for the approval status (it should say "Approved,Issued")

```
oc get csr | grep 'system:node'
```

Once Approved; finish up the install process

```
openshift-install wait-for install-complete 
```

## Upgrade

If you didn't install the latest 4.1.Z release...then just run the following

```
oc adm upgrade --to-latest=true
```

## DONE

Your install should be done! You're a UPI master!
