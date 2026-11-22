# -*- coding: utf-8 -*-
"""Creates or upgrades the SENAITE site. Run by senaite-update with
``bin/instance run``, as one more client of the ZEO server, so the app keeps
serving while it runs.

On an empty database it creates the site from the language and time zone
settings and its administrator from SENAITE_ADMIN_USERNAME,
SENAITE_ADMIN_PASSWORD and SENAITE_ADMIN_EMAIL. Later runs leave the administrator alone
and apply the upgrade steps of a newer SENAITE or Plone.

With an SMTP link, the site's mail server is set to it while the site still
has Plone's default (localhost) or the previous linked address.
"""
from __future__ import print_function

import os
import sys

import transaction
from AccessControl.SecurityManagement import newSecurityManager
from AccessControl.SpecialUsers import system
from Testing.makerequest import makerequest
from zope.component.hooks import setSite

SITE_ID = "senaite"
MIN_PASSWORD_LENGTH = 12

# Wodby's mail settings are remembered here, so a later link change is
# applied while a value set by hand in SENAITE is kept.
LINKED_SMTP_KEY = "wodby.senaite.linked_smtp"


def log(message):
    print("senaite-update: %s" % message)
    sys.stdout.flush()


def fail(message):
    print("senaite-update: error: %s" % message, file=sys.stderr)
    sys.exit(1)


def env(name, default=""):
    return os.environ.get(name, default).strip()


def create_admin(site):
    """Adds the administrator as a site user with the Manager role, so signing
    in gets Plone's signed session cookie. Zope's root has no users."""
    username = env("SENAITE_ADMIN_USERNAME", "admin")
    password = os.environ.get("SENAITE_ADMIN_PASSWORD", "")
    acl_users = site.acl_users
    if acl_users.getUserById(username) is None:
        acl_users._doAddUser(username, password, ["Manager"], [])
        email = env("SENAITE_ADMIN_EMAIL")
        if email:
            member = site.portal_membership.getMemberById(username)
            member.setMemberProperties({"email": email})
        log("created the administrator %s" % username)


def check_admin_settings():
    """Fails before anything is created, so a bad setting leaves no site
    without an administrator."""
    username = env("SENAITE_ADMIN_USERNAME", "admin")
    password = os.environ.get("SENAITE_ADMIN_PASSWORD", "")
    if not username:
        fail("the admin username is empty")
    if len(password) < MIN_PASSWORD_LENGTH:
        fail("the admin password must have at least %d characters" % MIN_PASSWORD_LENGTH)


def create_site(app):
    from Products.CMFPlone.factory import addPloneSite

    language = env("SENAITE_LANGUAGE", "en") or "en"
    timezone = env("SENAITE_TIMEZONE", "UTC") or "UTC"
    log("creating the site (language %s, time zone %s)" % (language, timezone))
    # The same profiles and options as SENAITE's own "Add SENAITE site" form.
    return addPloneSite(
        app,
        SITE_ID,
        title=env("SENAITE_SITE_TITLE", "SENAITE LIMS") or "SENAITE LIMS",
        extension_ids=("senaite.lims:default",),
        setup_content=True,
        default_language=language,
        portal_timezone=timezone,
    )


def secure_session_cookie(site):
    """Wodby serves apps over HTTPS, so the sign-in cookie is sent only over
    HTTPS. It can be changed in the site's acl_users/session afterwards."""
    site.acl_users.session.secure = True
    log("made the sign-in cookie HTTPS-only")


def upgrade_site(site):
    """Applies Plone's migration and every add-on's pending upgrade steps,
    as Plone's upgrade page and add-ons panel do."""
    migration = site.portal_migration
    if migration.needUpgrading():
        log("upgrading Plone from %s" % migration.getInstanceVersion())
        migration.upgrade(swallow_errors=False)

    setup = site.portal_setup
    for profile_id in setup.listProfilesWithUpgrades():
        if setup.getLastVersionForProfile(profile_id) == "unknown":
            # Not installed in this site.
            continue
        if not setup.listUpgrades(profile_id):
            continue
        before = setup.getLastVersionForProfile(profile_id)
        setup.upgradeProfile(profile_id)
        after = setup.getLastVersionForProfile(profile_id)
        log("upgraded %s from %s to %s" % (profile_id, ".".join(before), ".".join(after)))


def configure_mail(site):
    from plone.registry.interfaces import IRegistry
    from zope.annotation.interfaces import IAnnotations
    from zope.component import getUtility

    registry = getUtility(IRegistry)

    from_address = env("SENAITE_EMAIL_FROM")
    if from_address and not registry.get("plone.email_from_address"):
        registry["plone.email_from_address"] = from_address  # an ASCII field
        if not registry.get("plone.email_from_name"):
            registry["plone.email_from_name"] = site.Title().decode("utf-8")
        log("set the sender address")

    host = env("SMTP_HOST")
    port = env("SMTP_PORT")
    if not host:
        return
    try:
        port = int(port or 25)
    except ValueError:
        fail("SMTP_PORT is not a number: %s" % port)

    annotations = IAnnotations(site)
    previous = annotations.get(LINKED_SMTP_KEY)
    current = (registry.get("plone.smtp_host"), registry.get("plone.smtp_port"))
    if current[0] not in (None, u"", u"localhost") and tuple(previous or ()) != current:
        log("kept the mail server set in SENAITE")
        return
    if current == (host.decode("utf-8"), port):
        return

    registry["plone.smtp_host"] = host.decode("utf-8")
    registry["plone.smtp_port"] = port
    mailhost = site.MailHost
    mailhost.smtp_host = host
    mailhost.smtp_port = port
    annotations[LINKED_SMTP_KEY] = (host.decode("utf-8"), port)
    log("set the mail server to the linked SMTP service")


def main(app):
    app = makerequest(app)

    # Zope's internal user, which may do anything.
    newSecurityManager(None, system)

    if SITE_ID not in app.objectIds():
        check_admin_settings()
        site = create_site(app)
        setSite(site)
        create_admin(site)
        secure_session_cookie(site)
    else:
        site = app[SITE_ID]
        setSite(site)
        upgrade_site(site)

    setSite(site)
    configure_mail(site)
    transaction.commit()
    log("done")


main(app)  # noqa: F821 -- ``app`` is the Zope root that ``bin/instance run`` passes in.
