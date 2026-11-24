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
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0 -Force

# 3. Configure Windows Firewall for RDP (TCP & UDP)
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
New-NetFirewallRule -DisplayName "Allow RDP 3389 TCP" -Direction Inbound -LocalPort 3389 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Allow RDP 3389 UDP" -Direction Inbound -LocalPort 3389 -Protocol UDP -Action Allow -ErrorAction SilentlyContinue

# 4. Ultra-Low Latency & 60 FPS RDP Optimization
# Unlock 60 FPS remote desktop rendering (default Windows caps at 30 FPS)
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations' -Name "DWMFRAMEINTERVAL" -Value 15 -Type DWord -Force

# Enable RDP hardware/software acceleration codecs and enable UDP transport
if (-not (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services')) {
    New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Force
}
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name "fEnableRemoteFXAdvancedRemoteFX" -Value 1 -Type DWord -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name "SelectTransport" -Value 0 -Type DWord -Force

# Disable Nagle algorithm on all network interfaces (TCP NoDelay for instant mouse/key response)
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $_.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}

# 5. Set High Performance Power Plan (prevents any CPU throttling or sleep)
powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

# 6. Install Chocolatey Package Manager
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# 7. Refresh Path
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 8. Install Chrome, VS Code, and Git silently in background
choco install -y googlechrome vscode git --no-progress
</powershell>
