# -*- coding: utf-8 -*-
"""Serves the SENAITE site at the root of the app's domain.

Zope publishes the site at /senaite and builds its links from the request.
The filter rewrites every request into a Virtual Host Monster path, so Zope
links to the public scheme, host and port that Wodby's gateway received and
the site answers at /. Zope's root, with its management interface, is not
reachable this way.
"""

import re

SITE_ID = "senaite"

# A host name or address with an optional port. Anything else could add path
# segments to the rewritten path.
HOST_RE = re.compile(r"^(?P<host>[A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\])(?::(?P<port>[0-9]{1,5}))?$")

# Answered by Zope's root without the site, so a pod becomes ready before
# the first deployment creates the site.
HEALTH_PATH = "/.healthz"


def _first(value):
    return value.split(",")[0].strip() if value else ""


def filter_factory(global_conf, site_id=SITE_ID):
    """paste.deploy filter factory used by wsgi.ini."""

    def make_filter(app):
        def vhm(environ, start_response):
            path = environ.get("PATH_INFO") or "/"
            if path == HEALTH_PATH:
                environ["PATH_INFO"] = "/@@ok"
                return app(environ, start_response)

            # Wodby's gateway terminates TLS and passes the scheme on.
            scheme = _first(environ.get("HTTP_X_FORWARDED_PROTO")) or environ.get(
                "wsgi.url_scheme", "http"
            )
            if scheme not in ("http", "https"):
                scheme = "http"
            match = HOST_RE.match(environ.get("HTTP_HOST") or "")
            if match:
                host = match.group("host")
                port = match.group("port")
            else:
                host = environ.get("SERVER_NAME") or "localhost"
                port = None
            if not port:
                port = "443" if scheme == "https" else "80"

            # The client's address as the gateway saw it.
            forwarded_for = environ.get("HTTP_X_FORWARDED_FOR")
            if forwarded_for:
                environ["REMOTE_ADDR"] = forwarded_for.split(",")[-1].strip()

            environ["PATH_INFO"] = "/VirtualHostBase/%s/%s:%s/%s/VirtualHostRoot%s" % (
                scheme,
                host,
                port,
                site_id,
                path,
            )
            return app(environ, start_response)

        return vhm

    return make_filter
