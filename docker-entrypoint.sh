#!/usr/bin/env bash

set -e

if [[ -n "${DEBUG}" ]]; then
    set -x
fi

mkdir -p /var/cache/senaite/instance /var/cache/senaite/chameleon "${SENAITE_BLOB_CACHE}"

case "${1}" in
    # The ZEO server: SENAITE's database and files on /data.
    zeo)
        mkdir -p /data/filestorage /data/blobstorage
        exec /opt/senaite/parts/zeoserver/bin/runzeo
        ;;
    # A SENAITE client of the ZEO server at ZEO_ADDRESS.
    start)
        if [[ -z "${ZEO_ADDRESS}" ]]; then
            echo >&2 "Error: ZEO_ADDRESS is not set: SENAITE needs the address of its ZEO server, such as senaite-zeo:8100."
            exit 1
        fi
        exec /opt/senaite/bin/instance console
        ;;
esac

exec "${@}"
