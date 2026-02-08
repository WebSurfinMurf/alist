# AList - Self-Hosted File Manager

## Overview
AList is a powerful file list program that supports multiple storage providers, allowing you to browse and manage files from various sources through a unified web interface. This deployment provides secure access to browse project directories and agent workspaces with Keycloak SSO authentication.

**Project Type:** File Manager / Storage Browser / Web File Explorer
**Deployment Date:** 2025-10-20
**Status:** Production
**Primary DNS:** https://alist.ai-servicers.com

## Architecture

### Components

1. **AList (xhofe/alist:latest)** - File manager application
   - Container: `alist`
   - Internal port: 5244 (HTTP)
   - Networks: `alist-net` (isolated backend)
   - Technology: Go-based web file manager
   - Backend isolation: NOT on traefik-net for security

2. **OAuth2 Proxy (latest)** - Authentication gateway
   - Container: `alist-auth-proxy`
   - External port: 4180 (via Traefik)
   - Networks: `alist-net`, `keycloak-net`, `traefik-net`
   - Keycloak integration with hybrid URL strategy
   - 3-network pattern for backend isolation

### Network Isolation

```
Internet → Traefik (traefik-net)
              ↓
         OAuth2 Proxy (traefik-net + keycloak-net + alist-net)
              ↓
         AList Backend (alist-net ONLY - isolated)
```

**Security Architecture:**
- **Backend Isolation**: AList is NOT on traefik-net (no direct external access)
- **3-Network OAuth2 Pattern**:
  - traefik-net: Receives HTTPS traffic from Traefik
  - keycloak-net: Validates authentication with Keycloak
  - alist-net: Forwards authenticated requests to backend
- **Hybrid URL Strategy**: Browser URLs use HTTPS, backend URLs use internal HTTP
- **Group-Based Access**: Both administrators and developers groups have access

## Features

### Core Functionality
- **Web File Browser**: Browse files and directories via web interface
- **Multiple Storage Support**: Local storage, S3, WebDAV, OneDrive, Google Drive, etc.
- **Directory Mounting**: Mount read-only directories for browsing
- **File Preview**: View images, videos, documents inline
- **Download/Upload**: Download files, upload to writable mounts
- **Search**: Search across mounted directories
- **Path Navigation**: Breadcrumb navigation and quick access
- **Mobile Responsive**: Works on phones, tablets, desktops

### Advanced Features
- **Storage Drivers**: 30+ storage provider integrations
- **Offline Download**: Download files from URLs to storage
- **Video Streaming**: Stream video files with player controls
- **Image Gallery**: Gallery view for images with slideshow
- **Text Editor**: Edit text files directly in browser
- **Archive Extraction**: View contents of ZIP/RAR files
- **WebDAV**: Expose storage via WebDAV protocol
- **API Access**: RESTful API for automation

### File Management
- **Copy/Move/Delete**: Manage files across storages (if writable)
- **Rename**: Rename files and folders
- **New Folder**: Create new directories (if writable)
- **Batch Operations**: Select multiple files for bulk actions
- **Context Menu**: Right-click menu for quick actions
- **Shortcuts**: Keyboard shortcuts for common operations

### Content Features
- **Video Player**: Built-in video player with subtitles support
- **Audio Player**: Play music files with playlist
- **PDF Viewer**: View PDF documents inline
- **Code Syntax**: Syntax highlighting for code files
- **Markdown Rendering**: Render .md files as HTML
- **Archive Preview**: List contents of compressed files

## Configuration

### Environment Variables

**Location 1:** `$HOME/projects/secrets/alist.env`
```bash
# AList Configuration
ALIST_ADMIN_PASSWORD=<generated_password>
PUID=1000
PGID=1000
UMASK=022
```

**Location 2:** `$HOME/projects/secrets/alist-oauth2.env`
```bash
# OAuth2 Proxy Secrets
OAUTH2_PROXY_CLIENT_SECRET=<keycloak_client_secret>
OAUTH2_PROXY_COOKIE_SECRET=<32_byte_random_string>
```

**Note:** All other OAuth2 configuration is in docker-compose.yml (following Obsidian pattern).

### OAuth2 Configuration (docker-compose.yml)

**Provider Settings:**
- `OAUTH2_PROXY_PROVIDER=keycloak-oidc`
- `OAUTH2_PROXY_CLIENT_ID=alist`
- `OAUTH2_PROXY_OIDC_ISSUER_URL=https://keycloak.ai-servicers.com/realms/master`
- `OAUTH2_PROXY_LOGIN_URL=https://keycloak.ai-servicers.com/realms/master/protocol/openid-connect/auth`
- `OAUTH2_PROXY_REDEEM_URL=http://keycloak:8080/realms/master/protocol/openid-connect/token`
- `OAUTH2_PROXY_OIDC_JWKS_URL=http://keycloak:8080/realms/master/protocol/openid-connect/certs`
- `OAUTH2_PROXY_SKIP_OIDC_DISCOVERY=true`

**Access Control:**
- `OAUTH2_PROXY_ALLOWED_GROUPS=/administrators,/developers`
- `OAUTH2_PROXY_OIDC_GROUPS_CLAIM=groups`
- `OAUTH2_PROXY_SCOPE=openid profile email groups`

**Upstream Configuration:**
- `OAUTH2_PROXY_UPSTREAMS=http://alist:5244`
- `OAUTH2_PROXY_REDIRECT_URL=https://alist.ai-servicers.com/oauth2/callback`

### Keycloak Client

**Client ID:** `alist`
**Client Type:** Confidential (client authentication ON)
**Client Secret:** Stored in `$HOME/projects/secrets/alist-oauth2.env`

**Valid Redirect URIs:**
- `https://alist.ai-servicers.com/*`
- `https://alist.ai-servicers.com/oauth2/callback`

**Valid Post Logout Redirect URIs:**
- `https://alist.ai-servicers.com/*`

**Web Origins:**
- `https://alist.ai-servicers.com`

**Access Control:** `/developers` and `/administrators` groups (both have access)

**Client Scopes:**
- Default scopes: web-origins, acr, profile, roles, groups, basic, email
- Groups mapper: Full group path ON (sends groups as `/administrators` not `administrators`)

**Protocol Mappers:**
- `groups`: Group membership mapper (full path, multivalued)
- `Client ID`, `Client Host`, `Client IP Address` mappers for audit trail

## Deployment

### Initial Setup

**Step 1: Generate Secrets**

```bash
cd /home/administrator/projects/alist
./generate-secrets.sh
```

This creates:
- AList admin password
- OAuth2 cookie secret (32-byte random)
- Placeholder for Keycloak client secret

**Step 2: Create Keycloak Client**

The client configuration is in `/mnt/shared/alist.json`. Import via:
- Keycloak → Clients → Import client
- Or create manually following the Keycloak Client section above

Copy the generated client secret to `$HOME/projects/secrets/alist-oauth2.env`:
```bash
nano $HOME/projects/secrets/alist-oauth2.env
# Update OAUTH2_PROXY_CLIENT_SECRET=<client_secret_from_keycloak>
```

**Step 3: Deploy**

```bash
cd /home/administrator/projects/alist
./deploy.sh
```

The deployment script:
1. Validates environment files exist
2. Verifies Keycloak client secret is configured
3. Creates Docker networks (alist-net)
4. Creates data directories
5. Exports environment variables (set -a)
6. Deploys containers via docker-compose
7. Verifies network topology (backend isolation)
8. Tests internal connectivity
9. Displays logs and status

### Manual Operations

**Restart services:**
```bash
cd /home/administrator/projects/alist
docker compose restart
```

**View logs:**
```bash
docker logs -f alist
docker logs -f alist-auth-proxy
```

**Redeploy (recommended for config changes):**
```bash
cd /home/administrator/projects/alist
./deploy.sh
```

**Stop services:**
```bash
cd /home/administrator/projects/alist
docker compose down
```

## Access

### Web Interface

**External (SSO):** https://alist.ai-servicers.com
- Authentication: OAuth2 via Keycloak
- Authorized Groups: `/developers`, `/administrators`
- Features: Full AList web interface with SSO protection

### First-Time Setup

1. **Access AList** via https://alist.ai-servicers.com
2. **Keycloak Login**: Authenticate with your account (must be in developers or administrators group)
3. **Browse Directories**: After OAuth2, you're in as guest (read-only) - no separate alist login needed
   - `/projects` - All infrastructure projects (read-only)
   - `/uploads` - Shared uploads
   - `/dev-projects` - Developer projects
4. **Admin Access** (optional): Login via alist's own login for admin operations:
   - Username: `admin`
   - Password: See `$HOME/projects/secrets/alist.env`

### Admin Password Reset

If you forget the AList admin password:

```bash
# View current password
cat $HOME/projects/secrets/alist.env | grep ALIST_ADMIN_PASSWORD

# Or reset via CLI inside container
docker exec -it alist ./alist admin set <new_password>
```

## Use Cases

### 1. Browse Infrastructure Projects
```bash
# Navigate to /mnt/projects
# View all project files and directories
# Search for specific configurations
# Download deployment scripts
```

### 2. Explore Agent Workspaces
```bash
# Navigate to /mnt/claudeagents
# View PM, Architect, Security, Developer workspaces
# Check agent reports, decisions, notes
# Download context files for analysis
```

### 3. File Search and Discovery
```bash
# Use search bar to find files across all mounts
# Search for "docker-compose.yml" to find all compose files
# Search for ".env" to locate environment files
# Filter by file type, date modified, size
```

### 4. Quick File Preview
```bash
# Click on images to view inline
# View text files without downloading
# Read markdown documentation
# Check configuration files
```

### 5. Code Review
```bash
# Browse project source code
# View code with syntax highlighting
# Compare configurations across projects
# Check deployment script contents
```

### 6. Documentation Access
```bash
# Read CLAUDE.md files from each project
# Browse AINotes documentation
# View README files
# Check integration guides
```

### 7. Log File Review
```bash
# Browse container log directories (if mounted)
# View application logs
# Search log contents
# Download logs for analysis
```

## Data Persistence

### Volume Mounts

```
# AList data (read-write)
/home/administrator/projects/data/alist → /opt/alist/data

# Browseable directories (read-only)
/home/administrator/projects → /mnt/projects:ro
/home/administrator/data/claudeagents → /mnt/claudeagents:ro
```

### AList Data Directory

Location: `/home/administrator/projects/data/alist`

Stored data:
- Database (SQLite): `data.db`
- Configuration: `config.json`
- Logs: `log/`
- Temporary uploads: `temp/`
- Custom settings
- Storage provider credentials

**Note:** All persistent data is stored in `/home/administrator/projects/data/alist`, not in the project directory.

### Mounted Directories

**Projects Mount:**
- Source: `/home/administrator/projects`
- Container: `/mnt/projects`
- Access: Read-only
- Contents: All infrastructure project directories

**Claude Agents Mount:**
- Source: `/home/administrator/data/claudeagents`
- Container: `/mnt/claudeagents`
- Access: Read-only
- Contents: PM, Architect, Security, Developer agent workspaces

**Storage Configuration:**
- Add mounts in AList web interface
- Storage → Add → Local Storage
- Set mount path (e.g., `/mnt/projects`)
- Configure as read-only if needed

### Backup Strategy

**Backup AList Database:**
```bash
# Backup database and config
tar -czf alist-backup-$(date +%Y%m%d).tar.gz \
  /home/administrator/projects/data/alist/

# Or backup just the database
cp /home/administrator/projects/data/alist/data.db \
   /home/administrator/projects/data/alist/data.db.backup
```

**Restore from Backup:**
```bash
# Stop AList
cd /home/administrator/projects/alist
docker compose down

# Restore backup
tar -xzf alist-backup-YYYYMMDD.tar.gz -C /

# Restart
./deploy.sh
```

## Common Commands

```bash
# Check status
docker ps --filter name=alist

# View AList logs
docker logs alist --tail 50 --follow

# View OAuth2 proxy logs
docker logs alist-auth-proxy --tail 50 --follow

# Restart AList only
docker restart alist

# Restart OAuth2 proxy only
docker restart alist-auth-proxy

# Full redeploy
cd /home/administrator/projects/alist
./deploy.sh

# Check container health
docker inspect alist --format '{{.State.Status}}'
docker inspect alist-auth-proxy --format '{{.State.Status}}'

# Verify network topology (backend isolation)
docker inspect alist --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
# Should show: alist-net ONLY (not traefik-net)

docker inspect alist-auth-proxy --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
# Should show: traefik-net keycloak-net alist-net (all 3)

# Check data directory size
du -sh /home/administrator/projects/data/alist/

# View AList admin info
docker exec -it alist ./alist admin

# Reset admin password
docker exec -it alist ./alist admin set <new_password>

# View AList version
docker exec -it alist ./alist version

# Test internal connectivity from OAuth2 proxy to AList
docker exec -it alist-auth-proxy wget -O- http://alist:5244 2>&1 | head -20
```

## Troubleshooting

### AList Won't Start

**Issue:** Container keeps restarting
**Cause:** Port conflict, permission issue, or corrupted database
**Solution:**

```bash
# Check logs
docker logs alist --tail 100

# Check for port conflicts
sudo netstat -tlnp | grep 5244

# Check file permissions
ls -la /home/administrator/projects/data/alist/
# Should be owned by UID 1000 (PUID)

# Fix permissions if needed
sudo chown -R 1000:1000 /home/administrator/projects/data/alist/

# If database is corrupted, restore from backup or delete to start fresh
# WARNING: This deletes all AList configuration!
# docker compose down
# rm -rf /home/administrator/projects/data/alist/*
# ./deploy.sh
```

### OAuth2 Proxy Issues

**Issue:** 403 Forbidden on login
**Cause:** User not in authorized groups
**Solution:**
1. Verify user is in `/developers` or `/administrators` group in Keycloak
2. Check groups claim is configured (Keycloak → Client Scopes → groups mapper)
3. Verify full group path is ON in groups mapper

**Issue:** "Invalid redirect_uri" error
**Cause:** Redirect URI not configured in Keycloak client
**Solution:**
```bash
# Add to Keycloak client Valid redirect URIs:
# https://alist.ai-servicers.com/*
# https://alist.ai-servicers.com/oauth2/callback
```

**Issue:** "Invalid OAuth2 state" error
**Cause:** Cookie secret mismatch or stale cookies
**Solution:**
```bash
# Clear browser cookies for alist.ai-servicers.com
# Verify OAUTH2_PROXY_COOKIE_SECRET matches in env file
# Redeploy to ensure cookie secret is loaded
cd /home/administrator/projects/alist
./deploy.sh
```

### Environment Variables Not Loading

**Issue:** OAuth2 proxy shows no environment variables
**Cause:** env_file permissions or not exported before docker-compose
**Solution:**
```bash
# Check that deploy.sh exports variables with set -a
# Verify secrets file is readable
ls -la $HOME/projects/secrets/alist-oauth2.env

# Redeploy to reload configuration
cd /home/administrator/projects/alist
./deploy.sh

# Verify variables are loaded
docker inspect alist-auth-proxy --format '{{range .Config.Env}}{{println .}}{{end}}' | grep OAUTH2
```

### Can't Access Mounted Directories

**Issue:** AList shows empty or permission denied
**Cause:** Mount paths not configured in AList or permission issues
**Solution:**

```bash
# 1. Login to AList as admin
# 2. Go to: Storage → Add Storage
# 3. Driver: Local
# 4. Mount path: /projects (display name)
# 5. Root folder path: /mnt/projects
# 6. Enable "Read only"
# 7. Order: 0
# 8. Save

# Repeat for /mnt/claudeagents

# If permission denied, check container can read mounts:
docker exec -it alist ls -la /mnt/projects
docker exec -it alist ls -la /mnt/claudeagents
```

### Traefik 404 Error

**Issue:** https://alist.ai-servicers.com returns 404
**Cause:** Traefik not discovering OAuth2 proxy container
**Solution:**

```bash
# Check container is running and healthy
docker ps --filter name=alist-auth-proxy

# Check Traefik can see the service
docker logs traefik --tail 50 | grep alist

# Verify Traefik labels are correct
docker inspect alist-auth-proxy --format '{{json .Config.Labels}}' | jq

# Restart Traefik to rediscover services
docker restart traefik

# Wait 10-20 seconds and test again
```

### Slow File Browsing

**Issue:** Directory listing is slow
**Cause:** Large directories, network latency, or storage provider issues
**Solution:**

```bash
# For local storage, check I/O performance
docker stats alist

# Enable pagination in AList settings
# Settings → Page size: 100 (reduce for faster loading)

# Disable thumbnail generation for large image directories
# Settings → Disable thumbnails
```

## Security

### Authentication Layers

1. **External Access:** OAuth2 proxy → Keycloak SSO → Group membership check
2. **AList Login:** Admin credentials required after OAuth2
3. **Network Isolation:** Backend on separate network (alist-net)
4. **Backend Protection:** AList NOT on traefik-net (no direct external access)

### Access Control

**OAuth2 Groups:**
- `/administrators` - Full access to AList (read/write if configured)
- `/developers` - Read-only access to browse files

**AList Permissions:**
- Admin account: Full control over all storages and settings
- Guest access: Enabled (read-only browsing after OAuth2 login - no separate alist login needed)
- SSO users: Auto-registered with permission 63 (read/write)
- Read-only mounts: Projects and agent workspaces are read-only

### Secret Management

**Secrets Location:** `$HOME/projects/secrets/`
- `alist.env` - AList admin password
- `alist-oauth2.env` - OAuth2 client secret and cookie secret

**Never commit secrets to git:**
- .gitignore configured to exclude secrets/
- No secrets stored in projects/alist directory
- All sensitive data in $HOME/projects/secrets/

### Best Practices

- Keep AList admin password **strong and secure**
- Regularly **update AList** to latest version
- Monitor logs for **suspicious activity**
- Use **read-only mounts** for sensitive directories
- Enable **2FA in Keycloak** for additional security
- Restrict **OAuth2 groups** to authorized users only
- **Never expose** AList directly without OAuth2 proxy
- Keep backend **isolated** on alist-net (not traefik-net)

### Audit Trail

OAuth2 proxy logs all authentication attempts:
```bash
# View authentication logs
docker logs alist-auth-proxy --tail 100 | grep -i auth

# Check for failed login attempts
docker logs alist-auth-proxy | grep -i "unauthorized\|forbidden"

# Monitor access patterns
docker logs alist-auth-proxy | grep -i "GET\|POST"
```

## MCP Integration

AList can be accessed through MCP (Model Context Protocol) for AI integration:

### MCP Filesystem Access

With the `mcp__filesystem` server configured, LLMs can:
- **Read files** from mounted directories
- **List directory contents** via AList mounts
- **Search for files** across projects and agent workspaces
- **Analyze configurations** in project directories
- **Review agent outputs** in claudeagents workspaces

### Example MCP Workflows

**1. Find Project Configurations:**
```
User: "Find all docker-compose.yml files in the projects"
Claude: [Uses MCP filesystem to search /home/administrator/projects/]
```

**2. Analyze Agent Reports:**
```
User: "What reports has the architect agent created?"
Claude: [Searches /home/administrator/data/claudeagents/architect/reports/]
```

**3. Review Deployment Scripts:**
```
User: "Show me the deploy.sh for Keycloak"
Claude: [Reads /home/administrator/projects/keycloak/deploy.sh]
```

**4. Compare Configurations:**
```
User: "Compare OAuth2 config between AList and Obsidian"
Claude: [Reads docker-compose.yml from both projects]
```

### MCP Configuration

To enable MCP access to directories browseable via AList:

1. Ensure MCP filesystem server is running
2. Configure allowed directories:
   - `/home/administrator/projects`
   - `/home/administrator/data/claudeagents`
3. LLMs can now read files that AList exposes
4. Use natural language to search and analyze files

## Naming Convention Compliance

All resources use the name **alist**:
- ✓ Container names: `alist`, `alist-auth-proxy`
- ✓ Project directory: `/home/administrator/projects/alist`
- ✓ Component network: `alist-net`
- ✓ Environment files: `alist.env`, `alist-oauth2.env`
- ✓ Keycloak client: `alist`
- ✓ DNS: `alist.ai-servicers.com`
- ✓ Traefik router: `alist-auth-proxy`
- ✓ Data directory: `/home/administrator/projects/data/alist`

## Related Documentation

- **Keycloak Integration:** `/home/administrator/projects/AINotes/security.md`
- **OAuth2 Proxy Patterns:** Compare with Obsidian, MicroBin, Stirling-PDF
- **Traefik Configuration:** `/home/administrator/projects/traefik/`
- **Backend Isolation Pattern:** See other 3-network deployments
- **AList Official Docs:** https://alist.nn.ci/
- **AList GitHub:** https://github.com/alist-org/alist
- **MCP Filesystem:** `/home/administrator/projects/mcp/filesystem/`

## Changelog

### 2025-10-20 - Initial Deployment

**Completed:**
- [x] Project structure creation
- [x] Environment configuration (alist.env, alist-oauth2.env)
- [x] Keycloak client setup (imported from alist.json)
- [x] Docker Compose configuration with backend isolation (3-network pattern)
- [x] Deployment automation script (deploy.sh)
- [x] OAuth2 authentication via Keycloak (/developers, /administrators groups)
- [x] Traefik integration with Let's Encrypt SSL
- [x] Network topology verification (backend isolated on alist-net)
- [x] Dashy integration (added to Context Management section)
- [x] Project documentation (this file)

**Configuration Fixes Applied:**
- Removed env_file approach, moved all OAuth2 config to docker-compose.yml (matching Obsidian pattern)
- Simplified alist-oauth2.env to only contain CLIENT_SECRET and COOKIE_SECRET
- Added set -a to deploy.sh to export all variables before docker-compose
- Fixed groups format to use leading slashes: `/administrators,/developers`
- Declared all 3 networks in docker-compose.yml (alist-net, keycloak-net, traefik-net)
- Verified environment variables load correctly in container

**Troubleshooting History:**
1. Traefik 404: Health check causing "unhealthy" status → Removed health check
2. Invalid redirect_uri: Missing callback URL in Keycloak → Added redirect URI
3. OAuth2 403: Group format without slashes → Fixed to `/administrators,/developers`
4. Environment not loading: Using env_file with 600 permissions → Switched to docker-compose.yml environment section with variable substitution

**Architecture:**
- External Access: https://alist.ai-servicers.com (SSO required)
- Authentication: Keycloak SSO for external access
- Backend Isolation: AList on alist-net ONLY (not on traefik-net)
- OAuth2 Proxy: 3-network pattern (traefik-net + keycloak-net + alist-net)
- Data: Stored at `/home/administrator/projects/data/alist`
- Mounts: `/mnt/projects` (all projects), `/mnt/claudeagents` (agent workspaces)

**Use Case:**
- Browse infrastructure project files
- Explore agent workspace outputs
- Search and download configurations
- Preview code, docs, and configurations
- Complements Obsidian (note-taking) with AList (file browsing)

**Group Access:**
- `/administrators`: Full access to AList (can configure storages, settings)
- `/developers`: Read-only access to browse mounted directories

---

### 2026-02-05 - Guest Read-Only Access for AI Board Review Links

**Problem:** HTML pages from `/createsolution`, `/createplan`, `/createreview` workflows link to markdown artifacts hosted on alist (e.g., `https://alist.ai-servicers.com/projects/ainotes/shared/createsolution/aiagentchat.final.md`). After Keycloak OAuth2 login, users hit alist's own "token expired" login page because of two-layer authentication.

**Root Cause:** Two layers of auth - Keycloak OAuth2 (external gate) AND alist's own JWT token system. After passing Keycloak, users still needed to login to alist separately. Expired alist tokens in browser localStorage caused "token expired" error.

**Solution Applied:**
1. **`sign_all` → `false`**: Disabled alist URL signing for file downloads. Keycloak OAuth2 is the access gate, so alist's own URL signing is unnecessary. Set via admin API.
2. **`customize_head` script**: Injected JavaScript in alist SPA `<head>` that checks localStorage for expired alist JWT tokens and removes them, forcing the SPA to operate in guest mode. This prevents the "token expired" login page.
3. **Guest user**: Already had `permission: 7` (read access). No changes needed to user permissions.

**Result:** After Keycloak OAuth2 login, users browse alist in guest mode (read-only). Markdown files render as HTML via alist's built-in markdown renderer. No separate alist login required.

**Settings Changed (via alist admin API, persisted in SQLite):**
- `sign_all`: `true` → `false`
- `customize_head`: Added expired-token cleanup script

---

*Document created: 2025-10-20*
*Last updated: 2026-02-05*
*Maintained by: Claude Code*
