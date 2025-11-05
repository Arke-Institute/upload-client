#!/bin/bash

################################################################################
# Check Status of Deployed Arke Upload Server
#
# This script checks the health and status of the deployed server
#
# Usage: ./check-status.sh
################################################################################

set -e

INFO_FILE="deployment/instance-info.json"

# Check if instance info exists
if [ ! -f "$INFO_FILE" ]; then
  echo "❌ Error: Instance info file not found: $INFO_FILE"
  echo "   No deployment found."
  exit 1
fi

# Load instance info
INSTANCE_ID=$(jq -r '.instanceId' "$INFO_FILE")
PUBLIC_IP=$(jq -r '.publicIp' "$INFO_FILE")
KEY_NAME=$(jq -r '.keyName' "$INFO_FILE")
REGION=$(jq -r '.region' "$INFO_FILE")
KEY_FILE="${KEY_NAME}.pem"

echo "=================================================="
echo "Arke Upload Server - Status Check"
echo "=================================================="
echo ""

# Check EC2 instance status
echo "EC2 Instance Status:"
INSTANCE_STATE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)

echo "  Instance ID: $INSTANCE_ID"
echo "  State:       $INSTANCE_STATE"
echo "  Public IP:   $PUBLIC_IP"
echo ""

if [ "$INSTANCE_STATE" != "running" ]; then
  echo "❌ Instance is not running"
  exit 1
fi

# Check HTTP endpoint
echo "HTTP Endpoint Check:"
if curl -sf -o /dev/null -w "%{http_code}" "http://${PUBLIC_IP}/api/v1/health" | grep -q "200"; then
  echo "  ✓ HTTP endpoint responding"
  echo ""
  echo "Server Health:"
  curl -s "http://${PUBLIC_IP}/api/v1/health" | jq .
else
  echo "  ❌ HTTP endpoint not responding"
  echo ""
  echo "Checking service via SSH..."
  if [ -f "$KEY_FILE" ]; then
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ec2-user@"$PUBLIC_IP" "sudo systemctl status arke-upload.service --no-pager | head -20"
  else
    echo "  ❌ SSH key not found: $KEY_FILE"
  fi
  exit 1
fi

echo ""
echo "SSH Access:"
echo "  ssh -i ${KEY_FILE} ec2-user@${PUBLIC_IP}"
echo ""
echo "View Logs:"
echo "  ssh -i ${KEY_FILE} ec2-user@${PUBLIC_IP} 'sudo journalctl -u arke-upload -f'"
echo ""
echo "=================================================="
