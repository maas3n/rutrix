# rutrix

`rutrix` is a Debian 13 (Trixie) installer and user manager for a minimal rTorrent + ruTorrent seedbox stack.

Maintained by **maas3n**. The rutrix-specific implementation, hardening, release work, and ongoing modifications are Copyright (c) 2026 maas3n. This repository also includes MIT-licensed portions from prior work; the required copyright and permission notice is retained in `LICENSE`.

## Stable release

**rutrix v1.0.0** is the current stable release.

Release: https://github.com/maas3n/rutrix/releases/tag/v1.0.0

The v1.0.0 tag targets the validated release commit:

```text
1509a5f4436dc0f0356ff7f231f4bbfe8f9913fd
```

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

The standalone `rutrix.sh` bootstrap is pinned to the tested rutrix release tree rather than silently installing an arbitrary future revision.

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

PURGE is deliberately destructive. It is allowed only when rutrix can prove it created the Unix account. The operator must type `purge USER`, and rutrix verifies both the Unix account and recorded `/home/USER` path are gone before reporting success.

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
