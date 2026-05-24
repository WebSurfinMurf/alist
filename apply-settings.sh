#!/bin/bash
# Re-applies alist runtime settings that are stored in SQLite (not git).
# Idempotent. Called from deploy.sh; safe to run standalone.
#
# What this enforces:
#   - customize_head: contents of assets/customize_head.html
#                     (token cleanup script for guest mode after Keycloak SSO)
#   - sign_all:       false  (no per-URL signatures; OAuth2 is the access gate)
#
# Why: alist UI lets admins edit these settings, but they're stored only in
# data.db with no source-of-truth file. Drift caused 2026-05-09 outage where
# a redundant external-viewer redirect was added on top of alist's native
# markdown renderer (which already supports mermaid/katex/gfm).

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEAD_FILE="$SCRIPT_DIR/assets/customize_head.html"

if [ ! -f "$HEAD_FILE" ]; then
    echo -e "${RED}Missing $HEAD_FILE${NC}"
    exit 1
fi

if [ -z "${ALIST_ADMIN_PASSWORD:-}" ]; then
    if [ -f "$HOME/projects/secrets/alist.env" ]; then
        # shellcheck disable=SC1090
        source "$HOME/projects/secrets/alist.env"
    fi
fi

if [ -z "${ALIST_ADMIN_PASSWORD:-}" ]; then
    echo -e "${RED}ALIST_ADMIN_PASSWORD not set${NC}"
    exit 1
fi

echo -e "${YELLOW}Applying alist runtime settings (customize_head, sign_all)...${NC}"

export ALIST_ADMIN_PASSWORD HEAD_FILE
python3 - <<'PYEOF'
import json, os, subprocess, sys

password = os.environ['ALIST_ADMIN_PASSWORD']
head_path = os.environ['HEAD_FILE']
with open(head_path) as f:
    head_value = f.read()

def alist_api(path, body=None, token=None):
    cmd = ['docker', 'exec', '-i', 'alist', 'wget', '-qO-',
           '--header', 'Content-Type: application/json']
    if token:
        cmd += ['--header', f'Authorization: {token}']
    if body is not None:
        cmd += ['--post-data', body]
    cmd += [f'http://localhost:5244{path}']
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"FAIL: wget exit={r.returncode} stderr={r.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(r.stdout)

login = alist_api('/api/auth/login',
                  json.dumps({'username': 'admin', 'password': password}))
if login.get('code') != 200:
    print(f"FAIL: login {login}", file=sys.stderr); sys.exit(1)
token = login['data']['token']

settings = [
    {'key': 'customize_head', 'value': head_value, 'type': 'text', 'flag': 2, 'group': 3},
    {'key': 'sign_all',        'value': 'false',   'type': 'bool', 'flag': 0, 'group': 1},
]
resp = alist_api('/api/admin/setting/save', json.dumps(settings), token=token)
if resp.get('code') != 200:
    print(f"FAIL: save {resp}", file=sys.stderr); sys.exit(1)

# Verify by reading public settings (what the SPA actually sees)
public = alist_api('/api/public/settings')
got_head = public['data'].get('customize_head', '')
got_sign = public['data'].get('sign_all', '')
ok = (got_head == head_value) and (got_sign == 'false')
print(f"customize_head: {len(got_head)} bytes, sign_all={got_sign}, match={ok}")
sys.exit(0 if ok else 1)
PYEOF

echo -e "${GREEN}✓ alist settings applied${NC}"
