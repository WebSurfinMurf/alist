#!/bin/bash
# Generate secrets for AList deployment
# This script creates the environment file with secure random passwords

set -e

SECRETS_DIR="$HOME/projects/secrets"
SECRETS_FILE="$SECRETS_DIR/alist.env"

echo "=== Generating AList Secrets ==="

# Verify secrets directory exists
mkdir -p "$SECRETS_DIR"

# Generate secure random password for AList admin
ALIST_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)

# Create environment file
cat > "$SECRETS_FILE" <<EOF
# AList Configuration
# Generated: $(date)
# DO NOT COMMIT TO GIT - Add to .gitignore

# AList Admin Password
# Use this to login as admin user on first access
ALIST_ADMIN_PASSWORD=$ALIST_ADMIN_PASSWORD

# AList Configuration
ALIST_SITE_URL=https://alist.ai-servicers.com
EOF

# Set secure permissions
chmod 600 "$SECRETS_FILE"

echo "✅ Secrets file created: $SECRETS_FILE"
echo ""
echo "=== AList Admin Credentials ==="
echo "Username: admin"
echo "Password: $ALIST_ADMIN_PASSWORD"
echo ""
echo "⚠️  IMPORTANT: Save these credentials securely!"
echo "⚠️  The password is also stored in: $SECRETS_FILE"
echo ""
echo "File permissions: $(ls -la $SECRETS_FILE | awk '{print $1, $3, $4, $9}')"
