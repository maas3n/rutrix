#!/bin/bash

# rutrix v1.0.0 - Debian 13 rTorrent + ruTorrent installer/user manager.

set -euo pipefail

VERSION="1.0.0"
REPO="maas3n/rutrix"
REPO_URL="https://github.com/${REPO}.git"
BOOTSTRAP_COMMIT="e29b65a5e91c011cb6f3f5559a39dba0b492f4f1"
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")" && pwd)
SELECTED_USER=""
ASSUME_YES=0
STATE_DIR=/var/lib/rutrix/users
DIAGNOSTIC_USER_FILE=/var/lib/rutrix/diagnostic_user

usage() {
  cat <<EOF
rutrix $VERSION

Normal interactive use:
  sudo ./rutrix.sh
  sudo rutrix

The no-argument menu offers:
  1) Install / add a rTorrent user
  2) Uninstall a user (keep user home directories)
  3) PURGE a user (delete rutrix-created user and entire home directories)
  4) Cancel

After choosing Uninstall or PURGE, rutrix asks which eligible rTorrent user
to operate on.

Optional automation shortcuts:
  sudo ./rutrix.sh -u USER
  sudo ./rutrix.sh -y -u USER -w WEB-PASSWORD
  sudo ./rutrix.sh --uninstall USER
  sudo ./rutrix.sh --uninstall USER --yes
  sudo ./rutrix.sh --purge USER

Other:
  ./rutrix.sh --version
  ./rutrix.sh --help

PURGE is always interactive and destructive. It deletes a selected Unix account
only when rutrix has recorded that it created that account, and removes that
account's entire home directory. Pre-existing Unix accounts are never deleted
by PURGE.

Passing a web password with -w can expose it in shell history and process
listings. Prefer the interactive password prompt when possible.
EOF
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Must be run as root or with sudo"
    exit 1
  fi
}

acquire_lock() {
  install -d -m 0750 /var/lib/rutrix
  exec 9>/var/lib/rutrix/lock
  if ! flock -n 9; then
    echo "Another rutrix operation is already running."
    exit 1
  fi
}

valid_user() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]]
}

state_file_for() {
  printf '%s/%s\n' "$STATE_DIR" "$1"
}

state_value() {
  local file=$1
  local key=$2
  [ -r "$file" ] || return 1
  sed -n "s/^${key}=//p" "$file" | head -1
}

state_created_by_rutrix() {
  [ "$(state_value "$1" created_by_rutrix 2>/dev/null || true)" = "1" ]
}

is_managed_service() {
  local unit=$1
  [ -f "$unit" ] || return 1
  grep -q '^# Managed by rutrix$' "$unit"
}

is_installed_user() {
  local user=$1
  local state unit installed
  state=$(state_file_for "$user")
  unit="/etc/systemd/system/rtorrent-$user.service"

  if [ -r "$state" ]; then
    installed=$(state_value "$state" installed 2>/dev/null || true)
    [ "$installed" = "1" ] && return 0
    [ "$installed" = "0" ] && return 1
  fi

  is_managed_service "$unit"
}

is_purgeable_user() {
  local state
  state=$(state_file_for "$1")
  [ -r "$state" ] && state_created_by_rutrix "$state"
}

is_eligible_user() {
  local action=$1
  local user=$2
  case "$action" in
    uninstall) is_installed_user "$user" ;;
    purge) is_purgeable_user "$user" ;;
    *) return 1 ;;
  esac
}

managed_users() {
  local action=$1
  local -A seen=()
  local state_file unit user

  if [ "$action" = "purge" ]; then
    for state_file in "$STATE_DIR"/*; do
      [ -f "$state_file" ] || continue
      state_created_by_rutrix "$state_file" || continue
      user=$(basename "$state_file")
      valid_user "$user" || continue
      if [ -z "${seen[$user]+x}" ]; then
        printf '%s\n' "$user"
        seen[$user]=1
      fi
    done
    return
  fi

  for state_file in "$STATE_DIR"/*; do
    [ -f "$state_file" ] || continue
    user=$(basename "$state_file")
    valid_user "$user" || continue
    is_installed_user "$user" || continue
    if [ -z "${seen[$user]+x}" ]; then
      printf '%s\n' "$user"
      seen[$user]=1
    fi
  done

  for unit in /etc/systemd/system/rtorrent-*.service; do
    is_managed_service "$unit" || continue
    user=$(sed -n 's/^User=//p' "$unit" | head -1)
    [ -n "$user" ] || continue
    valid_user "$user" || continue
    if [ -z "${seen[$user]+x}" ]; then
      printf '%s\n' "$user"
      seen[$user]=1
    fi
  done
}

prompt_user() {
  local action=$1
  local user users

  SELECTED_USER=""
  users=$(managed_users "$action" | sort || true)
  if [ -n "$users" ]; then
    echo
    if [ "$action" = "purge" ]; then
      echo "rutrix-created users eligible for purge:"
    else
      echo "Installed rTorrent users:"
    fi
    while IFS= read -r user; do
      [ -n "$user" ] && echo "  - $user"
    done <<< "$users"
  else
    if [ "$action" = "purge" ]; then
      echo "No rutrix-created users eligible for purge were found."
    else
      echo "No installed rutrix rTorrent users were found."
    fi
    return 1
  fi

  echo
  read -r -p "rTorrent user to $action: " user

  if ! valid_user "$user"; then
    echo "Invalid Unix user name: $user"
    return 1
  fi
  if ! is_eligible_user "$action" "$user"; then
    echo "User '$user' is not eligible for $action."
    return 1
  fi

  SELECTED_USER="$user"
}

write_state_status() {
  local state_file=$1
  local installed=$2
  local tmp

  [ -f "$state_file" ] || return 0
  tmp=$(mktemp "${state_file}.XXXXXX")
  grep -v '^installed=' "$state_file" > "$tmp" || true
  printf 'installed=%s\n' "$installed" >> "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$state_file"
}

create_state_after_uninstall() {
  local user=$1
  local home=$2
  local state_file

  [ -n "$home" ] || return 0
  install -d -m 0750 /var/lib/rutrix "$STATE_DIR"
  state_file=$(state_file_for "$user")
  cat > "$state_file" <<EOF
user=$user
home=$home
created_by_rutrix=0
installed=0
EOF
  chmod 600 "$state_file"
}

php_literal() {
  php -r 'echo var_export($argv[1], true);' "$1"
}

refresh_global_rutorrent_config() {
  [ -d /var/www/rutorrent/conf ] || return 0

  local user="" home top scgi candidate

  if [ -r "$DIAGNOSTIC_USER_FILE" ]; then
    candidate=$(cat "$DIAGNOSTIC_USER_FILE" 2>/dev/null || true)
    if valid_user "$candidate" && is_installed_user "$candidate"; then
      user="$candidate"
    fi
  fi

  if [ -z "$user" ]; then
    user=$(managed_users uninstall | sort | head -1 || true)
  fi

  if [ -z "$user" ]; then
    rm -f /var/www/rutorrent/conf/config.local.php "$DIAGNOSTIC_USER_FILE"
    return 0
  fi

  home=$(getent passwd "$user" | cut -d: -f6 || true)
  if [ -z "$home" ] || [ ! -f "/var/www/rutorrent/conf/users/$user/config.php" ]; then
    rm -f "$DIAGNOSTIC_USER_FILE"
    return 0
  fi

  top=$(php_literal "$home/rtorrent")
  scgi=$(php_literal "unix://$home/rtorrent/.session/rpc.sock")

  cat > /var/www/rutorrent/conf/config.local.php <<EOF
<?php
\$topDirectory = $top;
\$scgi_port = 0;
\$scgi_host = $scgi;
\$localHostedMode = true;
\$profileMask = 0770;
?>
EOF
  chown www-data:rutorrent /var/www/rutorrent/conf/config.local.php 2>/dev/null || true
  chmod 0640 /var/www/rutorrent/conf/config.local.php 2>/dev/null || true
  printf '%s\n' "$user" > "$DIAGNOSTIC_USER_FILE"
  chmod 0640 "$DIAGNOSTIC_USER_FILE"
}

confirm_user_action() {
  local action=$1
  local user=$2
  local home=${3:-}
  local answer

  echo
  if [ "$action" = "purge" ]; then
    echo "DANGER: PURGE will delete the rutrix-created Unix user '$user'"
    echo "and the entire recorded home directory:"
    echo "  $home"
    echo
    read -r -p "Type 'purge $user' to permanently continue: " answer
    if [ "$answer" != "purge $user" ]; then
      echo "Cancelled"
      return 1
    fi
  else
    echo "This will remove rTorrent/ruTorrent access for '$user'."
    echo "The Unix account and the complete home directory will be preserved."
    if [ "$ASSUME_YES" -eq 1 ]; then
      echo "Non-interactive uninstall confirmed by --yes."
      return 0
    fi
    echo
    read -r -p "Type 'uninstall' to continue: " answer
    if [ "$answer" != "uninstall" ]; then
      echo "Cancelled"
      return 1
    fi
  fi
}

remove_user() {
  require_root

  local action=$1
  local user=${2:-}
  local unit service state_file home state_home created account_exists=0

  if [ -z "$user" ]; then
    prompt_user "$action" || return 1
    user="$SELECTED_USER"
  fi

  if ! valid_user "$user"; then
    echo "Invalid Unix user name: $user"
    return 1
  fi
  if ! is_eligible_user "$action" "$user"; then
    echo "User '$user' is not eligible for $action."
    return 1
  fi

  state_file=$(state_file_for "$user")
  unit="/etc/systemd/system/rtorrent-$user.service"
  service="rtorrent-$user.service"
  home=""
  state_home=""
  created=0

  if [ -r "$state_file" ]; then
    state_home=$(state_value "$state_file" home 2>/dev/null || true)
    state_created_by_rutrix "$state_file" && created=1
  fi

  if id "$user" >/dev/null 2>&1; then
    account_exists=1
    home=$(getent passwd "$user" | cut -d: -f6 || true)
  elif [ "$action" = "purge" ]; then
    home="$state_home"
  fi

  if [ -f "$unit" ] && ! is_managed_service "$unit"; then
    echo "Refusing to modify $unit because it lacks the '# Managed by rutrix' marker."
    return 1
  fi

  if [ "$action" = "purge" ]; then
    if [ "$created" -ne 1 ]; then
      echo "Refusing to purge '$user'."
      echo "rutrix cannot prove that it created this Unix account."
      return 1
    fi
    if [ "$state_home" != "/home/$user" ]; then
      echo "Refusing to purge '$user': recorded home '$state_home' is unexpected."
      return 1
    fi
    if [ "$account_exists" -eq 1 ] && [ "$home" != "$state_home" ]; then
      echo "Refusing to purge '$user': live home '$home' does not match recorded home '$state_home'."
      return 1
    fi
    home="$state_home"
  else
    [ -n "$home" ] || home="$state_home"
  fi

  confirm_user_action "$action" "$user" "$home" || return 1

  if is_managed_service "$unit"; then
    systemctl disable --now "$service" >/dev/null 2>&1 || true
    rm -f "$unit"
    systemctl daemon-reload
  fi

  if [ -f /etc/nginx/.htpasswd-rutorrent ]; then
    htpasswd -D /etc/nginx/.htpasswd-rutorrent "$user" >/dev/null 2>&1 || true
  fi
  rm -rf "/var/www/rutorrent/conf/users/$user"

  if [ -n "$home" ] && [ -d "$home" ]; then
    setfacl -x g:rutorrent "$home" >/dev/null 2>&1 || true
  fi
  if getent group rutorrent >/dev/null 2>&1 && id "$user" >/dev/null 2>&1; then
    gpasswd -d "$user" rutorrent >/dev/null 2>&1 || true
  fi

  if [ "$action" = "purge" ]; then
    if [ "$account_exists" -eq 1 ]; then
      echo "Purging rutrix-created user $user and $home"
      deluser --remove-home "$user"
      if id "$user" >/dev/null 2>&1; then
        echo "Purge failed: Unix user '$user' still exists"
        return 1
      fi
    else
      echo "Unix user '$user' is already absent; cleaning recorded rutrix home/state."
    fi

    if [ -d "$home" ]; then
      echo "Removing remaining home directory $home"
      rm -rf -- "$home"
    fi
    if [ -e "$home" ]; then
      echo "Purge failed: home path still exists: $home"
      return 1
    fi

    rm -f "$state_file"
  else
    if [ -f "$state_file" ]; then
      write_state_status "$state_file" 0
    else
      create_state_after_uninstall "$user" "$home"
    fi
    echo "Uninstalled rTorrent/ruTorrent for $user"
    echo "Preserved Unix user and home directory: $home"
  fi

  if [ -r "$DIAGNOSTIC_USER_FILE" ] && [ "$(cat "$DIAGNOSTIC_USER_FILE" 2>/dev/null || true)" = "$user" ]; then
    rm -f "$DIAGNOSTIC_USER_FILE"
  fi
  refresh_global_rutorrent_config

  if command -v nginx >/dev/null 2>&1 && nginx -t >/dev/null 2>&1; then
    systemctl reload nginx >/dev/null 2>&1 || true
  fi

  echo
  if [ "$action" = "purge" ]; then
    echo "User purge complete: $user"
  else
    echo "User uninstall complete: $user"
  fi
}

valid_commit() {
  [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

clone_installer_tree() {
  local commit=$1
  local actual

  apt-get -qq update
  apt-get -yqq install git ca-certificates >/dev/null
  rm -rf /etc/rutrix
  git clone -q "$REPO_URL" /etc/rutrix

  if [ -n "$commit" ]; then
    git -C /etc/rutrix checkout -q "$commit"
    actual=$(git -C /etc/rutrix rev-parse HEAD)
    if [ "$actual" != "$commit" ]; then
      echo "Release verification failed: expected $commit, got $actual"
      rm -rf /etc/rutrix
      exit 1
    fi
    printf '%s\n' "$commit" > /etc/rutrix/.release-commit
    chmod 0644 /etc/rutrix/.release-commit
  else
    echo "WARNING: no release commit is pinned; using current main development code."
    git -C /etc/rutrix checkout -q main
  fi

  rm -rf /etc/rutrix/.git
}

prepare_install_tree() {
  require_root

  local local_commit=""

  if [ -f "$SCRIPT_DIR/scripts/install-user" ] && [ -f "$SCRIPT_DIR/conf/rtorrent.rc" ]; then
    if [ "$SCRIPT_DIR" != "/etc/rutrix" ]; then
      rm -rf /etc/rutrix
      install -d -m 0755 /etc/rutrix
      cp -a "$SCRIPT_DIR/rutrix.sh" /etc/rutrix/
      cp -a "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/conf" /etc/rutrix/
      for extra in README.md LICENSE VERSION; do
        [ -e "$SCRIPT_DIR/$extra" ] && cp -a "$SCRIPT_DIR/$extra" /etc/rutrix/
      done

      if [ -d "$SCRIPT_DIR/.git" ]; then
        local_commit=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || true)
      fi
      if valid_commit "$local_commit"; then
        printf '%s\n' "$local_commit" > /etc/rutrix/.release-commit
      elif valid_commit "$BOOTSTRAP_COMMIT"; then
        printf '%s\n' "$BOOTSTRAP_COMMIT" > /etc/rutrix/.release-commit
      fi
    fi
  elif [ ! -f /etc/rutrix/scripts/install-user ]; then
    clone_installer_tree "$BOOTSTRAP_COMMIT"
  fi

  chmod 755 /etc/rutrix/rutrix.sh /etc/rutrix/scripts/install-user 2>/dev/null || true
  chmod 755 /etc/rutrix/scripts/install-rtorrent-0.16.22 2>/dev/null || true
  ln -sfn /etc/rutrix/rutrix.sh /usr/local/bin/rutrix
}

run_install() {
  prepare_install_tree
  exec bash /etc/rutrix/scripts/install-user "$@"
}

interactive_menu() {
  require_root
  local choice

  while true; do
    echo
    echo "rutrix $VERSION"
    echo "=============================="
    echo "1) Install / add a rTorrent user"
    echo "2) Uninstall a user (keep user home directories)"
    echo "3) PURGE a user (delete rutrix-created user and entire home directories)"
    echo "4) Cancel"
    echo
    read -r -p "Choose [1-4]: " choice

    case "$choice" in
      1) run_install ;;
      2) remove_user uninstall; return ;;
      3) remove_user purge; return ;;
      4) echo "Cancelled"; return ;;
      *) echo "Invalid choice" ;;
    esac
  done
}

parse_uninstall() {
  shift
  local user=${1:-}
  [ -n "$user" ] && shift || true

  if [ "${1:-}" = "--yes" ] && [ "$#" -eq 1 ]; then
    ASSUME_YES=1
  elif [ "$#" -ne 0 ]; then
    echo "Unknown uninstall option: ${1:-}"
    usage
    exit 1
  fi

  remove_user uninstall "$user"
}

parse_purge() {
  shift
  local user=${1:-}
  [ -n "$user" ] && shift || true

  if [ "$#" -ne 0 ]; then
    echo "PURGE does not accept additional options."
    usage
    exit 1
  fi

  remove_user purge "$user"
}

if [ "$#" -eq 0 ]; then
  require_root
  acquire_lock
  interactive_menu
  exit 0
fi

case "$1" in
  --version)
    echo "rutrix $VERSION"
    ;;
  --help|-h)
    usage
    ;;
  --uninstall)
    require_root
    acquire_lock
    parse_uninstall "$@"
    ;;
  --purge|--purge-data)
    require_root
    acquire_lock
    parse_purge "$@"
    ;;
  -u|-w|-y)
    require_root
    acquire_lock
    run_install "$@"
    ;;
  --*|-*)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
  *)
    echo "Unexpected argument: $1"
    usage
    exit 1
    ;;
esac
