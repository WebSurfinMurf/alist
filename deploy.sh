#!/bin/bash
# AList Deployment Script
# Deploys AList file manager with OAuth2/Keycloak authentication
# Following infrastructure standards for backend isolation

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_NAME="alist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}=== Deploying AList File Manager with Keycloak OAuth2 ===${NC}"

# ============================================================================
# Pre-Deployment Validation
# ============================================================================

# Verify environment files exist
if [ ! -f "$HOME/projects/secrets/${PROJECT_NAME}.env" ]; then
    echo -e "${RED}Error: AList environment file not found${NC}"
    echo "Run: cd $SCRIPT_DIR && ./generate-secrets.sh"
    exit 1
fi

if [ ! -f "$HOME/projects/secrets/${PROJECT_NAME}-oauth2.env" ]; then
    echo -e "${RED}Error: OAuth2 environment file not found${NC}"
    echo "File should be at: $HOME/projects/secrets/${PROJECT_NAME}-oauth2.env"
    exit 1
fi

# Load environment variables for validation and docker-compose substitution
set -a  # Export all variables
source "$HOME/projects/secrets/${PROJECT_NAME}.env"
source "$HOME/projects/secrets/${PROJECT_NAME}-oauth2.env"

# Dynamically resolve Traefik IP for extra_hosts configuration
TRAEFIK_IP=$(docker inspect traefik --format '{{range $net, $conf := .NetworkSettings.Networks}}{{if eq $net "traefik-net"}}{{.IPAddress}}{{end}}{{end}}' 2>/dev/null || echo "172.25.0.6")
export TRAEFIK_IP
echo -e "${YELLOW}Using Traefik IP: $TRAEFIK_IP${NC}"

set +a  # Stop exporting

# Verify Keycloak client secret is configured
if [ -z "$OAUTH2_PROXY_CLIENT_SECRET" ] || [ "$OAUTH2_PROXY_CLIENT_SECRET" = "<CLIENT_SECRET_FROM_KEYCLOAK>" ]; then
    echo -e "${RED}Error: Keycloak client secret not configured${NC}"
    echo "Please update $HOME/projects/secrets/${PROJECT_NAME}-oauth2.env with the client secret from Keycloak"
    exit 1
else
    echo -e "${YELLOW}Using existing Keycloak client secret${NC}"
fi

# Verify required variables
if [ -z "$ALIST_ADMIN_PASSWORD" ]; then
    echo -e "${RED}Error: ALIST_ADMIN_PASSWORD not set${NC}"
    echo "Run: cd $SCRIPT_DIR && ./generate-secrets.sh"
    exit 1
fi

echo -e "${GREEN}✓ Environment files validated${NC}"

# ============================================================================
# Network Setup
# ============================================================================

echo -e "${YELLOW}Creating Docker networks...${NC}"

# Create alist-net for backend isolation
docker network create alist-net 2>/dev/null && echo -e "${GREEN}✓ Created alist-net${NC}" || echo -e "${YELLOW}ℹ Network alist-net already exists${NC}"

# Verify external networks exist
docker network inspect traefik-net >/dev/null 2>&1 || {
    echo -e "${RED}Error: traefik-net network not found${NC}"
    exit 1
}

docker network inspect keycloak-net >/dev/null 2>&1 || {
    echo -e "${RED}Error: keycloak-net network not found${NC}"
    exit 1
}

echo -e "${GREEN}✓ All required networks exist${NC}"

# ============================================================================
# Data Directory Setup
# ============================================================================

echo -e "${YELLOW}Creating data directories...${NC}"
mkdir -p "$HOME/projects/data/alist"
mkdir -p "$HOME/projects/data/uploads"

echo -e "${GREEN}✓ Data directories ready${NC}"

# ============================================================================
# Container Deployment
# ============================================================================

echo -e "${YELLOW}Stopping existing containers...${NC}"
cd "$SCRIPT_DIR"
docker compose down 2>/dev/null || true

echo -e "${YELLOW}Starting AList containers...${NC}"
docker compose up -d

# ============================================================================
# Network Connection (OAuth2 Proxy)
# ============================================================================

echo -e "${YELLOW}Connecting OAuth2 proxy to additional networks...${NC}"

# OAuth2 proxy needs to be on 3 networks:
# 1. traefik-net (already connected via docker-compose)
# 2. keycloak-net (for authentication)
# 3. alist-net (to reach AList backend)

docker network connect keycloak-net alist-auth-proxy 2>/dev/null && \
    echo -e "${GREEN}✓ Connected to keycloak-net${NC}" || \
    echo -e "${YELLOW}ℹ Already connected to keycloak-net${NC}"

docker network connect alist-net alist-auth-proxy 2>/dev/null && \
    echo -e "${GREEN}✓ Connected to alist-net${NC}" || \
    echo -e "${YELLOW}ℹ Already connected to alist-net${NC}"

# ============================================================================
# Deployment Verification
# ============================================================================

echo -e "${YELLOW}Waiting for containers to start...${NC}"
sleep 10

echo ""
echo -e "${GREEN}=== Container Status ===${NC}"
docker ps | grep alist

echo ""
echo -e "${GREEN}=== Network Verification ===${NC}"

# Verify AList is on alist-net and traefik-net (dual access)
ALIST_NETWORKS=$(docker inspect alist --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')
echo "AList networks: $ALIST_NETWORKS"

REQUIRED_ALIST_NETWORKS=("alist-net" "traefik-net")
for net in "${REQUIRED_ALIST_NETWORKS[@]}"; do
    if echo "$ALIST_NETWORKS" | grep -q "$net"; then
        echo -e "${GREEN}✓ AList on $net${NC}"
    else
        echo -e "${RED}✗ AList NOT on $net${NC}"
    fi
done

# Verify OAuth2 proxy is on all 3 networks
PROXY_NETWORKS=$(docker inspect alist-auth-proxy --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')
echo "OAuth2 proxy networks: $PROXY_NETWORKS"

REQUIRED_NETWORKS=("traefik-net" "keycloak-net" "alist-net")
for net in "${REQUIRED_NETWORKS[@]}"; do
    if echo "$PROXY_NETWORKS" | grep -q "$net"; then
        echo -e "${GREEN}✓ OAuth2 proxy on $net${NC}"
    else
        echo -e "${RED}✗ OAuth2 proxy NOT on $net${NC}"
    fi
done

# ============================================================================
# Health Check
# ============================================================================

echo ""
echo -e "${YELLOW}Waiting for AList to become healthy (up to 60 seconds)...${NC}"
for i in {1..12}; do
    if docker ps | grep alist | grep -q "healthy"; then
        echo -e "${GREEN}✓ AList is healthy${NC}"
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# ============================================================================
# Connectivity Test
# ============================================================================

echo -e "${YELLOW}Testing internal connectivity...${NC}"
if docker exec alist-auth-proxy wget --quiet --tries=1 --spider http://alist:5244/ping 2>/dev/null; then
    echo -e "${GREEN}✓ OAuth2 proxy can reach AList backend${NC}"
else
    echo -e "${YELLOW}ℹ Health check endpoint may not exist (normal for some apps)${NC}"
fi

# ============================================================================
# Logs Check
# ============================================================================

echo ""
echo -e "${GREEN}=== Recent Logs ===${NC}"
echo -e "${YELLOW}AList:${NC}"
docker logs alist --tail 10

echo ""
echo -e "${YELLOW}OAuth2 Proxy:${NC}"
docker logs alist-auth-proxy --tail 10

# ============================================================================
# Deployment Complete
# ============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}Access AList at:${NC} https://alist.ai-servicers.com"
echo ""
echo -e "${YELLOW}First-time login:${NC}"
echo "  Username: admin"
echo "  Password: See $HOME/projects/secrets/alist.env"
echo ""
echo -e "${YELLOW}Authentication:${NC}"
echo "  - Keycloak SSO required (administrators or developers group)"
echo "  - Then AList login with admin credentials"
echo ""
echo -e "${YELLOW}Mounted directories:${NC}"
echo "  - /mnt/projects (read-only) - All infrastructure projects"
echo "  - /mnt/claudeagents (read-only) - Agent workspaces"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  Check status:  docker ps | grep alist"
echo "  View logs:     docker logs alist --follow"
echo "  View auth:     docker logs alist-auth-proxy --follow"
echo "  Restart:       cd $SCRIPT_DIR && docker compose restart"
echo "  Redeploy:      cd $SCRIPT_DIR && ./deploy.sh"
echo ""
