#!/usr/bin/python
"""Set ZenCart admin password, email and domain to serve

Option:
    --pass=     unless provided, will ask interactively
    --email=    unless provided, will ask interactively
    --domain=   unless provided, will ask interactively
                DEFAULT=www.example.com
"""

import re
import sys
import getopt
import inithooks_cache

import string
import random
import hashlib
from datetime import datetime

from dialog_wrapper import Dialog
from mysqlconf import MySQL
from executil import system

def usage(s=None):
    if s:
        print >> sys.stderr, "Error:", s
    print >> sys.stderr, "Syntax: %s [options]" % sys.argv[0]
    print >> sys.stderr, __doc__
    sys.exit(1)

DEFAULT_DOMAIN="www.example.com"

def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass=', 'email=', 'domain='])
    except getopt.GetoptError, e:
        usage(e)

    email = ""
    domain = ""
    password = ""
    for opt, val in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt == '--pass':
            password = val
        elif opt == '--email':
            email = val
        elif opt == '--domain':
            domain = val

    if not password:
        d = Dialog('TurnKey Linux - First boot configuration')
        password = d.get_password(
            "ZenCart Password",
            "Enter new password for the ZenCart 'admin' account.")

    if not email:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        email = d.get_email(
            "ZenCart Email",
            "Enter email address for the ZenCart 'admin' account.",
            "admin@example.com")

    inithooks_cache.write('APP_EMAIL', email)

    if not domain:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        domain = d.get_input(
            "ZenCart Domain",
            "Enter the domain to serve ZenCart.",
            DEFAULT_DOMAIN)

    if domain == "DEFAULT":
        domain = DEFAULT_DOMAIN

    inithooks_cache.write('APP_DOMAIN', domain)

    salt = "".join(random.choice(string.letters) for line in range(2))
    hashpass = ":".join([hashlib.md5(salt + password).hexdigest(), salt])

    m = MySQL()
    m.execute('UPDATE zencart.admin SET admin_pass=\"%s\" WHERE admin_name=\"admin\";' % hashpass)
    m.execute('UPDATE zencart.admin SET admin_email=\"%s\" WHERE admin_name=\"admin\";' % email)

    # perform tweaks so user isn't asked to reset password
    now = datetime.now()
    date = now.strftime("%Y-%m-%d %H:%M:%S")

    m.execute('UPDATE zencart.admin SET pwd_last_change_date=\"%s\" WHERE admin_name=\"admin\";' % date)
    m.execute('UPDATE zencart.admin SET last_login_date=\"%s\" WHERE admin_name=\"admin\";' % date)

    # set domain
    conf = "/var/www/zencart/includes/configure.php"
    system("sed -i \"s|'HTTP_SERVER.*|'HTTP_SERVER', 'http://%s');|\" %s" % (domain, conf))
    system("sed -i \"s|'HTTPS_SERVER.*|'HTTPS_SERVER', 'https://%s');|\" %s" % (domain, conf))

    conf = "/var/www/zencart/manage/includes/configure.php"
    system("sed -i \"s|'HTTP_SERVER.*|'HTTP_SERVER', 'http://%s');|\" %s" % (domain, conf))
    system("sed -i \"s|'HTTPS_SERVER.*|'HTTPS_SERVER', 'https://%s');|\" %s" % (domain, conf))
    system("sed -i \"s|'HTTP_CATALOG_SERVER.*|'HTTP_CATALOG_SERVER', 'http://%s');|\" %s" % (domain, conf))
    system("sed -i \"s|'HTTPS_CATALOG_SERVER.*|'HTTPS_CATALOG_SERVER', 'https://%s');|\" %s" % (domain, conf))


if __name__ == "__main__":
    main()

