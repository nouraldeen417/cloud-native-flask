#!/usr/bin/env bash
set -euo pipefail

# Refreshes AWS Academy Learner Lab session credentials (access key, secret key,
# session token) into GitHub Actions secrets. Run this every time your Learner
# Lab session restarts and the old credentials go stale.
#
# Where to get the values: Learner Lab page → "AWS Details" → "Show" next to
# AWS CLI credentials. Copy the whole block, paste when prompted below.
#
# Prerequisites:
#   - gh auth login (already done for the Azure side of this project)
#   - Run from inside the repo directory (or add --repo owner/name below)

echo "== AWS Learner Lab Credential Refresh =="
echo ""
echo "Paste the credentials block from Learner Lab's 'AWS Details' panel."
echo "It looks like:"
echo "  aws_access_key_id=..."
echo "  aws_secret_access_key=..."
echo "  aws_session_token=..."
echo ""
echo "Paste it now, then press Ctrl+D when done:"

CREDS_BLOCK=$(cat)

AWS_ACCESS_KEY_ID=$(echo "$CREDS_BLOCK" | grep -i 'aws_access_key_id' | cut -d'=' -f2- | tr -d '[:space:]')
AWS_SECRET_ACCESS_KEY=$(echo "$CREDS_BLOCK" | grep -i 'aws_secret_access_key' | cut -d'=' -f2- | tr -d '[:space:]')
AWS_SESSION_TOKEN=$(echo "$CREDS_BLOCK" | grep -i 'aws_session_token' | cut -d'=' -f2- | tr -d '[:space:]')

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then
  echo "ERROR: one or more values missing — check the pasted block has all three lines"
  echo "  found access_key_id: ${AWS_ACCESS_KEY_ID:+yes}"
  echo "  found secret_access_key: ${AWS_SECRET_ACCESS_KEY:+yes}"
  echo "  found session_token: ${AWS_SESSION_TOKEN:+yes}"
  exit 1
fi

echo ""
echo "Parsed successfully. Pushing to GitHub secrets..."

gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY_ID"
gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_ACCESS_KEY"
gh secret set AWS_SESSION_TOKEN --body "$AWS_SESSION_TOKEN"

echo ""
echo "Also writing local ~/.aws/credentials so Terraform can run locally too..."

mkdir -p "$HOME/.aws"
cat > "$HOME/.aws/credentials" << EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
aws_session_token = $AWS_SESSION_TOKEN
EOF

echo ""
echo "Done. GitHub secrets updated and local AWS credentials refreshed."
echo "Verify with: gh secret list"
echo ""
echo "Note: these credentials are only valid for the current Learner Lab session."
echo "Re-run this script whenever your session restarts."