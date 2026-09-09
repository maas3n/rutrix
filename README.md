# rutrix

`rutrix` is a Debian 13 (Trixie) installer and user manager for a minimal rTorrent + ruTorrent seedbox stack.

Maintained by **maas3n**. The rutrix-specific implementation, hardening, release work, and ongoing modifications are Copyright (c) 2026 maas3n. This repository also includes MIT-licensed portions from prior work; the required copyright and permission notice is retained in `LICENSE`.

## Stable release

**rutrix v1.0.0** is the current stable release.

Release: https://github.com/maas3n/rutrix/releases/tag/v1.0.0

## Stack

- rTorrent **0.16.22**
- matching libtorrent **0.16.22**
- pinned upstream SHA-256 verification
- bundled tinyxml2 XMLRPC backend
- latest ruTorrent release available at install time
- nginx + PHP 8.4 FPM
- nginx Basic Auth
- self-signed HTTPS
- one dedicated Unix user, systemd service and Unix-domain SCGI socket per rTorrent instance

## Install

```bash
wget https://raw.githubusercontent.com/maas3n/rutrix/main/rutrix.sh
chmod +x rutrix.sh
sudo ./rutrix.sh
```

After the first install, run:

```bash
sudo rutrix
```

The standalone `rutrix.sh` bootstrap is pinned to a tested rutrix source tree rather than silently installing an arbitrary future revision. When a freshly downloaded standalone wrapper pins a different commit than the currently installed `/etc/rutrix/.release-commit`, rutrix refreshes the installed tree to that pinned commit before running `install-user`.

Before a new Unix user is created or an existing user is modified, rutrix validates the configured APT repositories with `apt-get update`. If an unrelated third-party repository is broken or inconsistent, installation stops before creating a partial rutrix account.

### Safety boundaries

- `/etc/rutrix` is constructed in a staging directory, checked for all required files, forced to `root:root`, and rejected if group/other-writable before it replaces the live install tree. Clone/checkout failures leave the previous tree untouched, and activation has rollback handling.
- A freshly downloaded standalone wrapper compares `/etc/rutrix/.release-commit` with its `BOOTSTRAP_COMMIT`; a valid-but-older installed tree is refreshed before any user installation proceeds.
- rutrix-created accounts record the Unix UID as part of destructive-operation provenance. PURGE refuses a live account whose UID does not match the recorded UID, preventing stale state from authorizing deletion after username reuse.
- Legacy rutrix state that predates UID recording is intentionally not auto-upgraded for PURGE. The installation may continue to run, but destructive deletion is refused when identity cannot be proven.
- Before deleting a home directory, PURGE verifies the canonical path, recorded owner UID, and refuses symbolic links or any mount/submount at or below the home path.
- A rutrix-managed rTorrent service must be confirmed inactive before its unit is removed or account/home deletion proceeds.

## Validated on Debian 13

rutrix v1.0.0 has been tested on a real Debian 13 (Trixie) system, including:

- fresh rutrix-managed user creation
- rTorrent **0.16.22** service start
- ruTorrent connectivity through the per-user Unix-domain SCGI socket
- ruTorrent `env_check.php` with all required checks passing
- XMLRPC mount point `/RPC2`
- actual torrent add/use through ruTorrent
- rTorrent service restart with torrent/session persistence
- uninstall while preserving the Unix account and complete home directory
- state transition from `installed=1` to `installed=0`
- removal of uninstalled users from the uninstall list
- continued purge eligibility for rutrix-created users after uninstall
- guarded purge removing the rutrix-created Unix account, complete home directory and rutrix state
- APT repository preflight before Unix-user creation or modification
- UID-bound purge provenance and username-reuse protection
- mount/submount and canonical-path checks before destructive home removal
- root-owned, staged `/etc/rutrix` replacement with rollback on activation failure
- mandatory rTorrent service-stop verification before teardown
- standalone wrapper refresh of an older valid `/etc/rutrix` tree before user installation

## Menu

```text
rutrix 1.0.0
==============================
1) Install / add a rTorrent user
2) Uninstall a user (keep user home directories)
3) PURGE a user (delete rutrix-created user and entire home directories)
4) Cancel
```

Uninstall removes the selected user's rTorrent/ruTorrent setup while preserving the Unix account and complete home directory.

PURGE is deliberately destructive. It is allowed only when rutrix can prove it created the Unix account and that the current Unix UID still matches the identity recorded by rutrix. The operator must type `purge USER`; rutrix also rejects unexpected paths, symlinks, mounts/submounts, and owner-UID mismatches before deletion.

## Optional arguments

```text
-u USER       dedicated Unix user for rTorrent
-w PASSWORD   nginx/ruTorrent Basic Auth password
-y            non-interactive install; requires -u and -w
--uninstall USER
--uninstall USER --yes
--purge USER
--version
--help
```

PURGE never accepts `--yes`.

Passing a password with `-w` can expose it in shell history and process listings. Interactive password entry is preferred.

## State and installed files

rutrix uses:

```text
/etc/rutrix/
/var/lib/rutrix/users/
/var/lib/rutrix/diagnostic_user
/usr/local/bin/rutrix
```

A rutrix user state file records at least:

```text
user=USER
uid=UID
home=/home/USER
created_by_rutrix=0|1
installed=0|1
```

Each managed rTorrent user gets:

```text
/home/USER/.rtorrent.rc
/home/USER/rtorrent/.session/rpc.sock
/home/USER/rtorrent/download/
/home/USER/rtorrent/watch/
/var/www/rutorrent/conf/users/USER/config.php
/etc/systemd/system/rtorrent-USER.service
```

## rTorrent build verification

The official v0.16.22 release assets are pinned to:

```text
libtorrent-0.16.22.tar.gz
08f6619dcd181ea5d48429ce027888f67a3e14e31135158112d3ec7dcaa240d9

rtorrent-0.16.22.tar.gz
4b157f83d93fd6fd3741a018a7397485dec5c080cbf222b336749b7d5f8f63d6
```

The build uses:

```text
--with-xmlrpc-tinyxml2
```

Useful post-install checks:

```bash
/usr/local/bin/rtorrent -h 2>&1 | head -1
strings /usr/local/bin/rtorrent | grep -F system.listMethods
sudo -u www-data sh -c 'cd /var/www/rutorrent && php env_check.php'
```

## License

MIT. See `LICENSE` for the complete notices and terms.
