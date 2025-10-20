#!/bin/bash
# AList Configuration Helper Script
# Use this script after first deployment to configure AList

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== AList Configuration Helper ===${NC}"
echo ""

# Load admin password
if [ -f "$HOME/projects/secrets/alist.env" ]; then
    source "$HOME/projects/secrets/alist.env"
fi

echo -e "${YELLOW}Step 1: Get Initial Admin Password${NC}"
echo ""
echo "AList generates a random admin password on first run."
echo "To retrieve it, check the container logs:"
echo ""
echo -e "${GREEN}docker logs alist 2>&1 | grep -i password${NC}"
echo ""
echo "Or use the password from the environment file:"
echo ""
if [ -n "$ALIST_ADMIN_PASSWORD" ]; then
    echo -e "Username: ${GREEN}admin${NC}"
    echo -e "Password: ${GREEN}$ALIST_ADMIN_PASSWORD${NC}"
else
    echo "Password not found in environment file"
fi
echo ""

echo -e "${YELLOW}Step 2: Access AList${NC}"
echo ""
echo "1. Open browser: ${GREEN}https://alist.ai-servicers.com${NC}"
echo "2. You'll be redirected to Keycloak login"
echo "3. Login with your Keycloak credentials (administrators or developers group)"
echo "4. You'll then see AList login page"
echo "5. Login with admin credentials from Step 1"
echo ""

echo -e "${YELLOW}Step 3: Configure Mount Points${NC}"
echo ""
echo "After logging in as admin:"
echo ""
echo "1. Go to: ${GREEN}Settings → Storages${NC}"
echo "2. Click ${GREEN}Add Storage${NC}"
echo ""
echo -e "${GREEN}Mount Point 1: Projects Directory${NC}"
echo "   - Mount Path: /projects"
echo "   - Driver: Local"
echo "   - Root Folder Path: /mnt/projects"
echo "   - Order: 1"
echo "   - Enable: Yes"
echo ""
echo -e "${GREEN}Mount Point 2: Agent Workspaces${NC}"
echo "   - Mount Path: /claudeagents"
echo "   - Driver: Local"
echo "   - Root Folder Path: /mnt/claudeagents"
echo "   - Order: 2"
echo "   - Enable: Yes"
echo ""

echo -e "${YELLOW}Step 4: Security Settings (Optional)${NC}"
echo ""
echo "Since OAuth2 proxy handles authentication, you may want to:"
echo ""
echo "1. Disable guest access (Settings → Other → Guest access)"
echo "2. Keep admin account for configuration only"
echo "3. Consider if you need AList's internal authentication at all"
echo ""
echo -e "${YELLOW}Note:${NC} OAuth2 proxy provides group-based access control."
echo "AList may not distinguish between administrators and developers groups."
echo "Both groups will have the same access level within AList."
echo ""

echo -e "${YELLOW}Step 5: Verify Read-Only Mounts${NC}"
echo ""
echo "The mounted directories are read-only by design:"
echo ""
echo "- You can browse and download files"
echo "- You CANNOT edit or delete source files"
echo "- This protects project files from accidental modification"
echo ""
echo "Test by trying to:"
echo "1. Browse to /projects"
echo "2. Try to delete a file (should fail)"
echo "3. Download a file (should work)"
echo ""

echo -e "${YELLOW}Step 6: Troubleshooting${NC}"
echo ""
echo "If you can't access AList:"
echo ""
echo "Check containers:"
echo -e "  ${GREEN}docker ps | grep alist${NC}"
echo ""
echo "Check AList logs:"
echo -e "  ${GREEN}docker logs alist --tail 50${NC}"
echo ""
echo "Check OAuth2 proxy logs:"
echo -e "  ${GREEN}docker logs alist-auth-proxy --tail 50${NC}"
echo ""
echo "Verify you're in administrators or developers group in Keycloak:"
echo -e "  ${GREEN}https://keycloak.ai-servicers.com:8443${NC}"
echo ""

echo -e "${GREEN}Configuration complete!${NC}"
echo ""
