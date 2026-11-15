#!/usr/bin/env bash
#
# install.sh — install pi-backup-agent on the Raspberry Pi.
#
#   sudo ./install.sh [ssh-user]        # ssh-user defaults to $SUDO_USER, then "pi"
#
# Installs:  /usr/local/bin/pi-backup-agent
#            /etc/pi-backup/agent.conf            (kept if it already exists)
#            /etc/sudoers.d/pi-backup-agent       (NOPASSWD for that one binary only)
#            /var/lib/pi-backup, /var/cache/restic (0700)
#
set -Eeuo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AGENT_SRC="$HERE/pi-backup-agent"
CONF_SRC="$HERE/agent.conf"
AGENT_DST=/usr/local/bin/pi-backup-agent
CONF_DST=/etc/pi-backup/agent.conf
SUDOERS_DST=/etc/sudoers.d/pi-backup-agent
SSH_USER=${1:-${SUDO_USER:-pi}}

say()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"
[[ $SSH_USER =~ ^[a-z_][a-z0-9_-]*$ ]] || die "invalid user name: $SSH_USER"
id "$SSH_USER" >/dev/null 2>&1 || die "user $SSH_USER does not exist"
[[ -f $AGENT_SRC && -f $CONF_SRC ]] || die "run from the pi/ folder (pi-backup-agent and agent.conf must be next to this script)"

say "Checking dependencies"
if ! command -v jq >/dev/null; then
  say "Installing jq"
  apt-get update -qq && apt-get install -y -qq jq
fi
missing=()
for c in restic rclone systemd-run systemctl flock mountpoint realpath find visudo; do
  command -v "$c" >/dev/null || missing+=("$c")
done
((${#missing[@]} == 0)) || die "missing commands: ${missing[*]} (install restic and rclone first)"
command -v docker >/dev/null || warn "docker not found — database hooks (PostgreSQL, MariaDB, Nextcloud) will not work"
command -v curl >/dev/null || warn "curl not found — failure alerts cannot be sent (sudo apt install curl)"

say "Installing $AGENT_DST"
# New inode + rename: a job that is running keeps reading the old file safely.
install -m 0755 -o root -g root "$AGENT_SRC" "$AGENT_DST.new"
mv -f "$AGENT_DST.new" "$AGENT_DST"

if [[ -f $CONF_DST ]]; then
  say "Keeping existing $CONF_DST (new defaults are in $CONF_SRC)"
else
  say "Installing $CONF_DST"
  install -d -m 0755 -o root -g root /etc/pi-backup
  install -m 0644 -o root -g root "$CONF_SRC" "$CONF_DST"
fi

say "Creating state and cache directories"
install -d -m 0700 -o root -g root /var/lib/pi-backup /var/cache/restic

say "Installing sudoers rule for $SSH_USER"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
printf '# Allow the Pi Backup Remote app to drive backups (that one binary only).\n%s ALL=(root) NOPASSWD: %s\n' \
  "$SSH_USER" "$AGENT_DST" >"$tmp"
visudo -cf "$tmp" >/dev/null || die "generated sudoers file is invalid"
install -m 0440 -o root -g root "$tmp" "$SUDOERS_DST"

[[ -s /root/.restic-pass ]] || warn "/root/.restic-pass is missing — create it before backing up"
[[ -r /root/.config/rclone/rclone.conf ]] || warn "rclone config is missing — run 'sudo rclone config'"

say "Testing: sudo -u $SSH_USER sudo -n $AGENT_DST info"
sudo -u "$SSH_USER" sudo -n "$AGENT_DST" info | jq .
say "Done. In the app: Settings → Test connection."
