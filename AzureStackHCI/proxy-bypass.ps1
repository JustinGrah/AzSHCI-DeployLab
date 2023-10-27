$proxyAddress = 'http://192.168.0.1'
$proxyPort = '3128'
$proxyBypassList = @('<local>','*.hci.lab')

# ===========
# DO NOT EDIT
# ===========

# assemble vars
$pUri = $proxyAddress + ':' + $proxyPort
$pBypass = @('localhost','127.0.0.1','*.svc','10.*','172.16.*','192.168.*')
$pBypass += $proxyBypassList

install set-wininetproxy

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Proxy $pUri
Register-PSRepository -Default -Proxy $pUri
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -Proxy  $pUri
Install-Module WinInetProxy -Proxy $pUri -Repository PSGallery -Force
Import-Module WinInetProxy

# Reset proxy:
[Environment]::SetEnvironmentVariable("HTTP_PROXY",$null,"Machine")
[Environment]::SetEnvironmentVariable("NO_PROXY", $null, "Machine")
Set-WinInetProxy
netsh winhttp import proxy source=ie

# setup proxy env variable
[Environment]::SetEnvironmentVariable("HTTP_PROXY",$pUri,"Machine")
[Environment]::SetEnvironmentVariable("NO_PROXY", ($pBypass -join ','), "Machine")
$env:ProxyServer = $pUri
$env:ProxyBypass = ($pBypass -join ',')
Set-WinInetProxy -ProxySettingsPerUser 0
netsh winhttp import proxy source=ie

