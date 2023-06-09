# Create a Proxy cluster

## Create the hypervisor
visit myworkspaces and create a nested virtualization lab like:


## Configure the hypervisor

**Basic configuration:**
```
$labName = "MyProxyLab"
Install-WindowsFeature -Name "Hyper-V" -IncludeAllSubFeature -IncludeManagementTools
Rename-Computer -NewName $labName
shutdown /r /t 0
```
**Create Hyper-V Switches**
```PowerShell
New-VMSwitch -Name "wan" -SwitchType Internal
New-VMSwitch -Name "mgmt" -SwitchType Internal
New-VMSwitch -Name "sbl1" -SwitchType Private
New-VMSwitch -Name "sbl2" -SwitchType Private
```
we will use the switches for the following:
1. wan - used for the network from our firewall to our host
2. mgmt - used for the cluster nodes and the DC to communicate
3. sbl1 - used for S2D storage network 1
4. sbl2 - used for S2D storage network 2

**Create WAN network**
```PowerShell
netsh interface ipv4 set address name="vEthernet (wan)" static 10.10.10.1 255.255.255.0
netsh interface ipv4 set dns name="vEthernet (wan)" static 10.10.10.2
```
WAN:
* 10.10.10.1 - Hypervisor / gateway
* 10.10.10.2 - Firewall

MGMT:
* 192.168.0.1 - Firewall / Proxy
* 192.168.0.2 - DNS / DomainController
* 192.168.0.3-4 - HCI nodes
* 192.168.0.5 - Failover Cluster

SBL:
* 10.10.100.1 - N1 SBL1
* 10.10.101.1 - N1 SBL2
* 10.10.100.2 - N2 SBL1
* 10.10.101.2 - N2 SBL2

**Create virtual machines**
```PowerShell
$c = 2          # how many total nodes
$r = 20GB       # how much ram per node
$n = "HCI-N-"   # naming scheme
$d = 'D:\'      # location where vm should be stored

for($i = 0; $i -lt $c; $i ++) {
    $vn = $n + ($i + 1)
    New-Item -Path $d -Name $vn -Type Directory | Out-Null
    New-Item -Path ($d + $vn) -Name 'virtualdisk' -Type Directory | Out-Null
    New-Vm -Name $vn -MemoryStartupBytes $r -Generation 2 -NewVHDPath ($d + $vn +'\virtualdisk\os.vhdx') -NewVHDSizeBytes 127GB -path $d
}
```

**Base configure VMs**
```PowerShell
$vms = Get-VM -Name HCI-N-*
foreach($vm in $vms) {
    $d = ($vm | Add-VMDvdDrive -Path 'C:\Users\azureuser\Downloads\hcios.iso')
    $vm | Set-VM -AutomaticStartAction Start -AutomaticStopAction TurnOff
    $vm | Set-VMProcessor -ExposeVirtualizationExtensions:$true -Count 4
    $vm | Get-VMNetworkAdapter | Set-VMNetworkAdapter -MacAddressSpoofing On

    $vm | Add-VMNetworkAdapter -SwitchName mgmt
    $vm | Add-VMNetworkAdapter -SwitchName sbl1
    $vm | Add-VMNetworkAdapter -SwitchName sbl2
    $vm | Get-VMNetworkAdapter | Where-Object {$_.SwitchName -eq $null} | Remove-VMNetworkAdapter

    $vm | Set-VMFirmware -FirstBootDevice ($d)
}
```

**Add Data disks to VMs**
```PowerShell
$datadiskPath = "D:\"
$drives = 4 # per server
$size = 250GB # 500GB per server 1000GB in total

foreach($server in $vms) {
    for($i = 0; $i -lt $drives; $i++) {
        $drivePath = ($datadiskPath + ("SBL_DISK_" + $i + "_" + $server.name + ".vhdx"))
        New-VHD -Path $drivePath -Dynamic -SizeBytes $size
        Get-VM -Name $server.name | Add-VMHardDiskDrive -Path $drivePath
    }

    $vm | Start-Vm
}
```

**Update OS settings**
```PowerShell
$credential = Get-Credential -UserName "Administrator" -Message "Please enter the HCI Admin password."
$adCred = Get-Credential -UserName "hci.lab\administrator" -Message "Enter the domain admin"
foreach($server in $vms) {
    Write-Host "updating hypervisor launch settings and adjusting computer name"
    Invoke-Command -VMName $server.name -ScriptBlock {
        param(
            $servername
        )
        bcdedit /set hypervisorlaunchtype auto

        Rename-Computer -NewName $servername -Restart

    } -ArgumentList $server.name -Credential $credential
}
```

**Configure network and join to domain**
```PowerShell
foreach($server in $vms) {
    # Wait-ForVm -vmName $server.name

    Write-Host "renaming network adapters"
    Invoke-Command -VMName $server.name -ScriptBlock {
        param(
            $servername
        )
        $serverId = $servername.split('-')[-1]
        $mgmtIp = ('192.168.0.' + (2 + $serverId))
        $sblIp1 = ('10.10.11.' + (2 + $serverId))
        $sblIp2 = ('10.10.12.' + (2 + $serverId))
        $gateway = '192.168.0.1'
        $dns = '192.168.0.1'

        $netAdapterConfig = @("mgmt","sbl1","sbl2")
        $i = 0;
        foreach($adapter in (Get-NetAdapter | Sort-Object -Property MacAddress)) {
            $adapter | Rename-NetAdapter -NewName $netAdapterConfig[$i]
            $i++
        }

        netsh interface ipv4 set address name="mgmt" static $mgmtIp 255.255.255.0 $gateway
        netsh interface ipv4 set address name="sbl1" static $sblIp1 255.255.255.0
        netsh interface ipv4 set address name="sbl2" static $sblIp2 255.255.255.0
        netsh interface ipv4 set dns name="mgmt" static $dns

        netsh Advfirewall set allprofiles state off
        
    } -ArgumentList $server.name -Credential $credential

    Write-Host "adding computer to domain"
    Invoke-Command -VMName $server.name -ScriptBlock {
        param(
            $servername,
            $credential,
            $localCred
        )
    
        Add-Computer -DomainName 'hci.lab' -Credential $credential -Restart -LocalCredential $localCred
    
    } -ArgumentList $server.name,$adCred,$credential -Credential $credential
}
```

**Install windows fatures**
```PowerShell
foreach($server in $vms) {
    Write-Host "installing programs"
    Invoke-Command -VMName $server.name -ScriptBlock {
        param(
            $servername
        )
    
        Install-WindowsFeature -name "BitLocker", "Data-Center-Bridging", "Failover-Clustering", "FS-FileServer", "FS-Data-Deduplication", "Hyper-V", "Hyper-V-PowerShell", "RSAT-AD-Powershell", "RSAT-Clustering-PowerShell", "NetworkATC", "NetworkHUD", "Storage-Replica" -IncludeAllSubFeature -IncludeManagementTools -Restart
    
    } -ArgumentList $server.name -Credential $adCred
}
```


**Clean-Up SBL Disks**
```PowerShell
foreach($server in $vms) {
    Write-Host "cleaning up SBL disks"
    Invoke-Command -VMName $server.name -ScriptBlock {
        param(
            $servername
        )
    
        Update-StorageProviderCache
        Get-StoragePool | ? IsPrimordial -eq $false | Set-StoragePool -IsReadOnly:$false -ErrorAction SilentlyContinue
        Get-StoragePool | ? IsPrimordial -eq $false | Get-VirtualDisk | Remove-VirtualDisk -Confirm:$false -ErrorAction SilentlyContinue
        Get-StoragePool | ? IsPrimordial -eq $false | Remove-StoragePool -Confirm:$false -ErrorAction SilentlyContinue
        Get-PhysicalDisk | Reset-PhysicalDisk -ErrorAction SilentlyContinue
        Get-Disk | ? Number -ne $null | ? IsBoot -ne $true | ? IsSystem -ne $true | ? PartitionStyle -ne RAW | % {
            $_ | Set-Disk -isoffline:$false
            $_ | Set-Disk -isreadonly:$false
            $_ | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
            $_ | Set-Disk -isreadonly:$true
            $_ | Set-Disk -isoffline:$true
        }
        Get-Disk | Where Number -Ne $Null | Where IsBoot -Ne $True | Where IsSystem -Ne $True | Where PartitionStyle -Eq RAW | Group -NoElement -Property FriendlyName

    } -ArgumentList $server.name -Credential $adCred
}
```

**Forming cluster**
```PowerShell
New-Cluster -Name 'HCI-CLUS' -Node 'HCI-N-1' -nostorage -StaticAddress '10.10.10.5'

Invoke-Command -VMName $vms[0].name -ScriptBlock {
    Enable-ClusterStorageSpacesDirect -PoolFriendlyName "HCI-CLUS Storage Pool" -CacheState Disabled
} -Credential $adCred
```

**Installing components on cluster**
```PowerShell
foreach($server in $vms) {
    Invoke-Command -ComputerName $server.name -ScriptBlock {
        Write-Host ("Installing Az module on node: " + $env:COMPUTERNAME)
        Install-Module Az.StackHci

        
        
        Write-Host ("Installing Az CLI on node: " + $env:COMPUTERNAME)
        $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; rm .\AzureCLI.msi

        Write-Host ("Creating external switch on node: " + $env:COMPUTERNAME)
        New-VMSwitch -NetAdapterName mgmt -Name "external" -AllowManagementOS:$true
    }  -Credential $adCred
}
```
