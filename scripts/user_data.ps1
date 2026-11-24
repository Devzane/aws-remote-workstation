<powershell>
# ==============================================================================
# user_data.ps1 - Windows Server 2022 Workstation Automated Provisioning
# ==============================================================================

$ErrorActionPreference = "Continue"

# 1. Set Administrator password
$adminPassword = "${admin_password}"
net user Administrator $adminPassword /active:yes

# 2. Configure Remote Desktop (RDP)
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
# Allow connections from any RDP client version (NLA optional for seamless client compatibility)
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0 -Force

# 3. Configure Windows Firewall for RDP
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
New-NetFirewallRule -DisplayName "Allow RDP 3389 TCP" -Direction Inbound -LocalPort 3389 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Allow RDP 3389 UDP" -Direction Inbound -LocalPort 3389 -Protocol UDP -Action Allow -ErrorAction SilentlyContinue

# 4. Set High Performance Power Plan (prevents any sleep timeouts)
powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

# 5. Install Chocolatey Package Manager
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# 6. Refresh Path
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 7. Install Chrome, VS Code, and Git silently in background
choco install -y googlechrome vscode git --no-progress
</powershell>
