# Run with bin/instance run: the JSON API modules use the hotfix's safe
# parser instead of Python's eval.
import os
import bika.lims.jsonapi as jsonapi

marker = "/tmp/senaite-hotfix-test"
try:
    jsonapi.eval("__import__('os').system('touch %s')" % marker)
except Exception:
    pass
print("hotfix active" if not os.path.exists(marker) else "hotfix MISSING")
