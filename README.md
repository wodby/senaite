# SENAITE Docker Container Image

[![Build Status](https://github.com/wodby/senaite/workflows/Build%20docker%20image/badge.svg)](https://github.com/wodby/senaite/actions)
[![Docker Pulls](https://img.shields.io/docker/pulls/wodby/senaite.svg)](https://hub.docker.com/r/wodby/senaite)

[SENAITE LIMS](https://www.senaite.com) on Plone 5.2 and Python 2.7, built once with buildout and every package
pinned. One image runs both the ZEO server that holds the database and the uploaded files, and the SENAITE clients
that serve the site. It includes SENAITE's security hotfix for
[CVE-2026-54569](https://github.com/senaite/senaite.core/security/advisories/GHSA-jrw6-7x4q-w25j)
(`SenaiteHotfix20260602`), a command that creates the site or upgrades it, and a regular `wodby` user (uid 1000).

## Docker Images

❗For better reliability we release images with stability tags (`wodby/senaite:2.6-rN`) which correspond to
[git tags](https://github.com/wodby/senaite/releases). We strongly recommend using images only with stability tags.

- Base image: [ubuntu](https://hub.docker.com/_/ubuntu) 22.04, pinned by digest
- [GitHub actions builds](https://github.com/wodby/senaite/actions)
- [Docker Hub](https://hub.docker.com/r/wodby/senaite)

Supported tags:

| Tag             | SENAITE |
|-----------------|---------|
| `2.6`, `latest` | 2.6.x   |

All images are built for `linux/amd64` and `linux/arm64`.

SENAITE 2.x needs Python 2.7, which no longer gets fixes from the Python project. Ubuntu 22.04 still ships Python
2.7 with security updates and current system libraries; vulnerability scans still report findings in Python 2
packages.

## Running

Start a ZEO server with a volume on `/data`, then any number of SENAITE clients pointed at it:

```bash
docker network create senaite
docker run -d --name zeo --network senaite -v senaite-data:/data wodby/senaite:2.6 zeo
docker run -d --name senaite --network senaite -e ZEO_ADDRESS=zeo:8100 -p 8080:8080 wodby/senaite:2.6
docker exec -e SENAITE_ADMIN_PASSWORD='a long password' senaite senaite-update
```

The site is served at the root of the domain: each request is rewritten to the site at `/senaite` with the scheme
from `X-Forwarded-Proto` and the `Host` header, so links use the public address behind a TLS-terminating proxy. The
client address in the access log comes from the last `X-Forwarded-For` entry. Zope's root and its management
interface are not reachable this way. `/.healthz` answers from Zope's root, before the site exists.

The root file system can be read-only; the containers write only to `/data` (ZEO server), `/var/cache/senaite`
and `/tmp`.

## Environment variables

| Variable                 | Default                         | Description                                                    |
|--------------------------|---------------------------------|----------------------------------------------------------------|
| `ZEO_ADDRESS`            |                                 | The ZEO server, `host:port`. Required for clients              |
| `ZODB_CACHE_SIZE`        | `30000`                         | Objects cached per database connection (one per thread)        |
| `ZEO_CLIENT_CACHE_SIZE`  | `128MB`                         | The ZEO client's object cache                                  |
| `ZEO_BLOB_CACHE_SIZE`    | `1073741824`                    | Bytes of uploaded files cached by a client                     |
| `SENAITE_BLOB_CACHE`     | `/var/cache/senaite/blobcache`  | Where a client caches uploaded files                           |
| `SENAITE_ADMIN_USERNAME` | `admin`                         | `senaite-update`: the administrator created with the site      |
| `SENAITE_ADMIN_PASSWORD` |                                 | `senaite-update`: their password, at least 12 characters       |
| `SENAITE_ADMIN_EMAIL`    |                                 | `senaite-update`: their email address                          |
| `SENAITE_LANGUAGE`       | `en`                            | `senaite-update`: the site's language                          |
| `SENAITE_TIMEZONE`       | `UTC`                           | `senaite-update`: the site's time zone                         |
| `SENAITE_SITE_TITLE`     | `SENAITE LIMS`                  | `senaite-update`: the site's title                             |
| `SENAITE_EMAIL_FROM`     |                                 | `senaite-update`: the sender address, when none is set         |
| `SMTP_HOST`, `SMTP_PORT` |                                 | `senaite-update`: the mail server, see below                   |

## Commands

| Command                       | Runs in    | Description                                                                 |
|-------------------------------|------------|-----------------------------------------------------------------------------|
| `zeo`                         | Server     | Starts the ZEO server on port 8100                                          |
| `start` (default)             | Client     | Starts SENAITE on port 8080                                                 |
| `senaite-update`              | Client     | Creates the site on an empty database, or upgrades it                       |
| `senaite-pack [DAYS]`         | Client     | Packs the database on the ZEO server, keeping `DAYS` of history (7)         |
| `senaite-backup FILE.tar.gz`  | Server     | Writes a backup of the database and the files while the server runs        |

`senaite-update` connects to the ZEO server as one more client, so SENAITE keeps serving while it runs:

- On an empty database, it creates the site with SENAITE's profile, the language and time zone, and an
  administrator: a site user with the Manager role. A missing or short password stops it before anything is created.
  The sign-in cookie is set to be sent only over HTTPS. Zope's root gets no user.
- On later runs, it applies Plone's migration and the pending upgrade steps of every installed add-on. The
  administrator settings are not used again.
- With `SMTP_HOST`, it sets the site's mail server while the site still has Plone's default (`localhost`) or the
  server it set before; a server entered in SENAITE's mail settings is kept. `SENAITE_EMAIL_FROM` is set as the
  sender when the site has none.

`senaite-backup` copies `Data.fs` up to its last committed transaction with Zope's `repozo` and adds the
blobstorage. To restore, stop the server and unpack the archive into an empty `/data`.
