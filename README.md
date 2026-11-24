# Personal Remote Desktop Workstation on AWS (Infrastructure-as-Code)

A production-grade, cost-optimized, and security-hardened Infrastructure-as-Code (Terraform) project to provision a personal remote workstation on AWS. Built specifically for developers working from West Africa (Nigeria) and optimized for low latency, smooth GUI interactivity, and minimal burn against AWS promotional credits (~$200 for 6 months).

---

## Architecture Overview

* **Compute:** Windows Server 2022 Base on `m7i-flex.large` (2 vCPU, 8 GiB RAM, 4th Gen Intel Xeon Scalable). Fallback to `c7i-flex.large` or `t3.small`.
* **Region:** `eu-west-1` (Ireland) — Lowest latency (~75–95ms) to Nigeria via major Atlantic subsea cables without requiring account opt-in.
* **Remote Display:** Native Microsoft Remote Desktop Protocol (RDP) on port 3389 (TCP & UDP acceleration). Native Windows-to-Windows integration with seamless DPI scaling, zero letterboxing, clipboard sync, and pixel-perfect mouse responsiveness.
* **Storage:** 50 GB encrypted `gp3` root EBS volume (3000 IOPS, 125 MB/s).
* **Pre-installed Software:** Google Chrome, Visual Studio Code, Git, and Chocolatey package manager.
* **Security:**
  * Least-privilege IAM instance role with AWS Systems Manager (SSM) Session Manager.
  * Security group restricts remote desktop (8443 TCP/UDP) and SSH (22) exclusively to your `/32` IP address.
  * Key-based SSH only (password authentication and root login disabled).
  * Enforced IMDSv2 and automatic unattended security updates.
  * UFW host firewall enabled.
* **Cost Controls:**
  * Systemd timer on the instance monitors active DCV connections and CPU load; automatically triggers self-shutdown after 30 minutes of idle time.
  * Dedicated CloudWatch Metric Alarm triggers EC2 Stop Action as an infrastructure fallback.
  * AWS Budgets with alerts at 50%, 80%, and 100% forecasted spend.
  * Ephemeral dynamic public IP (avoids unattached Elastic IP charges).

---

## 1. Prerequisites

1. **Terraform CLI**: Version `>= 1.5.0` installed locally.
2. **AWS CLI v2**: Installed and configured (`aws configure`) with credentials for an IAM user or role with permissions for EC2, IAM, CloudWatch, and Budgets.
3. **SSH Key Pair**: An existing or newly generated key (e.g. `~/.ssh/id_ed25519`).
4. **AWS DCV Client** (Optional but recommended): Download the free native client from [AWS DCV Client Downloads](https://docs.aws.amazon.com/dcv/latest/userguide/client.html) for Windows, macOS, or Linux. Alternatively, any modern web browser (Chrome, Firefox, Edge, Safari) can connect directly.

---

## 2. Pre-Flight Checks: Verifying Free-Tier & Regional Eligibility

AWS accounts created after July 15, 2025 operate on a promotional credit model (~$200 across 6 months).

### Check Regional Instance Type Availability
Run the following command to verify that `m7i-flex.large` is available in your availability zones:
```bash
aws ec2 describe-instance-type-offerings \
  --region eu-west-1 \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=m7i-flex.large,c7i-flex.large,t3.small" \
  --query "InstanceTypeOfferings[*].[InstanceType,Location]" \
  --output table
```

### Check General Free-Tier Instance Metadata
```bash
aws ec2 describe-instance-types \
  --region eu-west-1 \
  --filters "Name=free-tier-eligible,Values=true" \
  --query "InstanceTypes[*].InstanceType" \
  --output text
```

---

## 3. Configuration & Variable Setup

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Determine your current public IPv4 address:
   ```bash
   curl -s https://checkip.amazonaws.com
   ```

3. Edit `terraform.tfvars` and set the required variables:
   ```hcl
   aws_region                = "eu-west-1"
   instance_type             = "m7i-flex.large"
   allowed_ip                = "102.89.23.45/32"    # Replace with your actual IP from step 2
   ssh_public_key            = "ssh-ed25519 AAAAC3... your_email@example.com"
   workstation_user          = "dcvuser"
   dcv_password              = "YourSuperSecurePassword2026!"
   budget_notification_email = "you@example.com"
   monthly_budget_usd        = 35.0
   ```

> **Warning:** `terraform.tfvars` is git-ignored. Never commit your secrets or passwords to Git.

---

## 4. Deployment & Lifecycle Commands

### Step 1: Initialize Terraform
```bash
terraform init
```

### Step 2: Validate Configuration
```bash
terraform validate
```

### Step 3: Review Execution Plan
```bash
terraform plan
```

### Step 4: Provision Workstation
```bash
terraform apply
```
*Note: Provisioning takes ~3 to 5 minutes as cloud-init packages and installs XFCE, DCV, Chrome, VS Code, and Docker.*

---

## 5. Connecting to the Remote Desktop

### Option A: Web Browser (Instant, No Software Needed)
1. In your local browser, visit the output URL:
   ```text
   https://<PUBLIC_IP>:8443
   ```
2. Accept the self-signed TLS certificate warning (`Advanced -> Proceed`).
3. Enter credentials:
   * **Username:** `dcvuser` (or value of `workstation_user`)
   * **Password:** The password configured in `dcv_password`.

### Option B: Amazon DCV Native Client (Lowest Latency & 60 FPS)
1. Open the **Amazon DCV Client**.
2. Target: `<PUBLIC_IP>:8443`.
3. Provide your credentials.
4. *Tip:* DCV Client will use QUIC (UDP 8443) for dynamic frame-rate adaptation over high-latency transatlantic links.

### Option C: Zero Open Inbound Ports (Tunnel via AWS Systems Manager)
If your public IP changes frequently or you want 100% security with 0 open ports in your AWS Security Group:
```bash
# 1. Start an SSM port-forwarding session:
aws ssm start-session \
  --target $(terraform output -raw instance_id) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8443"],"localPortNumber":["8443"]}' \
  --region eu-west-1

# 2. In your local browser or DCV client, connect to:
https://localhost:8443
```

---

## 6. Daily Operations: Stopping and Starting

To keep your credit burn under ~$35/month, stop the instance when not actively working.

### Stop the Workstation
```bash
# Via AWS CLI:
aws ec2 stop-instances --instance-ids $(terraform output -raw instance_id) --region eu-west-1

# Or from inside the workstation terminal:
sudo shutdown -h now
```
*(The workstation also auto-stops itself after 30 minutes of idle time).*

### Start the Workstation
```bash
# Start instance:
aws ec2 start-instances --instance-ids $(terraform output -raw instance_id) --region eu-west-1

# Retrieve the new ephemeral public IP:
aws ec2 describe-instances \
  --instance-ids $(terraform output -raw instance_id) \
  --region eu-west-1 \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text
```

### Teardown / Destroy
To terminate the instance and delete all associated storage and alarms:
```bash
terraform destroy
```

---

## 7. Post-Launch Verification Checklist

Once logged into your remote desktop or SSH session:

- [ ] **Bootstrap Completion:** Run `cat /var/log/bootstrap-complete.txt` (or inspect `/var/log/user-data.log`).
- [ ] **Swap Memory:** Run `swapon --show` — confirm 4 GB active swap file.
- [ ] **EBS Encryption & Size:** Run `lsblk` — confirm 30 GB root volume.
- [ ] **DCV Session Status:** Run `sudo dcv list-sessions` — confirms `workstation-session` is active.
- [ ] **XFCE Compositor:** Run `xfconf-query -c xfwm4 -p /general/use_compositing` — must return `false`.
- [ ] **Docker:** Run `docker run --rm hello-world` — executes without `sudo`.
- [ ] **Toolchain:** Verify installed versions:
  * `code --version`
  * `python3 --version`
  * `google-chrome --version`
  * `firefox --version`
  * `terraform -v`
  * `aws --version`
- [ ] **Idle Auto-Stop Timer:** Check systemd timer with `systemctl list-timers idle-shutdown.timer`.

---

## 8. Latency & Lag Troubleshooting (West Africa to Europe)

1. **Verify UDP / QUIC Streaming:**
   * In the Amazon DCV Client, click **Connection -> Connection Info**.
   * Confirm the protocol is **QUIC (UDP)**. If it says **TCP/WebSocket**, your local router, mobile hotspot, or ISP is blocking or throttling UDP port 8443. QUIC avoids TCP head-of-line blocking over packet-loss-prone links.
2. **Display Resolution & Quality:**
   * Avoid 4K streaming over mobile cellular networks. In DCV Settings, set display resolution to `1920x1080` and adjust quality to `Medium` or `80%`.
3. **Verify Compositor is Disabled:**
   * Compositing introduces double-buffering latency. Verify it remains disabled in `xfwm4.xml`.
4. **Dynamic IP Mismatch:**
   * If your home ISP changes your public IP, AWS Security Group will drop packets. Re-check your IP via `curl https://checkip.amazonaws.com` and run `terraform apply` with the updated `allowed_ip`.

---

## 9. Cost Traps & Credit Burn Watchlist

| Service Component | Pricing Rate | Monthly Estimate (Stopped vs Active) | Strategy to Avoid Surprises |
| :--- | :--- | :--- | :--- |
| **Compute (`m7i-flex.large`)** | ~$0.0864 / hour | $0 when stopped; ~$10.37/mo @ 4 hrs/day | Systemd idle daemon + CloudWatch alarm stop instance after 30m idle. |
| **Public IPv4 Address** | $0.005 / hour | $0 when stopped; ~$0.60/mo @ 4 hrs/day | No Elastic IP used. (Alternative: SSM port-forwarding with private IP). |
| **EBS Root Volume (`gp3`)** | $0.08 / GB-month | ~$2.40 / month (charged even when stopped) | Kept volume at 30 GB minimum needed for OS + tools. |
| **Internet Data Transfer** | First 100 GB/mo free | $0 (DCV uses ~50–150 MB/hour; ~18 GB/mo) | Falls well within AWS free 100 GB egress tier. |
| **Total Estimated Burn** | — | **~$13.37 / month** | **Total 6-month burn: ~$80** (Leaves >$120 buffer of your $200 credit). |

---

## 10. Architectural Critiques & Better Alternatives

1. **Zero-Public-IP Architecture (Highest Security & $0 IPv4 Fees):**
   * Instead of assigning a public IP to EC2, place it in a private subnet and connect exclusively via **AWS SSM Session Manager Port Forwarding**. This completely eliminates the $0.005/hr IPv4 charge and eliminates all port scanning risk.
2. **EC2 Spot Instances (60–70% Discount):**
   * If you commit code regularly to GitHub/GitLab, running `m7i-flex.large` as an EC2 Spot instance reduces compute cost to ~$0.026/hour. This allows 3x more working hours for the same credit budget.
3. **AWS WorkSpaces Comparison:**
   * AWS WorkSpaces charges a fixed base monthly charge ($7.25–$10.00/mo) plus hourly fees, offering less root flexibility and older base AMIs. The self-hosted DCV on EC2 approach gives modern Ubuntu 24.04 LTS, full Docker/kernel control, and lower total cost.
