#!/usr/bin/env bash
# ==============================================================================
# user_data.sh - Ubuntu 24.04 LTS Workstation Cloud-Init Bootstrap Script
# ==============================================================================
set -euo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=========================================================="
echo " Starting Workstation Bootstrap: $(date -u)"
echo "=========================================================="

# ------------------------------------------------------------------------------
# 1. SWAP CONFIGURATION (4 GB swap file on gp3 root volume)
# ------------------------------------------------------------------------------
echo "[-] Configuring 4 GB swapfile..."
if [ ! -f /swapfile ]; then
    fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Reduce swappiness to 10 for responsive desktop interactivity
    sysctl vm.swappiness=10
    echo 'vm.swappiness=10' > /etc/sysctl.d/99-workstation.conf
fi

# ------------------------------------------------------------------------------
# 2. SYSTEM UPDATES & HARDENING
# ------------------------------------------------------------------------------
echo "[-] Performing unattended OS package updates and hardening..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    wget \
    gnupg \
    software-properties-common \
    lsb-release \
    unzip \
    tar \
    git \
    zsh \
    tmux \
    htop \
    jq \
    bc \
    tree \
    ufw \
    unattended-upgrades \
    update-notifier-common \
    build-essential

# Enable automated security updates
dpkg-reconfigure -f noninteractive unattended-upgrades

# Host firewall (UFW) configuration
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 8443/tcp comment 'Amazon DCV Web/TCP'
ufw allow 8443/udp comment 'Amazon DCV QUIC'
ufw --force enable

# Enforce SSH hardening: disable passwords & root login
sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i -E 's/^#?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh || systemctl restart sshd || true

# ------------------------------------------------------------------------------
# 3. WORKSTATION USER PROVISIONING
# ------------------------------------------------------------------------------
WORKSTATION_USER="${workstation_user}"
echo "[-] Provisioning desktop user: $WORKSTATION_USER..."

if ! id "$WORKSTATION_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$WORKSTATION_USER"
    usermod -aG sudo "$WORKSTATION_USER"
    echo "$WORKSTATION_USER:${dcv_password}" | chpasswd
    echo "$WORKSTATION_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$WORKSTATION_USER"
    chmod 0440 "/etc/sudoers.d/$WORKSTATION_USER"

    # Propagate authorized SSH keys from default cloud-init user
    mkdir -p "/home/$WORKSTATION_USER/.ssh"
    if [ -f /home/ubuntu/.ssh/authorized_keys ]; then
        cp /home/ubuntu/.ssh/authorized_keys "/home/$WORKSTATION_USER/.ssh/authorized_keys"
    fi
    chown -R "$WORKSTATION_USER:$WORKSTATION_USER" "/home/$WORKSTATION_USER/.ssh"
    chmod 700 "/home/$WORKSTATION_USER/.ssh"
    chmod 600 "/home/$WORKSTATION_USER/.ssh/authorized_keys" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 4. LIGHTWEIGHT XFCE DESKTOP & PERFORMANCE TUNING
# ------------------------------------------------------------------------------
echo "[-] Installing XFCE Desktop Environment..."
apt-get install -y xfce4 xfce4-goodies dbus-x11 xorg

# Disable XFCE window compositing: eliminate input latency and rendering lag over remote streaming
mkdir -p "/home/$WORKSTATION_USER/.config/xfce4/xfconf/xfce-perchannel-xml"
cat << 'EOF' > "/home/$WORKSTATION_USER/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
EOF
chown -R "$WORKSTATION_USER:$WORKSTATION_USER" "/home/$WORKSTATION_USER/.config"

# ------------------------------------------------------------------------------
# 5. AMAZON DCV SERVER (Free on Amazon EC2)
# ------------------------------------------------------------------------------
echo "[-] Installing Amazon DCV Server & QUIC UDP components..."
cd /tmp
wget -q https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY
gpg --import NICE-GPG-KEY 2>/dev/null || true
rm -f NICE-GPG-KEY

wget -q https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-ubuntu2404-x86_64.tgz
tar -xzf nice-dcv-ubuntu2404-x86_64.tgz
cd nice-dcv-*-ubuntu2404-x86_64
apt-get install -y ./nice-dcv-server_*.deb ./nice-dcv-web-viewer_*.deb ./nice-xdcv_*.deb
cd /tmp
rm -rf /tmp/nice-dcv*

# Assign permissions
usermod -aG video dcv || true
usermod -aG dcv "$WORKSTATION_USER" || true

# Configure DCV Server (/etc/dcv/dcv.conf)
cat << EOF > /etc/dcv/dcv.conf
[license]
# On Amazon EC2, Amazon DCV is free of charge and requires no external license server.

[session-management]
create-session = true

[session-management/defaults]
default-session-type = "virtual"

[session-management/automatic-console-session]
owner = "$WORKSTATION_USER"
storage-root = "/home/$WORKSTATION_USER"

[display]
# Responsive remote desktop video streaming optimizations
target-fps = 60
quality = 85

[connectivity]
web-port = 8443
web-listen-endpoints = ["0.0.0.0:8443"]
enable-quic = true
EOF

systemctl enable dcvserver
systemctl restart dcvserver

# Automatically create a persistent virtual session for the user
sleep 3
dcv create-session --type=virtual --owner="$WORKSTATION_USER" --user="$WORKSTATION_USER" workstation-session || true

# ------------------------------------------------------------------------------
# 6. DEVELOPER ENVIRONMENT & PRODUCTIVITY TOOLS
# ------------------------------------------------------------------------------
echo "[-] Installing developer toolchain (Chrome, Firefox, VS Code, Docker, Python, AWS CLI, Terraform)..."

# Google Chrome
wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y /tmp/chrome.deb || apt-get -f install -y
rm -f /tmp/chrome.deb

# Firefox
apt-get install -y firefox

# Microsoft Visual Studio Code
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
apt-get update -y
apt-get install -y code

# Docker CE
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker "$WORKSTATION_USER"

# Python 3, venv, and build headers
apt-get install -y python3 python3-pip python3-venv python3-dev

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update
rm -rf /tmp/aws /tmp/awscliv2.zip

# HashiCorp Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list
apt-get update -y
apt-get install -y terraform

# ------------------------------------------------------------------------------
# 7. INACTIVITY AUTO-STOP SYSTEMD SERVICE (Credit Saver)
# ------------------------------------------------------------------------------
echo "[-] Setting up 30-minute idle auto-stop service..."

cat << 'EOF' > /usr/local/bin/idle-shutdown-check.sh
#!/usr/bin/env bash
set -u

# Check 1: Active DCV network connections on port 8443
ACTIVE_DCV_CONNS=$(ss -nt '( sport = :8443 )' | grep -v State | wc -l)

# Check 2: Active SSH connections on port 22
ACTIVE_SSH_CONNS=$(ss -nt '( sport = :22 )' | grep -v State | wc -l)

# Check 3: 15-minute system load average
LOAD_15M=$(awk '{print $3}' /proc/loadavg)

# Idle condition: 0 DCV connections, 0 SSH sessions, and load average < 0.20
if [ "$ACTIVE_DCV_CONNS" -eq 0 ] && [ "$ACTIVE_SSH_CONNS" -eq 0 ] && (( $(echo "$LOAD_15M < 0.20" | bc -l) )); then
    COUNT_FILE="/tmp/idle_shutdown_counter"
    COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$COUNT_FILE"
    logger -t idle-shutdown "Workstation is inactive. Idle interval counter: $COUNT/6 (5m per count)."

    # 6 checks * 5 minutes = 30 consecutive minutes of idle activity
    if [ "$COUNT" -ge 6 ]; then
        logger -t idle-shutdown "Workstation inactive for 30 consecutive minutes. Stopping EC2 instance to preserve credit balance."
        rm -f "$COUNT_FILE"

        # Obtain IMDSv2 token
        TOKEN=$(curl -s -S -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || echo "")
        if [ -n "$TOKEN" ]; then
            INSTANCE_ID=$(curl -s -S -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/instance-id" 2>/dev/null || echo "")
            REGION=$(curl -s -S -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/placement/region" 2>/dev/null || echo "")

            if [ -n "$INSTANCE_ID" ] && [ -n "$REGION" ]; then
                aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION" || /sbin/shutdown -h now
                exit 0
            fi
        fi

        # Fallback to standard ACPI shutdown (stops instance on AWS)
        /sbin/shutdown -h now
    fi
else
    # Activity detected, reset counter
    rm -f /tmp/idle_shutdown_counter
fi
EOF

chmod +x /usr/local/bin/idle-shutdown-check.sh

# Install systemd service and timer
cat << 'EOF' > /etc/systemd/system/idle-shutdown.service
[Unit]
Description=Workstation Idle Auto-Stop Checker
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/idle-shutdown-check.sh
EOF

cat << 'EOF' > /etc/systemd/system/idle-shutdown.timer
[Unit]
Description=Trigger Workstation Idle Checker Every 5 Minutes

[Timer]
OnBootSec=10min
OnUnitActiveSec=5min
Unit=idle-shutdown.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now idle-shutdown.timer

echo "=========================================================="
echo " Workstation Bootstrap Completed Successfully: $(date -u)"
echo "=========================================================="
touch /var/log/bootstrap-complete.txt
