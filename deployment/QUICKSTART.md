# Quick Start - Deploy in 5 Minutes

Fastest path to get Arke Upload Server running on AWS EC2.

## Prerequisites

✅ AWS CLI installed and configured (`aws configure`)
✅ `jq` installed (`brew install jq` on macOS)
✅ Valid AWS credentials with EC2 permissions

## Deploy

```bash
cd deployment/scripts

# 1. Create EC2 instance (2 minutes)
./01-create-ec2.sh

# 2. Wait for "Deployment Complete" message, then deploy application (5-10 minutes)
./02-deploy-server.sh

# 3. Check status
./check-status.sh
```

## Access

Your server will be available at:

```
http://YOUR_PUBLIC_IP/api/v1/health
```

The public IP is displayed after step 1 and saved in `deployment/instance-info.json`.

## Test Upload

```bash
# Get your public IP
PUBLIC_IP=$(jq -r '.publicIp' deployment/instance-info.json)

# Initialize session
curl -X POST "http://${PUBLIC_IP}/api/v1/upload/init" \
  -H "Content-Type: application/json" \
  -d '{"uploader": "Test User"}'

# Upload file (use session ID from above)
curl -X POST "http://${PUBLIC_IP}/api/v1/upload/SESSION_ID/files" \
  -F "files=@myfile.jpg"

# Trigger processing
curl -X POST "http://${PUBLIC_IP}/api/v1/upload/SESSION_ID/process"

# Check status
curl "http://${PUBLIC_IP}/api/v1/upload/SESSION_ID/status"
```

## Next Steps

- **Set up domain**: Point your DNS to the public IP
- **Add SSL**: Run `sudo certbot --nginx -d yourdomain.com` on the instance
- **Monitor**: Check logs with `sudo journalctl -u arke-upload -f`

## Cleanup

To destroy everything:

```bash
./99-cleanup.sh
```

## Need Help?

See full documentation: [deployment/README.md](./README.md)
