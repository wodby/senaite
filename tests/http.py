# Requests SENAITE inside the app container (Python 2.7) as Wodby's gateway
# sends them: the public host, HTTPS and the client's address.
import base64
import cookielib
import re
import sys
import urllib
import urllib2

BASE = "http://127.0.0.1:8080"
HEADERS = {
    "Host": "senaite.example.com",
    "X-Forwarded-Proto": "https",
    "X-Forwarded-For": "203.0.113.7",
}


class NoRedirect(urllib2.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def request(path, data=None, headers=None, jar=None):
    opener = urllib2.build_opener(NoRedirect, urllib2.HTTPCookieProcessor(jar or cookielib.CookieJar()))
    all_headers = dict(HEADERS)
    all_headers.update(headers or {})
    try:
        response = opener.open(urllib2.Request(BASE + path, data=data, headers=all_headers))
        return response.code, response.info(), response.read()
    except urllib2.HTTPError as error:
        return error.code, error.info(), error.read()


def main(command, *args):
    if command == "status":
        print(request(args[0])[0])
    elif command == "location":
        print(request(args[0])[1].get("Location"))
    elif command == "links":
        body = request(args[0])[2]
        https = "yes" if "https://senaite.example.com" in body else "no"
        http = "yes" if "http://senaite.example.com" in body else "no"
        print("https=%s http=%s" % (https, http))
    elif command == "login":
        data = urllib.urlencode({
            "__ac_name": args[0], "__ac_password": args[1], "came_from": "",
            "buttons.login": "Log in", "form.submitted": "1",
        })
        code, info, _ = request("/login", data)
        cookies = info.getheaders("Set-Cookie")
        auth = [c for c in cookies if c.startswith("__ac=")]
        secure = "yes" if auth and re.search(r";\s*secure", auth[0], re.I) else "no"
        print("%s %s secure=%s" % (code, info.get("Location"), secure))
    elif command == "api":
        token = base64.b64encode("%s:%s" % (args[0], args[1]))
        code, _, body = request(args[2], headers={"Authorization": "Basic " + token})
        print("%s %s" % (code, body))
    elif command == "anon-post":
        code, _, body = request(args[0], data='{"uid": "x", "Title": "y"}', headers={"Content-Type": "application/json"})
        print("%s %s" % (code, body[:200]))


if __name__ == "__main__":
    main(*sys.argv[1:])
