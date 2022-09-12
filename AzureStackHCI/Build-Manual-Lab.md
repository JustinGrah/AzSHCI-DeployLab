## Download the required ISO files onto the Hyper-V Host
1. `mkdir C:\temp` - Create a temp folder for the downloads
2. `(New-Object System.Net.WebClient).DownloadFile('https://software-download.microsoft.com/download/pr/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso','C:\temp\server-2019.iso')`
3. `(New-Object System.Net.WebClient).DownloadFile('https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_en-us.iso','C:\temp\azshci-21H2.iso')`
4. `(New-Object System.Net.WebClient).DownloadFile('https://download.microsoft.com/download/1/0/5/1059800B-F375-451C-B37E-758FFC7C8C8B/WindowsAdminCenter2110.msi','C:\temp\Wac.msi')`

## Setup the Hyper-V Host
1. Install Windows features
   1. `Install-WindowsFeature -Name "Hyper-V" -IncludeAllSubFeature -IncludeManagementTools`
2. Create a VMNat for the internet connection inside the VMs
   1. `New-NetNat -Name "MyWanNat" -InternalIPInterfaceAddressPrefix "192.168.178.0/24"`
   2. `New-VMSwitch -Name VmNAT -SwitchType Internal`
   3. `Get-NetAdapter "vEthernet (VmNat)" | New-NetIPAddress -IPAddress 192.168.178.1 -AddressFamily IPv4 -PrefixLength 24`
   4. Setup the VMSwitches
      1. `New-VMSwitch -Name "management" -SwitchType Internal`
      2. `New-VMSwitch -Name "sbl1" -SwitchType Internal`
      3. `New-VMSwitch -Name "sbl2" -SwitchType Internal`
3. Create your virtual machines
   1. You will need 4 VMs (Depending on your cluster you want to build)
      1. azs-gw -> This will be your gateway. This holds: DNS, AD and if wanted, DHCP
      2. azs-mgmt -> This will be your WAC server. You can use this to access the WAC and to manage the Servers
      3. azs-node-1
      4. azs-node-2
   2. Connect your VM's
      1. azs-gw -> Connect to "VmNAT" and "managment"
      2. azs-mgmt -> Connect to "management"
      3. azs-node-1 -> Connect to "management", "sbl1" and "sbl2"
      4. azs-node-2 -> Connect to "management", "sbl1" and "sbl2"
   3. Add the Virtual Disks for storage
      1. Setup variables
         1. `$VMs = "azs-node-1","azs-node-2"`
         2. `$Path = "F:\Virtual Hard Disks\"`
         3. `$TotalVolume = 2000`
         4. `$DisksPerNode = 7`
      2. Run this PowerShell Script to create and add all disks
```
$TotalDisks = $DisksPerNode * ($VMs.Count)
$SizePerDisk = [Math]::floor($TotalVolume / $TotalDisks)
$BytesPerDisk = $SizePerDisk * 1073741824

for($i = 0; $i -lt $TotalDisks; $i++) {
    New-VHD -Path ($Path + "Data_Disk_" + $i + ".vhdx") -Dynamic -SizeBytes ($BytesPerDisk.ToString())
}

$j,$k = 0,0;

for($i = 0; $i -lt $TotalDisks; $i++) {
    
    if($j -ge $DisksPerNode) {
        $j = 0
        $k++
    }
    Get-VM $VMs[$k] | Add-VMHardDiskDrive -ControllerType SCSI -ControllerLocation $j -Path ($Path + "Data_Disk_" + $i +".vhdx")
    $j++
}
```
   4. Set the processor settings
      1. `Set-VMProcessor -VMName $VMs -ExposeVirtualizationExtensions $true`
      2. `Get-VMNetworkAdapter -VMName $VMs| Set-VMNetworkAdapter -MacAddressSpoofing On`

## Setup the Gateway Server
1. Install windows features (We will only cover the static IP deployment here)
   1. `Install-WindowsFeature -Name "AD-Domain-Services","DNS" -IncludeAllSubFeature -IncludeManagementTools`
2. Setup Networking
   1. Rename the Network Adapters
      1. `Get-NetAdapter `
      2. `Rename-NetAdapter "OLDNAME" "NEWNAME"`
   2. Assing IP addreses
      1. `netsh interface ipv4 set address NAME="VmNat" static 192.168.178.2 255.255.255.0 192.168.178.1`
      2. `netsh interface ipv4 set address NAME="Management" static 10.10.1.1 255.255.255.0 192.168.2`
      3. `netsh interface ipv4 set dns NAME="Management" static 10.10.1.1``
   3. Create a new NAT for the internal traffic
      1. `New-NetNat -Name "MyWanNat" -InternalIPInterfaceAddressPrefix "10.10.1.0/24"`
3. Rename Computer
   1. `Rename-Computer "azs-gw"`
4. Configure AD
   1. `Install-ADDSForest -DomainName "azs-hci-arc.demo" -InstallDNS`

## Setup the Managemnet Node
1. `Install-WindowsFeature -Name "RSAT" -IncludeAllSubFeature -IncludeManagementTools`
2. Rename Computer
   1. `Rename-Computer "azs-mgmt"`
3. Rename the Network Adapters
      1. `Get-NetAdapter `
      2. `Rename-NetAdapter "OLDNAME" "NEWNAME"`
   1. Assing IP addresses
      1. `netsh interface ipv4 set address NAME="Management" static 10.10.1.2 255.255.255.0 192.168.2`
      2. `netsh interface ipv4 set dns NAME="Management" static 10.10.1.1`
4. Download Edge and WAC
   1. `mkdir C:\temp` - Create a temp dir to store the MSI for WAC and the EDGE exe
   2. `(New-Object System.Net.WebClient).DownloadFile('https://c2rsetup.officeapps.live.com/c2r/downloadEdge.aspx?platform=Default&source=EdgeStablePage&Channel=Stable&language=en&consent=1','C:\temp\edge.exe')`
   3. `(New-Object System.Net.WebClient).DownloadFile('https://aka.ms/wacdownload','C:\temp\wac.msi')`

## Setup the HCI nodes
1. Rename Computer
   1. `Rename-Computer "azs-node-X"` -> Replace X with the node number
2. Set the hypervisorlaunch type
   1. `bcdedit /set hypervisorlaunchtype auto`
3. Setup Networking
   1. Assing IP address
      1. `netsh interface ipv4 set address NAME="Management" static 10.10.1.X 255.255.255.0 10.10.1.1` -> replace X with the node number
      2. `netsh interface ipv4 set address NAME="SBL1" static 192.168.1.X 255.255.255.0` -> replace X with the node number
      3. `netsh interface ipv4 set address NAME="SBL2" static 192.168.2.X 255.255.255.0 ` -> replace X with the node number
4. Restart the Server
   1. `Restar-Computer`