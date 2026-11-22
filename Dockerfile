ARG BASE_IMAGE=ubuntu:22.04

# Ubuntu 22.04 still has Python 2.7, which SENAITE 2.x needs, with security
# updates, and current system libraries.
FROM ${BASE_IMAGE} AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl g++ gcc git make \
        python2.7 python2.7-dev \
        libbz2-dev libffi-dev libjpeg-dev libopenjp2-7-dev libpcre3-dev libssl-dev \
        libtiff-dev libxml2-dev libxslt1-dev zlib1g-dev; \
    rm -rf /var/lib/apt/lists/*

# pip's last release for Python 2.7, then the build tools Plone pins. The
# Python 2.7 installer script no longer changes, so its checksum is pinned.
RUN set -eux; \
    curl -fsSL -o /tmp/get-pip.py https://bootstrap.pypa.io/pip/2.7/get-pip.py; \
    echo "40ee07eac6674b8d60fce2bbabc148cf0e2f1408c167683f110fd608b8d6f416  /tmp/get-pip.py" | sha256sum -c -; \
    python2.7 /tmp/get-pip.py --no-cache-dir 'pip<21' setuptools==42.0.2 wheel==0.37.1; \
    pip2 install --no-cache-dir zc.buildout==2.13.8; \
    rm /tmp/get-pip.py

# Plone and SENAITE with every package pinned in versions.cfg.
WORKDIR /opt/senaite
COPY buildout.cfg versions.cfg ./
RUN set -eux; \
    buildout -N; \
    rm -rf /tmp/buildout-downloads parts/instance/inituser var

FROM ${BASE_IMAGE}

ARG SENAITE_VER
ARG WODBY_USER_ID=1000
ARG WODBY_GROUP_ID=1000

# zope.conf reads the ZEO settings from these variables.
ENV DEBIAN_FRONTEND=noninteractive \
    SENAITE_VER="${SENAITE_VER}" \
    HOME="/home/wodby" \
    ZEO_ADDRESS="" \
    ZODB_CACHE_SIZE="30000" \
    ZEO_CLIENT_CACHE_SIZE="128MB" \
    ZEO_BLOB_CACHE_SIZE="1073741824" \
    SENAITE_BLOB_CACHE="/var/cache/senaite/blobcache"

RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
        ca-certificates python2.7 \
        libbz2-1.0 libffi8 libjpeg8 libopenjp2-7 libpcre3 libssl3 libtiff5 libxml2 libxslt1.1 zlib1g \
        # PDF reports: WeasyPrint draws with Cairo and Pango.
        fonts-dejavu-core fonts-liberation libcairo2 libgdk-pixbuf-2.0-0 libpango-1.0-0 \
        libpangocairo-1.0-0 shared-mime-info; \
    rm -rf /var/lib/apt/lists/*; \
    \
    groupadd -g "${WODBY_GROUP_ID}" wodby; \
    useradd -u "${WODBY_USER_ID}" -g wodby -m -s /bin/bash wodby; \
    mkdir -p /data /var/cache/senaite; \
    chown wodby:wodby /data /var/cache/senaite

COPY --from=build /usr/local/lib/python2.7 /usr/local/lib/python2.7
COPY --from=build /opt/senaite /opt/senaite

# Wodby's filter and setup script, and the configuration that replaces
# buildout's: logs go to the console and the ZEO address comes from the
# environment.
COPY wodby_senaite /usr/local/lib/python2.7/dist-packages/wodby_senaite
COPY etc/zope.conf etc/wsgi.ini /opt/senaite/parts/instance/etc/
COPY etc/zeo.conf /opt/senaite/parts/zeoserver/etc/
COPY bin /usr/local/bin/
COPY docker-entrypoint.sh /

# The image is built for the release it claims.
RUN set -eux; \
    test -n "${SENAITE_VER}"; \
    ls -d "/opt/senaite/eggs/senaite.lims-${SENAITE_VER}-py2.7.egg"; \
    ls -d /opt/senaite/eggs/SenaiteHotfix20260602-*.egg

USER wodby

WORKDIR /opt/senaite

VOLUME /data

EXPOSE 8080 8100

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["start"]
