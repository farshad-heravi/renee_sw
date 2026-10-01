#!/usr/bin/env bash
# The simulation container (docker-compose.yaml) runs as `robot` (uid/gid
# 1000), and volume-mounts this whole directory read-write. On hosts where
# uid 1000 happens to resolve to a different local account than the one
# running this script (e.g. a leftover pre-domain-join account), any file
# the container creates ends up owned by that account with mode 644/755 —
# unreadable/unwritable from the host afterwards.
#
# This grants the current host user a standing ACL on the whole tree: an
# immediate fix for files the container already created, plus a default ACL
# so files/dirs the container creates from now on are covered automatically.
# ACLs live on the filesystem (ext4 xattrs), not in git, so re-run this after
# a fresh clone or OS reinstall.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_USER="$(id -un)"

sudo setfacl -R -m "u:${HOST_USER}:rwX" "$SCRIPT_DIR"
sudo setfacl -R -d -m "u:${HOST_USER}:rwX" "$SCRIPT_DIR"

echo "ACLs granted to ${HOST_USER} on ${SCRIPT_DIR} (existing files + default for future ones)."
