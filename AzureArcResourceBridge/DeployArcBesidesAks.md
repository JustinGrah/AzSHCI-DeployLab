# How do I ... Deploy the ARC ResouceBridge besides AKS?

## Setting up your enviroment
First, you should gather details on your enviroment.

```
$gateway = "192.168.0.1"    # Your Gateway.
$dnsservers = "192.168.0.1" # Your DNS Server.
$switch = "external"        # The external switch you have created for the use on your VM's
$vip = "192.168.0.52"       # An IP address that will be used for the internal load balancer. This should not interfere with your AKS VIP pool range! 
$k8sStart = "192.168.0.53"  # Start of the IP Range for all your ARC agents. 
$k8sEnd = "192.168.0.53"    # End of the IP Range for all your ARC agents. 
$ipAddressPrefix = "192.168.0.0/16"     # The CIDR of your specific subnet
$cloudServiceCidr = "192.168.0.10/16"   # IP and CIDR of the CloudAgnet (ususally the clustered service in your cluster with the name "ca-XXXXX")
$controlPlaneIp = "192.168.0.51"        # IP of the new ARC RB controlplane. Ensure that this is not interferring with your AKS controlplane!
$resourceGroup="azs-arc-aks-clus"       # Resouce group where the RB will be deployed
$subscription="18abb5c0-0be4-4675-b1c1-53c0b4e353fd"    # Subscription ID you want to use
$Location="eastus"          # Location of your RG
$customloc_name="arc-clus"  # Name of the custom location which will be used for VM deployment
$csvPath = "C:\clusterstorage\volume01\ARC" # Location to where we will store all deployment information
$resource_name= ((Get-AzureStackHci).AzureResourceName) + "-arcbridge"  #Name of the ARC RB appliance visible in the Azure Portal
```

