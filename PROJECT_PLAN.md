# AList Deployment Project Plan

**Created**: 2025-10-20
**Project Manager**: PM Agent
**Status**: Planning Phase

---

## 📋 Project Overview

**Application**: AList - File Manager/Listing Application
**Purpose**: Browse and manage project files and agent workspaces
**URL**: https://alist.ai-servicers.com
**Image**: xhofe/alist:latest

---

## 🎯 Requirements

### Core Requirements
- **Project Directory**: `$HOME/projects/alist`
- **Data Directory**: `$HOME/projects/data/alist` (database, config, persistent data)
- **Secrets File**: `$HOME/projects/secrets/alist.env` (AList config)
- **OAuth2 Secrets**: `$HOME/projects/secrets/alist-oauth2.env` (proxy auth)
- **Container Name**: `alist`
- **Docker Image**: `xhofe/alist:latest`

### Mount Points (Read-Only for AList)
1. `/home/administrator/projects` → Browse all projects
2. `/home/administrator/data/claudeagents` → Browse agent workspaces

### Access Control
- **Keycloak Groups**:
  - `administrators` - Full access (read + edit + delete)
  - `developers` - Read-only access (browse + download only)
- **Authentication**: Keycloak SSO via OAuth2 proxy
- **Authorization**: Group-based permissions in AList configuration

### Network Architecture
- **traefik-net**: External HTTPS access via Traefik
- **keycloak-net**: OAuth2 validation with Keycloak
- **alist-net**: Backend isolation (new network)

---

## 🏗️ Architecture Design

### Network Topology
```
Internet (HTTPS)
    ↓
Traefik (traefik-net)
    ↓
alist-auth-proxy (traefik-net + keycloak-net + alist-net)
    ↓ validates with Keycloak (via keycloak-net)
    ↓ forwards authenticated requests (via alist-net)
AList Backend (alist-net ONLY - not on traefik-net)
    ↓ mounts
File System (/projects, /claudeagents)
```

### Component Architecture

#### 1. AList Container
- **Networks**: alist-net ONLY (backend isolation)
- **Ports**: 5244 (internal, not exposed)
- **Volumes**:
  - `/home/administrator/projects/data/alist:/opt/alist/data` (read-write, persistent data)
  - `/home/administrator/projects:/mnt/projects:ro` (read-only mount)
  - `/home/administrator/data/claudeagents:/mnt/claudeagents:ro` (read-only mount)
- **Environment**: Via secrets/alist.env
- **Purpose**: File browsing and management backend

#### 2. OAuth2 Proxy Container
- **Name**: alist-auth-proxy
- **Networks**: traefik-net + keycloak-net + alist-net (3-network bridge)
- **Purpose**: Keycloak SSO authentication enforcement
- **Upstream**: http://alist:5244
- **Groups**: administrators, developers
- **Environment**: Via secrets/alist-oauth2.env

#### 3. Keycloak Client
- **Client ID**: alist
- **Protocol**: openid-connect
- **Access Type**: confidential
- **Valid Redirect URIs**: https://alist.ai-servicers.com/oauth2/callback
- **Scopes**: openid, profile, email, groups
- **Mappers**: groups mapper ONLY (no audience mapper)

---

## 🔐 Security Configuration

### OAuth2 Proxy Pattern (Standard 3-Network)
Following infrastructure security standards:
- **traefik-net**: Receives HTTPS traffic from Traefik
- **keycloak-net**: Validates tokens with Keycloak (internal HTTP)
- **alist-net**: Forwards authenticated requests to AList backend

### Backend Isolation
- AList container is NOT on traefik-net (cannot bypass authentication)
- All traffic must go through OAuth2 proxy
- Direct access to AList impossible without authentication

### Group-Based Authorization
```yaml
Access Matrix:
  administrators:
    - Browse: YES
    - Download: YES
    - Upload: YES
    - Edit: YES
    - Delete: YES

  developers:
    - Browse: YES
    - Download: YES
    - Upload: NO
    - Edit: NO
    - Delete: NO
```

### File System Security
- Projects mount: Read-only to prevent accidental modifications
- Claudeagents mount: Read-only to prevent accidental modifications
- Data directory: Read-write for AList persistent data only
- All mounts owned by administrator user

---

## 💻 Implementation Tasks

### Phase 1: Infrastructure Setup
**Agent: Developer + Security**

**Task 1.1: Create Directory Structure**
```bash
mkdir -p $HOME/projects/alist
mkdir -p $HOME/projects/data/alist
```

**Task 1.2: Create Docker Networks**
```bash
docker network create alist-net 2>/dev/null || echo "Network may already exist"
# traefik-net and keycloak-net should already exist
```

**Task 1.3: Create Keycloak Client**
**Agent: Security**
- Client ID: alist
- Configure redirect URI: https://alist.ai-servicers.com/oauth2/callback
- Generate client secret
- Configure groups mapper
- Test with both administrators and developers groups

**Task 1.4: Generate Secrets Files**
```bash
# Generate secure passwords
ALIST_ADMIN_PASSWORD=$(openssl rand -base64 32)
OAUTH2_CLIENT_SECRET="<from Keycloak>"
OAUTH2_COOKIE_SECRET=$(openssl rand -hex 32)

# Create alist.env
# Create alist-oauth2.env
```

---

### Phase 2: Deployment
**Agent: Developer**

**Task 2.1: Deploy AList Container**
```bash
docker run -d \
  --name alist \
  --restart unless-stopped \
  --network alist-net \
  -v $HOME/projects/data/alist:/opt/alist/data \
  -v $HOME/projects:/mnt/projects:ro \
  -v $HOME/data/claudeagents:/mnt/claudeagents:ro \
  --env-file $HOME/projects/secrets/alist.env \
  xhofe/alist:latest
```

**Task 2.2: Configure AList Internal Settings**
- Set admin password
- Configure mount points (/mnt/projects, /mnt/claudeagents)
- Set up user access rules based on OAuth2 groups
- Configure read-only vs read-write permissions

**Task 2.3: Deploy OAuth2 Proxy**
```bash
docker run -d \
  --name alist-auth-proxy \
  --restart unless-stopped \
  --network traefik-net \
  --env-file $HOME/projects/secrets/alist-oauth2.env \
  --label "traefik.enable=true" \
  --label "traefik.docker.network=traefik-net" \
  --label "traefik.http.routers.alist.rule=Host(\`alist.ai-servicers.com\`)" \
  --label "traefik.http.routers.alist.entrypoints=websecure" \
  --label "traefik.http.routers.alist.tls=true" \
  --label "traefik.http.routers.alist.tls.certresolver=letsencrypt" \
  --label "traefik.http.services.alist.loadbalancer.server.port=4180" \
  quay.io/oauth2-proxy/oauth2-proxy:latest

# Connect to additional networks
docker network connect keycloak-net alist-auth-proxy
docker network connect alist-net alist-auth-proxy
```

---

### Phase 3: Configuration & Testing
**Agent: Developer + PM**

**Task 3.1: Verify Network Connectivity**
```bash
# Check AList is NOT on traefik-net (security verification)
docker inspect alist | grep -A 10 Networks

# Check OAuth2 proxy is on all 3 networks
docker inspect alist-auth-proxy | grep -A 10 Networks
```

**Task 3.2: Test Authentication Flow**
1. Access https://alist.ai-servicers.com
2. Should redirect to Keycloak login
3. Login with administrators group user
4. Should see full access (edit capabilities)
5. Login with developers group user
6. Should see read-only access

**Task 3.3: Test File Browsing**
1. Browse /mnt/projects - verify all projects visible
2. Browse /mnt/claudeagents - verify agent workspaces visible
3. Test download functionality
4. Test edit permissions (administrators only)

**Task 3.4: Verify AList Configuration**
```bash
# Check AList logs
docker logs alist --tail 50

# Check OAuth2 proxy logs
docker logs alist-auth-proxy --tail 50

# Verify health
curl -I https://alist.ai-servicers.com
```

---

### Phase 4: Integration & Documentation
**Agent: PM**

**Task 4.1: Update Dashy**
Edit `/home/administrator/projects/dashy/data/infra.yml`:
```yaml
# Under "Context Management" group on Home tab
- name: AList
  description: File Manager - Browse Projects & Agent Workspaces
  icon: hl-alist
  url: https://alist.ai-servicers.com
  target: newtab
  statusCheck: true
  statusCheckUrl: https://alist.ai-servicers.com
  statusCheckAcceptCodes: '200,401,403'
```

**Task 4.2: Create Documentation**
Create `/home/administrator/projects/alist/CLAUDE.md` with:
- Deployment details
- Mount point configuration
- Permission matrix
- Troubleshooting guide
- Integration notes

**Task 4.3: Update System Documentation**
Update `/home/administrator/projects/AINotes/SYSTEM-OVERVIEW.md`:
- Add AList to application services section
- Document OAuth2 integration
- Note mount points and access patterns

---

## 📊 Success Criteria

### Functional Requirements
- ✅ AList accessible at https://alist.ai-servicers.com
- ✅ Keycloak SSO authentication working
- ✅ Both groups (administrators, developers) can login
- ✅ Administrators have full access (read/write/edit)
- ✅ Developers have read-only access
- ✅ /projects directory browsable
- ✅ /claudeagents directory browsable
- ✅ Data persists in /projects/data/alist

### Security Requirements
- ✅ AList backend NOT on traefik-net (isolated)
- ✅ OAuth2 proxy enforces authentication
- ✅ Cannot bypass authentication to reach AList
- ✅ Group-based authorization working
- ✅ File system mounts are read-only

### Integration Requirements
- ✅ Traefik routing configured
- ✅ SSL certificate working
- ✅ Keycloak client configured
- ✅ Dashy updated with AList entry
- ✅ All networks properly configured

### Documentation Requirements
- ✅ CLAUDE.md created and complete
- ✅ SYSTEM-OVERVIEW.md updated
- ✅ Deploy script tested and working
- ✅ Troubleshooting guide included

---

## 🔄 Agent Workflow

### Sequence of Operations

**1. PM Agent** (Current)
- ✅ Create project plan
- Coordinate all agents
- Track progress
- Final verification

**2. Architect Agent**
- Review plan and provide architecture guidance
- Validate network topology
- Recommend best practices
- Design verification tests

**3. Security Agent**
- Create Keycloak client (alist)
- Configure groups mapper
- Generate OAuth2 secrets
- Validate security configuration
- Test authentication with both groups

**4. Developer Agent**
- Create directory structure
- Generate secrets files
- Deploy AList container
- Configure AList settings (mount points, permissions)
- Deploy OAuth2 proxy
- Connect all networks
- Test deployment
- Create deploy.sh script

**5. PM Agent** (Final)
- Verify all success criteria
- Update Dashy
- Create documentation
- Update system documentation
- Close project

---

## 📝 Configuration Files

### secrets/alist.env
```bash
# AList Configuration
ALIST_ADMIN_PASSWORD=<generated>
ALIST_SITE_URL=https://alist.ai-servicers.com
ALIST_DATA=/opt/alist/data

# Mount points configured in AList UI:
# - /mnt/projects (read-only)
# - /mnt/claudeagents (read-only)
```

### secrets/alist-oauth2.env
```bash
# OAuth2 Proxy Configuration
OAUTH2_PROXY_CLIENT_ID=alist
OAUTH2_PROXY_CLIENT_SECRET=<from Keycloak>
OAUTH2_PROXY_COOKIE_SECRET=<generated 32-byte hex>
OAUTH2_PROXY_PROVIDER=keycloak-oidc
OAUTH2_PROXY_OIDC_ISSUER_URL=https://keycloak.ai-servicers.com/realms/master
OAUTH2_PROXY_LOGIN_URL=https://keycloak.ai-servicers.com/realms/master/protocol/openid-connect/auth
OAUTH2_PROXY_REDEEM_URL=http://keycloak:8080/realms/master/protocol/openid-connect/token
OAUTH2_PROXY_OIDC_JWKS_URL=http://keycloak:8080/realms/master/protocol/openid-connect/certs
OAUTH2_PROXY_REDIRECT_URL=https://alist.ai-servicers.com/oauth2/callback
OAUTH2_PROXY_UPSTREAMS=http://alist:5244
OAUTH2_PROXY_EMAIL_DOMAINS=*
OAUTH2_PROXY_COOKIE_SECURE=true
OAUTH2_PROXY_COOKIE_HTTPONLY=true
OAUTH2_PROXY_COOKIE_SAMESITE=lax
OAUTH2_PROXY_SKIP_OIDC_DISCOVERY=true
OAUTH2_PROXY_OIDC_GROUPS_CLAIM=groups
OAUTH2_PROXY_ALLOWED_GROUPS=administrators,developers
OAUTH2_PROXY_INSECURE_OIDC_ALLOW_UNVERIFIED_EMAIL=true
OAUTH2_PROXY_PASS_AUTHORIZATION_HEADER=true
OAUTH2_PROXY_PASS_ACCESS_TOKEN=true
OAUTH2_PROXY_PASS_USER_HEADERS=true
OAUTH2_PROXY_SET_XAUTHREQUEST=true
```

---

## 🚨 Known Considerations

### AList Permission Configuration
AList needs internal configuration to map OAuth2 groups to permissions:
- May require AList-specific user/group mapping
- Administrator group → full permissions
- Developer group → read-only permissions
- Research AList documentation for OAuth2 group mapping

### Mount Point Limitations
- Mounts are read-only to prevent accidental file modifications
- AList can browse and download but cannot modify source files
- Uploads/edits would need to go to a separate writable directory

### Performance Considerations
- Large directory listings may be slow
- Consider AList caching configuration
- Monitor resource usage with many concurrent users

---

## 📚 References

### Infrastructure Standards
- `/home/administrator/projects/AINotes/codingstandards.md` - Naming, security directives
- `/home/administrator/projects/AINotes/network.md` - Network topology standards
- `/home/administrator/projects/AINotes/security.md` - OAuth2 patterns, Keycloak configuration

### Example Implementations
- `/home/administrator/projects/dashy/` - OAuth2 proxy example
- `/home/administrator/projects/grafana/` - Similar authentication pattern
- `/home/administrator/projects/arangodb/` - Recent OAuth2 deployment

---

## ✅ Next Steps

**Ready for agent coordination:**

1. **Launch Architect Agent** - Validate architecture design
2. **Launch Security Agent** - Create Keycloak client and secrets
3. **Launch Developer Agent** - Execute deployment
4. **PM Verification** - Test and document

**Command to start**: Await user confirmation to proceed with agent coordination.

---

**Project Plan Complete**
**Status**: Ready for Implementation
**Estimated Time**: 2-3 hours with agent coordination
**Risk Level**: Low (following established patterns)
