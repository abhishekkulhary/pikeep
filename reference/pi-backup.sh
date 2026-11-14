#!/usr/bin/env bash
#
# pi-backup — on-demand, encrypted, versioned backup of Immich + Nextcloud
#             from the Pi's SSD to OneDrive (restic, using rclone as transport).
#
# Usage:
#   sudo pi-backup init                 # create the encrypted repository (once)
#   sudo pi-backup                      # back up Immich + Nextcloud
#   sudo pi-backup --only immich        # back up only one service
#   sudo pi-backup --only nextcloud
#   sudo pi-backup --prune              # also apply retention + free space on OneDrive
#   sudo pi-backup --check              # also verify a random 5% of the stored data
#   sudo pi-backup --dry-run            # show what would be uploaded, change nothing
#   sudo pi-backup restic <args...>     # run any restic command against the repo
#                                       #   e.g. sudo pi-backup restic snapshots
#
set -Eeuo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
export RESTIC_REPOSITORY="rclone:onedrive:pi-backup"   # <rclone remote>:<folder>
export RESTIC_PASSWORD_FILE="/root/.restic-pass"
export RCLONE_CONFIG="/root/.config/rclone/rclone.conf"

SSD_MOUNT="/mnt/ssd"

IMMICH_APP="/mnt/ssd/immich/app"          # docker-compose.yml + .env
IMMICH_LIB="/mnt/ssd/immich/library"      # UPLOAD_LOCATION
IMMICH_DB_CONTAINER="immich_postgres"

NC_APP="/mnt/ssd/nextcloud/app"           # docker-compose.yml + .env
NC_HTML="/mnt/ssd/nextcloud/html"
NC_DATA="/mnt/ssd/nextcloud/data"
NC_APP_CONTAINER="nextcloud_app"
NC_DB_CONTAINER="nextcloud_db"

STAGING="/mnt/ssd/backup-staging"         # database dumps are written here first
LOG_FILE="/var/log/pi-backup.log"
LOCK_FILE="/run/pi-backup.lock"

# Retention (applied only with --prune)
KEEP_LAST=7
KEEP_MONTHLY=6

# Larger packs = fewer files on OneDrive = fewer API calls / less throttling
BACKUP_OPTS=(--pack-size 64 --exclude-caches)

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
log()  { echo "[$(date '+%F %T')] $*"; }
die()  { log "ERROR: $*"; exit 1; }
occ()  { docker exec -u www-data "$NC_APP_CONTAINER" php occ "$@"; }

usage() { sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

NC_MAINTENANCE=0
cleanup() {
  local rc=$?
  if [[ $NC_MAINTENANCE -eq 1 ]]; then
    log "Turning Nextcloud maintenance mode OFF"
    occ maintenance:mode --off >/dev/null || log "WARNING: could not disable maintenance mode — run: docker exec -u www-data $NC_APP_CONTAINER php occ maintenance:mode --off"
  fi
  rm -f "$STAGING"/*.tmp 2>/dev/null || true
  if [[ $rc -eq 0 ]]; then log "Done."; else log "FAILED (exit $rc)"; fi
}

preflight() {
  [[ $EUID -eq 0 ]] || die "run with sudo (Nextcloud data is only readable by root)"
  for c in restic rclone docker flock mountpoint; do
    command -v "$c" >/dev/null || die "'$c' is not installed"
  done
  mountpoint -q "$SSD_MOUNT" || die "$SSD_MOUNT is not mounted — refusing to back up an empty directory"
  [[ -s $RESTIC_PASSWORD_FILE ]] || die "password file $RESTIC_PASSWORD_FILE missing"
  mkdir -p "$STAGING"
  chmod 700 "$STAGING"
}

# ----------------------------------------------------------------------------
# Backup steps
# ----------------------------------------------------------------------------
backup_immich() {
  log "=== Immich ==="
  docker inspect -f '{{.State.Running}}' "$IMMICH_DB_CONTAINER" 2>/dev/null | grep -q true \
    || die "$IMMICH_DB_CONTAINER is not running"

  # Database first, files second (Immich's recommended order: files added after
  # the dump just become orphans on restore, nothing is lost or corrupted).
  log "Dumping Immich database"
  docker exec "$IMMICH_DB_CONTAINER" sh -c \
    'pg_dumpall --clean --if-exists --username="$POSTGRES_USER"' \
    > "$STAGING/immich-db.sql.tmp"
  [[ -s "$STAGING/immich-db.sql.tmp" ]] || die "Immich database dump is empty"
  mv "$STAGING/immich-db.sql.tmp" "$STAGING/immich-db.sql"

  log "Uploading Immich (originals, profile pics, config, DB dump)"
  restic backup "${BACKUP_OPTS[@]}" "${DRY[@]}" --tag immich \
    --exclude "$IMMICH_LIB/thumbs" \
    --exclude "$IMMICH_LIB/encoded-video" \
    "$IMMICH_LIB" \
    "$IMMICH_APP" \
    "$STAGING/immich-db.sql"
}

backup_nextcloud() {
  log "=== Nextcloud ==="
  docker inspect -f '{{.State.Running}}' "$NC_DB_CONTAINER" 2>/dev/null | grep -q true \
    || die "$NC_DB_CONTAINER is not running"

  # Maintenance mode keeps files and database consistent with each other.
  # Sync clients simply pause and retry until it is switched off again.
  log "Turning Nextcloud maintenance mode ON"
  occ maintenance:mode --on >/dev/null
  NC_MAINTENANCE=1

  log "Dumping Nextcloud database"
  docker exec "$NC_DB_CONTAINER" sh -c \
    'exec mariadb-dump --single-transaction --default-character-set=utf8mb4 -u root -p"$MARIADB_ROOT_PASSWORD" nextcloud' \
    > "$STAGING/nextcloud-db.sql.tmp"
  [[ -s "$STAGING/nextcloud-db.sql.tmp" ]] || die "Nextcloud database dump is empty"
  mv "$STAGING/nextcloud-db.sql.tmp" "$STAGING/nextcloud-db.sql"

  log "Uploading Nextcloud (user files, config, apps, DB dump)"
  restic backup "${BACKUP_OPTS[@]}" "${DRY[@]}" --tag nextcloud \
    --exclude "$NC_DATA/appdata_*/preview" \
    --exclude "$NC_DATA/*/uploads" \
    --exclude "$NC_DATA/*/cache" \
    --exclude "$NC_DATA/nextcloud.log*" \
    --exclude "$NC_DATA/updater-*" \
    "$NC_DATA" \
    "$NC_HTML/config" \
    "$NC_HTML/custom_apps" \
    "$NC_HTML/themes" \
    "$NC_APP" \
    "$STAGING/nextcloud-db.sql"

  log "Turning Nextcloud maintenance mode OFF"
  occ maintenance:mode --off >/dev/null
  NC_MAINTENANCE=0
}

apply_retention() {
  log "=== Retention: keep last $KEEP_LAST + $KEEP_MONTHLY monthly, then prune ==="
  restic forget --group-by host,tags \
    --keep-last "$KEEP_LAST" --keep-monthly "$KEEP_MONTHLY" --prune
}

verify() {
  log "=== Verifying repository (structure + random 5% of data) ==="
  restic check --read-data-subset=5%
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
ONLY="all"; DO_PRUNE=0; DO_CHECK=0; DRY=()

case "${1:-}" in
  -h|--help) usage 0 ;;
  init)
    preflight
    log "Creating encrypted repository at $RESTIC_REPOSITORY"
    restic init
    log "Repository created. Keep a copy of $RESTIC_PASSWORD_FILE somewhere OFF this Pi."
    exit 0 ;;
  restic)
    shift; preflight; exec restic "$@" ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)    ONLY="${2:-}"; [[ $ONLY == immich || $ONLY == nextcloud ]] || usage 1; shift 2 ;;
    --prune)   DO_PRUNE=1; shift ;;
    --check)   DO_CHECK=1; shift ;;
    --dry-run) DRY=(--dry-run); shift ;;
    *)         usage 1 ;;
  esac
done

preflight

exec 9>"$LOCK_FILE"
flock -n 9 || die "another backup is already running"

exec > >(tee -a "$LOG_FILE") 2>&1
trap cleanup EXIT

log "Starting backup (only=$ONLY prune=$DO_PRUNE check=$DO_CHECK ${DRY[*]:-})"

# Fail fast — before touching maintenance mode — if OneDrive or the repo is unreachable
restic cat config >/dev/null || die "cannot open repository on OneDrive (network, rclone token, or password?)"

[[ $ONLY == all || $ONLY == immich    ]] && backup_immich
[[ $ONLY == all || $ONLY == nextcloud ]] && backup_nextcloud
[[ $DO_PRUNE -eq 1 && ${#DRY[@]} -eq 0 ]] && apply_retention
[[ $DO_CHECK -eq 1 ]] && verify

log "=== Snapshots ==="
restic snapshots --latest 1 --group-by tags
log "=== Space used on OneDrive ==="
restic stats --mode raw-data | grep -E 'Total Size|Total Blob Count' || true
