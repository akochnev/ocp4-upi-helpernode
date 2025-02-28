# Helper Node Quickstart Install - Static IPs

This quickstart will get you up and running on `libvirt`. This should work on other environments (i.e. Virtualbox or Enterprise networks); you just have to substitue where applicable

To start login to your virtualization server / hypervisor

```
ssh virt0.example.com
```

And create a working directory

```
mkdir ~/ocp4-workingdir
cd ~/ocp4-workingdir
```

## Create Virtual Network

Download the virtual network configuration file, [virt-net.xml](./virt-net.xml)

```
wget https://raw.githubusercontent.com/heatmiser/ocp4-upi-helpernode/master/virt-net.xml
```

Create a virtual network using this file file provided in this repo (modify if you need to).


```
virsh net-define --file virt-net.xml
```

Make sure you set it to autostart on boot

```
virsh net-autostart openshift4
virsh net-start openshift4
```

## Create a CentOS 7 VM

Download the [Kickstart file](helper-ks.cfg) for the helper node.

```
wget https://raw.githubusercontent.com/heatmiser/ocp4-upi-helpernode/master/helper-ks.cfg
```

Edit `helper-ks.cfg` for your environment and use it to install the helper. The following command installs it "unattended".

> **NOTE** Change the path to the ISO for your environment

```
virt-install --name="ocp4-helper" --vcpus=2 --ram=4096 \
--disk path=/var/lib/libvirt/images/ocp4-helper.qcow2,bus=virtio,size=30 \
--os-variant centos7.0 --network network=openshift4,model=virtio \
--boot menu=on --location /var/lib/libvirt/ISO/CentOS-7-x86_64-Minimal-1810.iso \
--initrd-inject helper-ks.cfg --extra-args "inst.ks=file:/helper-ks.cfg" --noautoconsole
```

The provided Kickstart file installs the helper with the following settings (which is based on the [virt-net.xml](./virt-net.xml) file that was used before).

* IP - 192.168.7.77
* NetMask - 255.255.255.0
* Default Gateway - 192.168.7.1
* DNS Server - 8.8.8.8

> **NOTE** If you want to use macvtap (i.e. have the VM "be on your network"); you can use `--network type=direct,source=enp0s31f6,source_mode=bridge,model=virtio` ; replace the interface where applicable

You can watch the progress by lauching the viewer

```
virt-viewer --domain-name ocp4-helper
```

Once it's done, it'll shut off...turn it on with the following command

```
virsh start ocp4-helper
```

## Prepare the Helper Node

After the helper node is installed; login to it

```
ssh root@192.168.7.77
```

Install `ansible` and `git` and clone this repo

> **NOTE** If using RHEL 7 - you need to enable the `rhel-7-server-rpms` and the `rhel-7-server-extras-rpms` repos

```
yum -y install ansible git
git clone https://github.com/heatmiser/ocp4-upi-helpernode
cd ocp4-upi-helpernode
```

Create the [vars-static.yaml](./vars-static.yaml) file with the IP addresss that will be assigned to the masters/workers/bootstrap. The IP addresses need to be right since they will be used to create your DNS server. 


## Run the playbook

Run the playbook to setup your helper node (using `-e staticips=true` to flag to ansible that you won't be installing dhcp/tftp)

```
ansible-playbook -e @vars-static.yaml -e staticips=true tasks/main.yml
```

After it is done run the following to get info about your environment and some install help

```
/usr/local/bin/helpernodecheck
```

## Create Ignition Configs

Now you can start the installation process. Create an install dir.

```
mkdir ~/ocp4
cd ~/ocp4
```

Next, create an `install-config.yaml` file

```
cat <<EOF > install-config.yaml
apiVersion: v1
baseDomain: example.com
compute:
- hyperthreading: Enabled
  name: worker
  replicas: 0
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

Visit [try.openshift.com](https://cloud.redhat.com/openshift/install) and select "Bare Metal". Then copy the pull secret. Replace `pullSecret` with that pull secret and `sshKey` with your ssh public key.

Next, generate the ignition configs

```
openshift-install create ignition-configs
```

## Set Static IPs

This playbook installs [filetranspiler](https://github.com/ashcrow/filetranspiler) for you. You can use this to set up static IP files and inject them into the ignition files.

You'll need to do this for **ALL** VMs that need it (masters/workers/bootstrap).

Here's an example for bootstrap...

Create your fakeroot dirs

```
mkdir -p bootstrap/etc/sysconfig/network-scripts/
```

Next, set up your `ifcfg-INTERFACE` file. In my case my interface is `ens3`

```
cat <<EOF > bootstrap/etc/sysconfig/network-scripts/ifcfg-ens3
DEVICE=ens3
BOOTPROTO=none
ONBOOT=yes
IPADDR=192.168.7.20
NETMASK=255.255.255.0
GATEWAY=192.168.7.1
DNS1=192.168.7.77
PREFIX=24
DEFROUTE=yes
IPV6INIT=no
EOF
```

Use the ignition file you just created as a basis for an updated one using `filetranspiler`.

```
filetranspiler -i bootstrap.ign -f bootstrap -o bootstrap-static.ign
```

> **NOTE** You need to be in the directory where your `bootstrap.ign` file and `bootstrap` dir is in.

Copy this over to your apache serving dir.

```
cp bootstrap-static.ign /var/www/html/ignition/
```

^ Do this for ALL servers in your cluster!

## Install VMs

Install each VM one by one; here's an example for my boostrap node

> **NOTE** If you want to use macvtap (i.e. have the VM "be on your network"); you can use `--network type=direct,source=enp0s31f6,source_mode=bridge,model=virtio` ; replace the interface where applicable

```
virt-install --name=ocp4-bootstrap --vcpus=4 --ram=8192 \
--disk path=/var/lib/libvirt/images/ocp4-bootstrap.qcow2,bus=virtio,size=120 \
--os-variant rhel8.0 --network network=openshift4,model=virtio \
--boot menu=on --cdrom /exports/ISO/rhcos-4.1.0-x86_64-installer.iso
```

> **NOTE** If the console doesn't launch you can open it via `virt-manager`

Once booted; press `tab` on the boot menu and add your staticips and coreos options. Here is an example of what I used for my bootstrap node. (type this **ALL IN ONE LINE** ...I only used linebreaks here for ease of readability...but type it all in one line)

```
ip=192.168.7.20::192.168.7.1:255.255.255.0:bootstrap:ens3:none:192.168.7.77
coreos.inst.install_dev=vda
coreos.inst.image_url=http://192.168.7.77:8080/install/bios.raw.gz
coreos.inst.ignition_url=http://192.168.7.77:8080/ignition/bootstrap-static.ign
```

^ Do this for ALL of your VMs

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

The boostrap VM actually does the install for you; you can track it with the following command.

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

First, login to your cluster

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
