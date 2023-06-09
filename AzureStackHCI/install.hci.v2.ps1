$vmCount = 1
$vmNamePrefix = 'HCI-N-'
$vmNames = @('ARC')
$vmOsSize = 100GB

$storagePath = 'D:\'
$storageIsoPath = 'C:\temp\hcios.iso'
$storageVhdPerNode = 8
$storageVhdSize = 250GB

for($i = 0; $i -lt $vmCount; $i++) {
    $vm = Create-HciVm -count $i
    Prepare-HciVm -vm $vm
}


function Create-HciVm() {
    param(
        $count
    )

    $name += ($vmNamePrefix + $vmNames[$count])
    Write-Host ("Creating HCI VM " + $name)
    
    $vm = New-VM -Name $name -SwitchName mgmt -Path $storagePath -NewVHDPath ($storagePath + $name + '\os.vhdx') -NewVHDSizeBytes $vmOsSize -Generation 2
    return $vm
}

function Prepare-HciVm() {
    param (
        $vm
    )

    Write-Host ('Updating RAM')
    Set-VMMemory -VMName $vm.Name -StartupBytes 50GB

    Write-Host ('Updating Network settings on ' + $vm.Name)
    Set-VMProcessor -ExposeVirtualizationExtensions:$true -Count 4 -VMName $vm.Name
    Get-VMNetworkAdapter -VMName $vm.Name | Set-VMNetworkAdapter -MacAddressSpoofing On

    Write-Host ('Adding DVD Drive to ' + $vm.name)
    $dvd = Add-VMDvdDrive -VMName $vm.Name -Path $storageIsoPath

    Write-Host ('Setting DVD to be the first in the boot order on ' + $vm.name)
    Set-VMFirmware -VMName $vm.Name -BootOrder @((Get-VMDvdDrive -VMName $vm.Name -ControllerLocation 1 -ControllerNumber 0), (Get-VMHardDiskDrive -VMName $vm.Name -ControllerLocation 0 -ControllerNumber 0))
    
    Write-Host ('Adding DVD Drive to ' + $vm.name)
    Create-DataDisks -vm $vm
}


function Create-DataDisks() {
    param (
        $vm
    )

    New-Item -Path ($storagePath + $vm.name) -Name 'SBL' -Type Directory

    for($i = 0; $i -lt $storageVhdPerNode; $i++) {
        $drivePath = ($storagePath + $vm.name + ("\SBL\SBL_DISK_" + $i + "_" + $vm.name + ".vhdx"))
        New-VHD -Path $drivePath -Dynamic -SizeBytes $storageVhdSize
        Add-VMHardDiskDrive -Path $drivePath -VMName $vm.name
    }
}

function Configure-BaseOs() {
    param (
        $vm
    )

    $adCred = Get-Credential -Message 'Please enter the AD credentials' -UserName 'hci.lab\Administrator'
    $lclCred = Get-Credential -Message 'Please enter the local machine credentials' -UserName 'Administrator'

    function Update-GeneralSettings() {
        Invoke-Command -VMName $vm.name -ScriptBlock {
            param (
                [string] $name
            )

            Write-Host ('Updating BCDEDIT settings')
            bcdedit /set hypervisorlaunchtype auto

            Write-Host ('Updating computer name')
            Rename-Computer -NewName $name -Restart

        } -Credential $lclCred -ArgumentList $vm.name
    }

    function Update-NetworkSettings() {
        Invoke-Command -VMName $vm.name -ScriptBlock {
            param(
                $domainCred,
                $localCred
            )

            $mgmtIp = '192.168.0.3'
            $dns = '192.168.0.1'
            $gateway = '192.168.0.1'

            $netAdapterConfig = @("mgmt","sbl1","sbl2")
            $i = 0;
            foreach($adapter in (Get-NetAdapter | Sort-Object -Property MacAddress)) {
                $adapter | Rename-NetAdapter -NewName $netAdapterConfig[$i]
                $i++
            }

            Write-Host ('Setting up IP address on mgmt')
            netsh interface ipv4 set address name="mgmt" static $mgmtIp 255.255.255.0 $gateway
            Start-Sleep -Seconds 5
            netsh interface ipv4 set dns name="mgmt" static $dns

            Write-Host ('Joining computer to domain')
            Add-Computer -DomainName 'hci.lab' -Credential $domainCred -Restart -LocalCredential $localCred

        } -Credential $lclCred -ArgumentList $adCred, $lclCred
    }

    function Update-WindowsFeatures() {
        Invoke-Command -VMName $vm.name -ScriptBlock {
            Write-Host ('Installing features')
            Install-WindowsFeature -name "BitLocker", "Data-Center-Bridging", "Failover-Clustering", "FS-FileServer", "FS-Data-Deduplication", "Hyper-V", "Hyper-V-PowerShell", "RSAT-AD-Powershell", "RSAT-Clustering-PowerShell", "NetworkATC", "NetworkHUD", "Storage-Replica" -IncludeAllSubFeature -IncludeManagementTools -Restart
        } -Credential $adCred
    }

    function Clean-SBLDisks() {
        Invoke-Command -VMName $vm.name -ScriptBlock {     
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
    
        } -Credential $adCred
    }    


    New-Cluster -Name 'HCI-ARC-CLUS' -Node 'HCI-N-ARC' -nostorage -StaticAddress 192.168.0.5



    function Enable-Storage() {
        Invoke-Command -VMName $vm.name -ScriptBlock {     
            Enable-ClusterStorageSpacesDirect -PoolFriendlyName "HCI-N-EN-CLUS Storage Pool" -CacheState Disabled    
        } -Credential $adCred
    }

    
}
