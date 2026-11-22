# Run with bin/instance run: writes a blob through one ZEO client and reads
# it back through another one with an empty blob cache.
import sys
import transaction
from ZODB.blob import Blob

app = app  # noqa: F821 -- the Zope root from bin/instance run
root = app._p_jar.root()
if sys.argv[-1] == "write":
    blob = Blob()
    with blob.open("w") as f:
        f.write(b"senaite blob " * 1000)
    root["wodby_test_blob"] = blob
    transaction.commit()
    print("blob written")
else:
    with root["wodby_test_blob"].open("r") as f:
        data = f.read()
    print("blob read" if data == b"senaite blob " * 1000 else "blob WRONG")
