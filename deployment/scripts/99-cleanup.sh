#!/bin/bash

################################################################################
# Cleanup EC2 Instance and Resources
#
# This script terminates the EC2 instance and cleans up all AWS resources:
# - Terminates EC2 instance
# - Deletes security group
# - Optionally deletes SSH key pair
#
# WARNING: This is destructive! All data on the instance will be lost.
#
# Usage: ./99-cleanup.sh [--delete-key]
################################################################################

set -e

INFO_FILE="deployment/instance-info.json"
DELETE_KEY=false

if [ "$1" == "--delete-key" ]; then
  DELETE_KEY=true
fi

# Check if instance info exists
if [ ! -f "$INFO_FILE" ]; then
  echo "❌ Error: Instance info file not found: $INFO_FILE"
  echo "   No deployment found."
  exit 1
fi

# Load instance info
INSTANCE_ID=$(jq -r '.instanceId' "$INFO_FILE")
SG_ID=$(jq -r '.securityGroupId' "$INFO_FILE")
KEY_NAME=$(jq -r '.keyName' "$INFO_FILE")
REGION=$(jq -r '.region' "$INFO_FILE")
KEY_FILE="${KEY_NAME}.pem"

echo "=================================================="
echo "Arke Upload Server - Cleanup"
echo "=================================================="
echo ""
echo "⚠️  WARNING: This will delete the following resources:"
echo ""
echo "  Instance ID:       $INSTANCE_ID"
echo "  Security Group:    $SG_ID"
if [ "$DELETE_KEY" == "true" ]; then
  echo "  SSH Key Pair:      $KEY_NAME (and local .pem file)"
else
  echo "  SSH Key Pair:      $KEY_NAME (will be kept)"
fi
echo ""
echo "All data on the instance will be permanently lost!"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

# Terminate instance
echo "[1/4] Terminating EC2 instance..."
aws ec2 terminate-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --output text > /dev/null

echo "✓ Instance termination initiated"
echo "  Waiting for instance to terminate..."
aws ec2 wait instance-terminated \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION"

echo "✓ Instance terminated"

# Delete security group (wait a bit for instance to fully clean up)
echo ""
echo "[2/4] Deleting security group..."
sleep 10
aws ec2 delete-security-group \
  --group-id "$SG_ID" \
  --region "$REGION" || echo "  ⚠️  Could not delete security group (may be in use)"

echo "✓ Security group deleted"

# Delete key pair if requested
if [ "$DELETE_KEY" == "true" ]; then
  echo ""
  echo "[3/4] Deleting SSH key pair..."
  aws ec2 delete-key-pair \
    --key-name "$KEY_NAME" \
    --region "$REGION"

  if [ -f "$KEY_FILE" ]; then
    rm -f "$KEY_FILE"
    echo "✓ Local key file deleted: $KEY_FILE"
  fi

  echo "✓ SSH key pair deleted"
else
  echo ""
  echo "[3/4] Keeping SSH key pair: $KEY_NAME"
fi

# Remove instance info file
echo ""
echo "[4/4] Removing instance info file..."
rm -f "$INFO_FILE"
echo "✓ Instance info file removed"

echo ""
echo "=================================================="
echo "✅ Cleanup Complete!"
echo "=================================================="
echo ""

if [ "$DELETE_KEY" != "true" ]; then
  echo "Note: SSH key pair '$KEY_NAME' was kept."
  echo "      To delete it manually:"
  echo "      aws ec2 delete-key-pair --key-name $KEY_NAME --region $REGION"
  if [ -f "$KEY_FILE" ]; then
    echo "      rm $KEY_FILE"
  fi
  echo ""
fi

echo "All resources have been cleaned up."
echo "=================================================="
