#Create single master and single worker cluster (all-in-one small stack version)
export storagepool="virtimages"

for i in master worker bootstrap
do 
  if [[ "$i" == "master"* ]]; then
      mem=12288
  else
      mem=8192
  fi
  sudo virt-install --name="ocp4-${i}" \
  --cpu=host --vcpus=4 --ram=${mem} \
  --controller type=scsi,model=virtio-scsi \
  --disk pool=${storagepool},bus=scsi,discard='unmap',format=qcow2,size=120 \
  --os-variant rhel8.0 --network network=openshift4,model=virtio \
  --boot hd,network,menu=on --print-xml > ocp4-$i.xml
  sudo virsh define --file ocp4-$i.xml
done

for i in bootstrap master worker
do
  echo -ne "${i}\t" ; sudo virsh dumpxml ocp4-${i} | grep "mac address" | cut -d\' -f2
done

for i in bootstrap master worker
do
  export ${i}macaddy=$(sudo virsh dumpxml ocp4-${i} | grep 'mac address' | cut -d\' -f2)
done

(
cat <<EOF
---
disk: sda
helper:
  name: "helper"
  ipaddr: "192.168.7.77"
dns:
  domain: "example.com"
  clusterid: "ocp4"
  forwarder1: "8.8.8.8"
  forwarder2: "8.8.4.4"
dhcp:
  router: "192.168.7.1"
  bcast: "192.168.7.255"
  netmask: "255.255.255.0"
  poolstart: "192.168.7.10"
  poolend: "192.168.7.30"
  ipid: "192.168.7.0"
  netmaskid: "255.255.255.0"
bootstrap:
  name: "bootstrap"
  ipaddr: "192.168.7.20"
  macaddr: "$bootstrapmacaddy"
masters:
  - name: "master"
    ipaddr: "192.168.7.21"
    macaddr: "$mastermacaddy"
workers:
  - name: "worker"
    ipaddr: "192.168.7.22"
    macaddr: "$workermacaddy"
EOF
) > aio-vars.yaml

