#!/usr/bin/env bash
#
# Weekly upstream-tag watcher for paperclipai/paperclip.
#
# Compares the currently pinned git ref (the `#...` fragment in the compose
# file's build.context) against the latest GitHub release tag. If a new tag
# exists, writes a short reminder into the Obsidian vault so Monday-morning
# review surfaces it.
#
# Designed to be run as a Coolify scheduled task on the localhost server (or
# any host with gh + ripgrep available) on `0 9 * * MON`.
#
# Env:
#   OBSIDIAN_VAULT      - path to the Obsidian vault (default: ~/Documents/Obsidian)
#   PAPERCLIP_REPO_DIR  - path to the arodroz/paperclip deploy scaffolding clone
#                        (default: ~/projects/paperclip)
#
# Exits 0 whether or not a new tag was found. Exits non-zero only on tool
# failure (gh unavailable, vault path missing, compose file unreadable).

set -euo pipefail

VAULT="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian}"
REPO="${PAPERCLIP_REPO_DIR:-$HOME/projects/paperclip}"
COMPOSE="${REPO}/docker-compose.yaml"

command -v gh >/dev/null || { echo "gh CLI required" >&2; exit 1; }
[[ -f "$COMPOSE" ]] || { echo "compose not found at $COMPOSE" >&2; exit 1; }
[[ -d "$VAULT" ]]   || { echo "vault not found at $VAULT" >&2; exit 1; }

current_ref=$(grep -oE '#[a-f0-9v.]+' "$COMPOSE" | head -n1 | tr -d '#')
latest_tag=$(gh api repos/paperclipai/paperclip/releases/latest --jq '.tag_name')
latest_sha=$(gh api "repos/paperclipai/paperclip/commits/${latest_tag}" --jq '.sha')

# Treat current_ref as either a tag (vYYYY.MMDD.N) or a commit SHA. If it
# matches either the latest tag name or latest commit sha (full or short),
# we're up to date.
if [[ "$current_ref" == "$latest_tag" ]] || [[ "$latest_sha" == "$current_ref"* ]]; then
  echo "up to date: $current_ref matches latest release $latest_tag"
  exit 0
fi

today=$(date +%F)
note="${VAULT}/Inbox/paperclip-upstream-${today}.md"
mkdir -p "${VAULT}/Inbox"
cat > "$note" <<EOF
---
created: ${today}
tags: [paperclip, upstream-bump]
---

# Paperclip upstream has a newer tag

- Currently pinned: \`${current_ref}\`
- Latest tag: \`${latest_tag}\` (commit \`${latest_sha:0:12}\`)
- Diff: https://github.com/paperclipai/paperclip/compare/${current_ref}...${latest_tag}
- Release notes: https://github.com/paperclipai/paperclip/releases/tag/${latest_tag}

To bump:
1. Edit \`${COMPOSE}\` — change the \`build.context\` ref fragment to \`${latest_tag}\` (or its full SHA).
2. Commit, push to \`arodroz/paperclip\`.
3. Redeploy the Coolify app.
EOF

echo "wrote upgrade note to $note"
