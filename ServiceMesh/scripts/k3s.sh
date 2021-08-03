#!/usr/bin/env bash

function usage {
  echo -e "$1\n"
  echo "This script creates a single master / multiple workers K3s cluster"
  echo "usage: k3s.sh [options]"
  echo "-w WORKERS: number of worker nodes (defaults is 2)"
  echo "-c CPU: cpu used by each VM (default is 1)"
  echo "-m MEMORY: memory used by each VM (default is 1G)"
  echo "-d DISK: disk space used by each VM (default is 5G)"
  echo "-n NAME: prefix of node name (default is k3s)"
  echo
  echo "Prerequisites:"
  echo "- Multipass (https://multipass.run) must be installed"
  echo "- kubectl must be installed"
  exit 0
}

function check-multipass {
  # Make sure Multipass is there
  multipass version 1>/dev/null 2>&1 || usage "Please install Multipass (https://multipass.run)"
}

function check-kubectl {
  # Make sure kubectl is there
  kubectl 1>/dev/null 2>&1 || usage "Please install kubectl"
}

function create-vms {
  echo "-> about to created Ubuntu VMs using Multipass (https://multipass.run)"
  for i in $(seq 1 $((WORKERS+1))); do
    echo "-> creating VM [$NAME-$i]"
    multipass launch --name $NAME-$i --cpus $CPU --mem $MEM --disk $DISK || usage "Error creating [$NAME-$i] VM"
  done
  echo $'\u2714' "VMs created"
}

function init-cluster {
  echo "-> initializing cluster on [$NAME-1]"
  multipass exec $NAME-1 -- /bin/bash -c "curl -sfL https://get.k3s.io | sh -" || usage "Error during cluster init"
  echo $'\u2714' "cluster initialized"
}

function get-context {
  # Get cluster's configuration
  multipass exec $NAME-1 sudo cat /etc/rancher/k3s/k3s.yaml > .k3s.cfg || usage "Error retreiving kubeconfig"

  # Set master's external IP in the configuration file
  IP=$(multipass info $NAME-1 | grep IPv4 | awk '{print $2}')
  cat .k3s.cfg | sed "s/127.0.0.1/$IP/" > kubeconfig.k3s
  rm .k3s.cfg
}


function add-nodes {
  # Get master's IP and TOKEN used to join nodes
  IP=$(multipass info $NAME-1 | grep IPv4 | awk '{print $2}')
  URL="https://$IP:6443"
  TOKEN=$(multipass exec $NAME-1 sudo cat /var/lib/rancher/k3s/server/node-token)

  # Join worker nodes
  if [ "${WORKERS}" -ge "1" ]; then
    for i in $(seq 1 ${WORKERS}); do
      echo "-> adding worker nodes [$NAME-$((i+1))]"
      multipass exec $NAME-$((i+1)) -- bash -c "curl -sfL https://get.k3s.io | K3S_URL=\"https://$IP:6443\" K3S_TOKEN=\"$TOKEN\" sh -"
      if [ $? -ne 0 ]; then
        echo "Error while joining [$NAME-$((i+1))] worker node";
      else
        echo $'\u2714' "Node [$NAME-$((i+1))] added !"
      fi
    done
  else
    echo "-> no worker will be added"
  fi
}

function next {
  # Setup needed on the local machine
  echo
  echo "Cluster is up and ready !"
  echo "Please follow the next steps:"
  echo
  echo "- Configure your local kubectl:"
  echo "export KUBECONFIG=\$PWD/kubeconfig.k3s"
  echo
  echo "- Make sure the nodes are in READY state:"
  echo "kubectl get nodes"
  echo
}

# Use default values if not provided
NAME="k3s"
WORKERS=2
CPU=1
MEM="1G"
DISK="5G"

# Manage arguments
while getopts "n:w:c:m:d:h" opt; do
  case $opt in
    w)
      WORKERS=$OPTARG
      ;;
    c)
      CPU=$OPTARG
      ;;
    m)
      MEM=$OPTARG
      ;;
    d)
      DISK=$OPTARG
      ;;
    n)
      NAME=$OPTARG
      ;;
    h)
      usage
      ;;
    *)
      usage
      ;;
    :)
      echo -e "Option -$OPTARG requires an argument.\n" >&2
      help
      ;;
  esac
done

check-multipass
check-kubectl
create-vms
init-cluster
get-context
add-nodes
next
