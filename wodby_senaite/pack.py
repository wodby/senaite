# -*- coding: utf-8 -*-
"""Packs SENAITE's database on the ZEO server at ZEO_ADDRESS: removes old
object revisions and files nothing refers to any more, keeping the history
of the last DAYS days (the first argument, 7 by default). Run by
senaite-pack from any SENAITE container; the server does the work."""
from __future__ import print_function

import os
import shutil
import sys
import tempfile
import time

from ZEO.ClientStorage import ClientStorage
from ZODB.serialize import referencesf


def main(argv):
    address = os.environ.get("ZEO_ADDRESS", "")
    if ":" not in address:
        print("senaite-pack: error: ZEO_ADDRESS must be host:port", file=sys.stderr)
        return 1
    host, port = address.rsplit(":", 1)
    days = float(argv[1]) if len(argv) > 1 else 7.0

    blob_cache = tempfile.mkdtemp()
    try:
        storage = ClientStorage(
            (host, int(port)),
            storage="1",
            blob_dir=blob_cache,
            shared_blob_dir=False,
            wait_timeout=300,
        )
        try:
            print("senaite-pack: packing, keeping %g days of history" % days)
            sys.stdout.flush()
            storage.pack(time.time() - days * 86400, referencesf, wait=True)
        finally:
            storage.close()
    finally:
        shutil.rmtree(blob_cache, ignore_errors=True)
    print("senaite-pack: done")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
