<#
.SYNOPSIS
Helper script that created a Kubernetes cluster using Multipass and Kubeadm

.DESCRIPTION
This script creates a single master / multiple workers K3s cluster
usage: k3s.ps1 [options]
-Workers workers: number of worker nodes (defaults is 2)
-Cpu cpu: cpu used by each Multipass VM (default is 1)
-Mem mem: memory used by each Multipass VM (default is 1G)
-Disk disk: disk size (default 5G)
-Name name: prefix of node name (default is k3s)

Prerequisites:
- Multipass (https://multipass.run) must be installed
- kubectl must be installed

.EXAMPLE
./k3s.ps1

.LINK
https://github.com/yahya-j/Kubernetes-Learning/blob/master/ServiceMesh/scripts/k3s.ps1
#>

param(
  [string]
  $Name="k3s",

  [int]
  $Workers=2,

  [int]
  $Cpu=1,

  [string]
  $Mem="1G",

  [string]
  $Disk="5G"
)

function Usage {
 param(
    [string]
    $Message=""
  )
  Write-Host "---`n$Message`n---"
  Write-Host
  Write-Host "This script creates a single master / multiple workers K3s cluster"
  Write-Host "usage: k3s.sh [options]"
  Write-Host "-Cpu cpu: cpu used by each VM (default is 1)"
  Write-Host "-Mem memory: memory used by each VM (default is 1G)"
  Write-Host "-Disk disk: disk space used by each VM (default is 5G)"
  Write-Host "-Name name: prefix of node name (default is k3s)"
  Write-Host
  Write-Host "Prerequisites:"
  Write-Host "- Multipass (https://multipass.run) must be installed"
  Write-Host "- kubectl must be installed"
  exit 0
}

# Make sure Multipass is there
function Check-Multipass {
  if ((Get-Command "multipass.exe" -ErrorAction SilentlyContinue) -eq $null)
  {
     Usage -Message "Please make sure multipass.exe (https://multipass.run) is installed and available in your PATH"
  }
}

# Make sure kubectl is there
function Check-Kubectl {
  if ((Get-Command "kubectl.exe" -ErrorAction SilentlyContinue) -eq $null)
  {
     Usage -Message "Please make sure kubectl.exe is installed and available in your PATH"
  }
}

function Create-Vms {
  Write-Host "-> about to created Ubuntu VMs using Multipass (https://multipass.run)"
  for($i = 1; $i -le $($Workers+1); $i++){
    Write-Host "-> creating VM [$Name-$i]"
    Try{
      multipass launch --name $Name-$i --cpus $Cpu --mem $Mem --disk $Disk
      Write-Host "VM $Name-$i created"
    }
    Catch{
      Usage -Message "Error creating [$Name-$i] VM"
    }
  }
}

function Init-Cluster {
  Write-Host "-> initializing cluster on [$Name-1]"
  Try{
    multipass exec $Name-1 -- /bin/bash -c "curl -sfL https://get.k3s.io | sh -"
    Write-Host "cluster initialized"
  }
  Catch{
    Usage -Message usage "Error during cluster init"
  }
}

function Get-Context {
  # Get cluster's configuration
  Try{
    multipass exec $Name-1 sudo cat /etc/rancher/k3s/k3s.yaml > kubeconfig.tmp

    # Set master's external IP in the configuration file
    $IP=$((((multipass info $Name-1 | Select-String IPv4) -Split ":")[1]).trim())
    (Get-Content kubeconfig.tmp).replace('127.0.0.1', $IP) | Set-Content kubeconfig.k3s
    rm kubeconfig.tmp
  }
  Catch{
    Usage -Message "Error retreiving kubeconfig"
  }
}

function Add-Nodes {
  # Get master's IP and TOKEN used to join nodes
  $IP=$((((multipass info $Name-1 | Select-String IPv4) -Split ":")[1]).trim())
  $TOKEN=$(multipass exec $Name-1 -- sudo cat /var/lib/rancher/k3s/server/node-token)

  # Join worker nodes
  if ($Workers -ge 1) {
    for($i = 1; $i -le $Workers; $i++){
      Write-Host "-> adding worker nodes [$Name-$($i+1)]"
      Try{
        multipass exec $Name-$($i+1) -- bash -c "curl -sfL https://get.k3s.io | K3S_URL=`"https://$IP`:6443`" K3S_TOKEN=`"$TOKEN`" sh -"
        Write-Host "Node [$Name-$($i+1)] added !"
      }
      Catch{
        Write-Host "Error while joining [$Name-$($i+1)] worker node";
      }
    }
  } else {
    Write-Host "-> no worker will be added"
  }
}

function Next {
  # Setup needed on the local machine
  Write-Host
  Write-Host "Cluster is up and ready !"
  Write-Host "Please follow the next steps:"
  Write-Host
  Write-Host "- Configure your local kubectl:"
  Write-Host "`$Env:KUBECONFIG=`"`$pwd\kubeconfig.k3s`""
  Write-Host
  Write-Host "- Make sure the nodes are in READY state:"
  Write-Host "kubectl get nodes"
  Write-Host
}

Check-Multipass
Check-Kubectl
Create-Vms
Init-Cluster
Get-Context
Add-Nodes
Next
