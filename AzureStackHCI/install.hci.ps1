# install hypervisor roles
Install-WindowsFeature -Name "AD-Domain-Services","Hyper-V","DHCP","RSAT"  -IncludeAllSubFeature -IncludeManagementTools
Rename-Computer -NewName "22H2-Strech"
shutdown /r /t 0

# promote and create domain controller
Install-ADDSForest -DomainName "hci.lab" -InstallDns:$true

# add switches
New-VMSwitch -Name "mgmt" -SwitchType Internal
New-VMSwitch -Name "sbl1-site-b" -SwitchType Private
New-VMSwitch -Name "sbl2-site-a" -SwitchType Private

#create net nat
netsh interface ipv4 set address name="vEthernet (mgmt)" static 192.168.0.1 255.255.255.0
netsh interface ipv4 set dns name="vEthernet (mgmt)" static 192.168.0.1

New-NetNat -Name "HCI-NAT" -InternalIPInterfaceAddressPrefix 192.168.0.0/24

New-VM 


# create VM#s
$vms = Get-VM -Name HCI-N-2

$vms | Add-VMNetworkAdapter -SwitchName SBL1
$vms | Add-VMNetworkAdapter -SwitchName SBL2

# update settings from vms
$vms | Set-VMProcessor -ExposeVirtualizationExtensions:$true -Count 4
$vms | Get-VMNetworkAdapter | Set-VMNetworkAdapter -MacAddressSpoofing On

# create data disks and attach them
$datadiskPath = "D:\"
$drives = 8 # per server
$size = 250GB # 500GB per server 1000GB in total

foreach($server in $vms) {
    for($i = 0; $i -lt $drives; $i++) {
        $drivePath = ($datadiskPath + ("SBL_DISK_" + $i + "_" + $server.name + ".vhdx"))
        New-VHD -Path $drivePath -Dynamic -SizeBytes $size
        Get-VM -Name $server.name | Add-VMHardDiskDrive -Path $drivePath
    }
}

# configure servers
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


foreach($server in $vms) {
    Write-Host "renaming network adapters"
    Invoke-Command -VMName $server.name -ScriptBlock {
        param(
            $servername
        )
        # $serverId = $servername.split('-')[-1]
        $mgmtIp = ('10.10.10.' + (2 + 1))
        # $sblIp1 = ('10.10.11.' + (2 + $serverId))
        # $sblIp2 = ('10.10.12.' + (2 + $serverId))
        $gateway = '10.10.10.1'
        $dns = '10.10.10.1'

        $netAdapterConfig = @("mgmt","sbl1","sbl2")
        $i = 0;
        foreach($adapter in (Get-NetAdapter | Sort-Object -Property MacAddress)) {
            $adapter | Rename-NetAdapter -NewName $netAdapterConfig[$i]
            $i++
        }

        netsh interface ipv4 set address name="mgmt" static $mgmtIp 255.255.255.0 $gateway
        # netsh interface ipv4 set address name="sbl1" static $sblIp1 255.255.255.0
        # netsh interface ipv4 set address name="sbl2" static $sblIp2 255.255.255.0
        Start-Sleep -Seconds 10
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

foreach($server in $vms) {
    Write-Host "installing programs"
    Invoke-Command -VMName $server.name -ScriptBlock {
        param(
            $servername
        )
    
        Install-WindowsFeature -name "BitLocker", "Data-Center-Bridging", "Failover-Clustering", "FS-FileServer", "FS-Data-Deduplication", "Hyper-V", "Hyper-V-PowerShell", "RSAT-AD-Powershell", "RSAT-Clustering-PowerShell", "NetworkATC", "NetworkHUD", "Storage-Replica" -IncludeAllSubFeature -IncludeManagementTools -Restart
    
    } -ArgumentList $server.name -Credential $adCred
}

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

# create cluster
New-Cluster -Name 'HCI-N-EN-CLUS' -Node 'HCI-N-EN' -nostorage -StaticAddress '10.10.10.5'

Invoke-Command -VMName $vms[0].name -ScriptBlock {
    Enable-ClusterStorageSpacesDirect -PoolFriendlyName "HCI-N-EN-CLUS Storage Pool" -CacheState Disabled
} -Credential $adCred



# after cluster has been created
$nodes = Get-ClusterNode

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