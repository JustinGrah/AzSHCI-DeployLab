$proxyAddress = 'http://<YOUR_PROXYURL>'
$proxyPort = '<PORT>'
$proxyBypassList = @('*.<your>.<domain>')

# ===================================
# !!! DO NOT EDIT BELOW THIS LINE !!!
# ===================================
# setup helper vars and our default exclusion list
$pUri = $proxyAddress + ':' + $proxyPort
$pBypass = @('localhost','127.0.0.1','<local>','*.svc','10.*','172.16.*','192.168.*')
$pBypass += $proxyBypassList

# install wininetproxy from psgallery
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Proxy $pUri
Register-PSRepository -Default -Proxy $pUri
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -Proxy  $pUri
Install-Module WinInetProxy -Proxy $pUri -Repository PSGallery -Force
Import-Module WinInetProxy

# reset any proxy configurations.
# we are setting these values to "null" as we want to clear any old or stale configurations
[Environment]::SetEnvironmentVariable("HTTP_PROXY",$null,"Machine")
[Environment]::SetEnvironmentVariable("NO_PROXY", $null, "Machine")
$env:ProxyServer = $null
$env:ProxyBypass = $null
Set-WinInetProxy
netsh winhttp import proxy source=ie

# setup new proxy configurations.
[Environment]::SetEnvironmentVariable("HTTP_PROXY",$pUri,"Machine")                 # required for arc connected machines agent
[Environment]::SetEnvironmentVariable("NO_PROXY", ($pBypass -join ','), "Machine")  # required for arc connected machines agent
$env:ProxyServer = $pUri                    # required to automatically fill in the set-wininetproxy
$env:ProxyBypass = ($pBypass -join ',')     # required to automatically fill in the set-wininetproxy
Set-WinInetProxy -ProxySettingsPerUser 0    # will set global proxy settings based on our env. variables
netsh winhttp import proxy source=ie        # will pull the information from the proxy we just set with the wininet