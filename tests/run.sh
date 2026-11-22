#!/usr/bin/env bash

# Runs the image as the SENAITE stack does: a ZEO server with a data volume
# and a SENAITE client. Checks the health endpoint before the site exists,
# that a short admin password is refused, the site creation, the public links,
# signing in, the JSON API and the security hotfix, blobs across ZEO
# clients, packing, a backup restored into a new ZEO server and a second run
# of senaite-update.

set -e

if [[ -n "${DEBUG}" ]]; then
    set -x
fi

network="${NAME}-net"
data="${NAME}-data"
zeo="${NAME}-zeo"
app="${NAME}-app"
admin_password="Adm1n p'a#{s}s/w:rd"
backup_dir=$(mktemp -d)

cleanup() {
    local status=$?
    if [[ "${status}" -ne 0 ]]; then
        docker logs --tail 50 "${zeo}" 2>&1 || true
        docker logs --tail 80 "${app}" 2>&1 || true
    fi
    docker rm -vf "${app}" "${zeo}" > /dev/null 2>&1 || true
    docker volume rm -f "${data}" > /dev/null 2>&1 || true
    docker network rm "${network}" > /dev/null 2>&1 || true
    rm -rf "${backup_dir}"
    exit "${status}"
}
trap cleanup EXIT

expect() {
    local description=$1 actual=$2 expected=$3
    echo -n "${description}... "
    if [[ "${actual}" != *"${expected}"* ]]; then
        echo "Error: expected ${expected}, got: ${actual}"
        exit 1
    fi
    echo "OK"
}

wait_healthy() {
    for _ in $(seq 1 100); do
        if [[ "$(docker exec "${app}" python2.7 /usr/local/share/wodby-tests/http.py status /.healthz 2>/dev/null)" == "200" ]]; then
            return 0
        fi
        sleep 3
    done
    echo "Error: SENAITE did not become healthy"
    exit 1
}

update() {
    docker exec "${@}" "${app}" senaite-update 2>&1
}

docker network create "${network}" > /dev/null
docker volume create "${data}" > /dev/null
docker run -d --name "${zeo}" --network "${network}" -v "${data}:/data" "${IMAGE}" zeo > /dev/null
docker run -d --name "${app}" --network "${network}" -e ZEO_ADDRESS="${zeo}:8100" "${IMAGE}" > /dev/null
docker cp http.py "${app}:/tmp/http.py"
docker exec -u 0 "${app}" install -D -m 0644 /tmp/http.py /usr/local/share/wodby-tests/http.py
http() {
    docker exec "${app}" python2.7 /usr/local/share/wodby-tests/http.py "${@}"
}

wait_healthy
expect "Health check answers before the site exists" "$(http status /.healthz)" "200"
expect "No site yet" "$(http status /)" "404"

out=$(update -e SENAITE_ADMIN_PASSWORD=short || true)
expect "A short admin password is refused" "${out}" "the admin password must have at least 12 characters"
expect "Still no site" "$(http status /)" "404"

out=$(update \
    -e SENAITE_ADMIN_USERNAME=owner \
    -e SENAITE_ADMIN_PASSWORD="${admin_password}" \
    -e SENAITE_ADMIN_EMAIL=owner@example.com \
    -e SENAITE_EMAIL_FROM=noreply@senaite.example.com \
    -e SENAITE_TIMEZONE=Europe/Berlin \
    -e SMTP_HOST=opensmtpd \
    -e SMTP_PORT=25)
expect "senaite-update creates the administrator" "${out}" "created the administrator owner"
expect "senaite-update creates the site" "${out}" "creating the site (language en, time zone Europe/Berlin)"
expect "senaite-update points mail at the link" "${out}" "set the mail server to the linked SMTP service"
expect "senaite-update finishes" "${out}" "senaite-update: done"

expect "The site answers at the root and redirects to sign in over HTTPS" "$(http location /)" "https://senaite.example.com/login"
expect "Pages link to the public HTTPS address" "$(http links /login)" "https=yes http=no"
expect "The admin signs in" "$(http login owner "${admin_password}")" "302 https://senaite.example.com secure=yes"
expect "A wrong password is refused" "$(http login owner wrong-password)" "200"
expect "The JSON API answers the admin" "$(http api owner "${admin_password}" /@@API/senaite/v1/version)" "\"version\": \"${SENAITE_VER}\""
# The routes CVE-2026-54569 reached without the permission.
expect "Anonymous changes through the legacy JSON API are refused" "$(http anon-post /@@API/update)" "Access JSON API' permission"
expect "The client address comes from X-Forwarded-For" "$(docker logs "${app}" 2>&1 | grep -m1 '^203.0.113.7 - owner ' || true)" "203.0.113.7 - owner"

docker cp hotfix.py "${app}:/tmp/hotfix.py"
expect "The SENAITE hotfix replaces eval in the JSON API" \
    "$(docker exec -e SENAITE_BLOB_CACHE=/tmp/blobs-hotfix "${app}" /opt/senaite/bin/instance run /tmp/hotfix.py 2>&1 | tail -1)" \
    "hotfix active"

docker cp blob.py "${app}:/tmp/blob.py"
expect "A blob is written through ZEO" \
    "$(docker exec -e SENAITE_BLOB_CACHE=/tmp/blobs-a "${app}" /opt/senaite/bin/instance run /tmp/blob.py write 2>&1 | tail -1)" \
    "blob written"

expect "senaite-pack packs the database from a SENAITE container" \
    "$(docker exec "${app}" senaite-pack 0 2>&1 | tail -1)" \
    "senaite-pack: done"

expect "senaite-backup writes a backup while ZEO runs" \
    "$(docker exec "${zeo}" senaite-backup /tmp/backup/senaite.tar.gz 2>&1 | tail -1)" \
    "Backup written to /tmp/backup/senaite.tar.gz"
listing=$(docker exec "${zeo}" tar -tzf /tmp/backup/senaite.tar.gz)
expect "The backup has the database" "${listing}" "filestorage/Data.fs"
expect "The backup has the files" "${listing}" ".blob"
docker cp "${zeo}:/tmp/backup/senaite.tar.gz" "${backup_dir}/senaite.tar.gz"

# Restores the backup into a new volume and replaces the ZEO server with one
# that uses it, then restarts SENAITE.
docker rm -vf "${zeo}" > /dev/null
docker volume rm -f "${data}" > /dev/null
docker volume create "${data}" > /dev/null
docker run --rm -v "${data}:/data" -v "${backup_dir}:/backup:ro" "${IMAGE}" tar -xzf /backup/senaite.tar.gz -C /data
docker run -d --name "${zeo}" --network "${network}" -v "${data}:/data" "${IMAGE}" zeo > /dev/null
docker restart "${app}" > /dev/null
wait_healthy
expect "Another client reads the blob from the restored backup" \
    "$(docker exec -e SENAITE_BLOB_CACHE=/tmp/blobs-b "${app}" /opt/senaite/bin/instance run /tmp/blob.py read 2>&1 | tail -1)" \
    "blob read"
expect "The admin signs in after the restore" "$(http login owner "${admin_password}")" "302"

out=$(update -e SENAITE_ADMIN_PASSWORD=ignored -e SMTP_HOST=opensmtpd -e SMTP_PORT=25)
expect "A second run doesn't create anything" "${out}" "senaite-update: done"
if [[ "${out}" == *"created the administrator"* || "${out}" == *"creating the site"* ]]; then
    echo "Error: the second run created the site or the administrator again: ${out}"
    exit 1
fi
