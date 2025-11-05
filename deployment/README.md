# Arke Upload Server - Deployment Guide

Complete guide for deploying the Arke Upload Server to AWS EC2.

## Overview

The deployment uses a **t3.small EC2 instance** running **Amazon Linux 2023** with:
- Docker containerized application
- Nginx reverse proxy (port 80 → 3000)
- Systemd service for auto-restart
- 30 GB GP3 storage
- Security group with HTTP/HTTPS/SSH access

## Prerequisites

### Local Machine Requirements

1. **AWS CLI** installed and configured
   ```bash
   # Install AWS CLI (macOS)
   brew install awscli

   # Configure credentials
   aws configure
   ```

2. **Required tools**: `jq`, `curl`, `ssh`
   ```bash
   # macOS
   brew install jq
   ```

3. **AWS IAM Permissions**
   - EC2: Full access (launch, terminate, describe instances)
   - VPC: Describe VPCs, security groups
   - EC2 Key Pairs: Create, describe, delete

### AWS Account Requirements

- Valid AWS account with billing enabled
- Default VPC in your chosen region
- No conflicting security groups named `arke-upload-server-sg`

## Quick Start

### 1. Create EC2 Instance

```bash
cd deployment/scripts
chmod +x *.sh

# Create instance (uses your current IP for SSH access)
./01-create-ec2.sh

# Or specify custom key name and IP
./01-create-ec2.sh my-key-name 203.0.113.0/32
```

**Output:**
- EC2 instance ID and public IP
- SSH key file (.pem) saved locally
- Instance info saved to `deployment/instance-info.json`

**Wait 2-3 minutes** for the instance to fully initialize.

### 2. Deploy Application

```bash
# Deploy with default worker URL
./02-deploy-server.sh

# Or specify custom worker URL
./02-deploy-server.sh https://your-worker-url.com
```

**What this does:**
1. Installs Docker, Git, Nginx on EC2
2. Clones the repository
3. Builds Docker image
4. Creates systemd service
5. Configures Nginx reverse proxy
6. Starts the server

**Duration:** 5-10 minutes (Docker build takes longest)

### 3. Verify Deployment

```bash
# Check status
./check-status.sh

# Or manually
curl http://YOUR_PUBLIC_IP/api/v1/health
```

Expected response:
```json
{
  "status": "healthy",
  "version": "2.0.0",
  "uptime": 42,
  "storage": { ... },
  "worker": {
    "url": "https://ingest.arke.institute",
    "reachable": true
  },
  "sessions": {
    "active": 0
  }
}
```

## Architecture

### EC2 Instance

**Type:** t3.small (ARM64)
- 2 vCPU
- 2 GB RAM
- 30 GB GP3 SSD
- ~$15/month

**OS:** Amazon Linux 2023
- Modern, AWS-optimized
- Automatic security updates
- Docker in official repos

### Network Configuration

**Security Group:** `arke-upload-server-sg`

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP | SSH access |
| 80 | TCP | 0.0.0.0/0 | HTTP (Nginx → Docker) |
| 443 | TCP | 0.0.0.0/0 | HTTPS (future SSL) |

**Note:** Application runs on port 3000 inside Docker, Nginx proxies port 80 to 3000.

### Directory Structure

On EC2 instance:

```
/home/ec2-user/upload-server/     # Git repository
/data/arke-uploads/                # Persistent upload storage
/etc/systemd/system/               # Service configuration
  └── arke-upload.service
/etc/nginx/conf.d/                 # Nginx configuration
  └── arke-upload.conf
```

### Service Management

**Systemd Service:** `arke-upload.service`

```bash
# View status
sudo systemctl status arke-upload

# View logs
sudo journalctl -u arke-upload -f

# Restart service
sudo systemctl restart arke-upload

# Stop service
sudo systemctl stop arke-upload
```

**Docker Container:** `arke-upload`

```bash
# View container logs
sudo docker logs arke-upload -f

# Restart container
sudo docker restart arke-upload

# Check container status
sudo docker ps -a | grep arke-upload
```

## Deployment Scripts

### 01-create-ec2.sh

Creates EC2 instance with all necessary AWS resources.

**Usage:**
```bash
./01-create-ec2.sh [key-name] [your-ip]
```

**Arguments:**
- `key-name` (optional): SSH key pair name (default: `arke-upload-key`)
- `your-ip` (optional): Your IP for SSH access (default: auto-detected)

**Creates:**
- EC2 instance (t3.small)
- Security group
- SSH key pair (if doesn't exist)
- Saves instance info to `deployment/instance-info.json`

**Example:**
```bash
# Use defaults
./01-create-ec2.sh

# Custom key and IP
./01-create-ec2.sh my-company-key 203.0.113.0/32
```

### 02-deploy-server.sh

Deploys application to EC2 instance.

**Usage:**
```bash
./02-deploy-server.sh [worker-url]
```

**Arguments:**
- `worker-url` (optional): Worker API URL (default: `https://ingest.arke.institute`)

**Steps:**
1. Connects via SSH
2. Installs system dependencies
3. Clones repository
4. Builds Docker image
5. Configures systemd service
6. Sets up Nginx
7. Starts server

**Example:**
```bash
# Use default worker URL
./02-deploy-server.sh

# Custom worker URL
./02-deploy-server.sh https://staging.arke.institute
```

### check-status.sh

Checks deployment health.

**Usage:**
```bash
./check-status.sh
```

**Checks:**
- EC2 instance state
- HTTP endpoint health
- Service status

### 99-cleanup.sh

Destroys all AWS resources.

**Usage:**
```bash
# Keep SSH key
./99-cleanup.sh

# Delete SSH key too
./99-cleanup.sh --delete-key
```

**⚠️ WARNING:** This permanently deletes:
- EC2 instance
- All data on instance
- Security group
- Optionally: SSH key pair

## SSH Access

### Connect to Instance

```bash
# From instance-info.json
ssh -i arke-upload-key.pem ec2-user@YOUR_PUBLIC_IP

# View logs
sudo journalctl -u arke-upload -f

# Check service status
sudo systemctl status arke-upload

# View Docker logs
sudo docker logs arke-upload -f
```

### Troubleshooting SSH

**Connection refused:**
- Instance still initializing (wait 2-3 minutes)
- Check security group allows your current IP
- Verify instance is running: `aws ec2 describe-instances --instance-ids INSTANCE_ID`

**Permission denied:**
- Check key file permissions: `chmod 400 arke-upload-key.pem`
- Verify using correct key name
- Check key matches instance

## Updates and Maintenance

### Update Application Code

```bash
# SSH to instance
ssh -i arke-upload-key.pem ec2-user@YOUR_PUBLIC_IP

# Update repository
cd ~/upload-server
git pull origin feature/server-api

# Rebuild Docker image
sudo docker build -t arke-upload-server:latest .

# Restart service (systemd will use new image)
sudo systemctl restart arke-upload
```

### Update Worker URL

```bash
# Edit service file
sudo nano /etc/systemd/system/arke-upload.service

# Change WORKER_URL environment variable
# Then reload and restart
sudo systemctl daemon-reload
sudo systemctl restart arke-upload
```

### View Logs

```bash
# Service logs (systemd)
sudo journalctl -u arke-upload -f

# Last 100 lines
sudo journalctl -u arke-upload -n 100

# Docker container logs
sudo docker logs arke-upload -f

# Nginx access logs
sudo tail -f /var/log/nginx/access.log

# Nginx error logs
sudo tail -f /var/log/nginx/error.log
```

### Monitor Disk Usage

```bash
# Check disk space
df -h

# Check upload directory
du -sh /data/arke-uploads

# Clean up old sessions (manual)
sudo find /data/arke-uploads -type d -mtime +1 -exec rm -rf {} +
```

## Security Recommendations

### Production Checklist

- [ ] Change SSH port from 22 to custom port
- [ ] Restrict SSH to VPN or specific IPs only
- [ ] Set up SSL certificate (Let's Encrypt)
- [ ] Enable CloudWatch monitoring
- [ ] Set up automated backups
- [ ] Configure log rotation
- [ ] Enable AWS CloudTrail
- [ ] Set up billing alerts
- [ ] Review security group rules
- [ ] Enable automatic security updates

### SSL/HTTPS Setup

After initial deployment, set up Let's Encrypt:

```bash
# SSH to instance
ssh -i arke-upload-key.pem ec2-user@YOUR_PUBLIC_IP

# Install certbot
sudo dnf install -y certbot python3-certbot-nginx

# Get certificate (requires domain pointing to instance)
sudo certbot --nginx -d yourdomain.com

# Auto-renewal is set up automatically
sudo systemctl status certbot-renew.timer
```

### Firewall (Optional)

Amazon Linux 2023 uses `firewalld`:

```bash
# Check firewall status
sudo firewall-cmd --state

# Allow HTTP/HTTPS
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

## Cost Estimation

**Monthly Costs (us-east-1):**

| Resource | Cost |
|----------|------|
| t3.small instance | ~$15/month |
| 30 GB GP3 storage | ~$2.40/month |
| Data transfer (100 GB OUT) | ~$9/month |
| **Total** | **~$26/month** |

**Cost Optimization:**
- Use Reserved Instances (1-year): Save 30-40%
- Use Savings Plans: Flexible commitment
- Monitor data transfer costs
- Set up billing alerts

## Troubleshooting

### Server Not Starting

```bash
# Check service status
sudo systemctl status arke-upload

# View recent logs
sudo journalctl -u arke-upload -n 50

# Check if Docker is running
sudo systemctl status docker

# Manually run container to see errors
sudo docker run --rm -it arke-upload-server:latest
```

### Health Check Failing

```bash
# Check from instance
curl http://localhost:3000/api/v1/health

# Check Nginx configuration
sudo nginx -t

# Check if container is running
sudo docker ps | grep arke-upload

# View container logs
sudo docker logs arke-upload
```

### Out of Disk Space

```bash
# Check disk usage
df -h

# Clean up Docker images
sudo docker system prune -a

# Clean up old uploads
sudo find /data/arke-uploads -type d -mtime +1 -exec rm -rf {} +

# Check systemd logs size
sudo journalctl --disk-usage
sudo journalctl --vacuum-size=100M
```

### Worker Connection Failed

```bash
# Test worker connectivity from instance
curl https://ingest.arke.institute/

# Check service environment
sudo systemctl cat arke-upload | grep WORKER_URL

# Update worker URL if needed
sudo nano /etc/systemd/system/arke-upload.service
sudo systemctl daemon-reload
sudo systemctl restart arke-upload
```

## Advanced Configuration

### Custom Domain

1. **Point domain to instance IP** (in your DNS provider)
   ```
   A record: upload.yourdomain.com → YOUR_PUBLIC_IP
   ```

2. **Update Nginx configuration**
   ```bash
   sudo nano /etc/nginx/conf.d/arke-upload.conf
   # Change: server_name _;
   # To:     server_name upload.yourdomain.com;
   sudo nginx -t
   sudo systemctl restart nginx
   ```

3. **Set up SSL** (see SSL/HTTPS Setup above)

### Increase Upload Limits

Edit Nginx configuration:

```bash
sudo nano /etc/nginx/conf.d/arke-upload.conf

# Increase these values:
client_max_body_size 10G;
client_body_timeout 600s;
proxy_connect_timeout 600s;
proxy_send_timeout 600s;
proxy_read_timeout 600s;

sudo nginx -t
sudo systemctl restart nginx
```

### CloudWatch Integration

```bash
# Install CloudWatch agent
sudo dnf install -y amazon-cloudwatch-agent

# Configure metrics
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard

# Start agent
sudo systemctl enable amazon-cloudwatch-agent
sudo systemctl start amazon-cloudwatch-agent
```

## Support

### Useful AWS CLI Commands

```bash
# List instances
aws ec2 describe-instances --filters "Name=tag:Project,Values=arke-upload"

# Get instance public IP
aws ec2 describe-instances --instance-ids INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress'

# Stop instance (saves costs but keeps data)
aws ec2 stop-instances --instance-ids INSTANCE_ID

# Start instance
aws ec2 start-instances --instance-ids INSTANCE_ID

# Get new IP after start
aws ec2 describe-instances --instance-ids INSTANCE_ID
```

### Logs Location

**On EC2 instance:**
- Service logs: `sudo journalctl -u arke-upload`
- Docker logs: `sudo docker logs arke-upload`
- Nginx access: `/var/log/nginx/access.log`
- Nginx error: `/var/log/nginx/error.log`

### Getting Help

1. Check service status: `./deployment/scripts/check-status.sh`
2. View logs: `ssh -i KEY.pem ec2-user@IP 'sudo journalctl -u arke-upload -n 100'`
3. Review this documentation
4. Check AWS CloudWatch console for metrics
