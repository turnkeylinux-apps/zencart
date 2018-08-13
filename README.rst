Zen Cart - online store management system
=========================================

`Zen Cart`_ is an online store management that supports multiple
languages and currencies. It's designed to put the dream of running an
online business within anyone's reach. While many other shopping cart
solutions seem to be complicated programming exercises Zen Cart puts the
needs of merchants and shoppers first.

This appliance includes all the standard features in `TurnKey Core`_,
and on top of that:

- Zen Cart configurations:
   
   - Installed from upstream source code to /var/www/zencart

     **Security note**: Updates to Zen Cart may require supervision so
     they **ARE NOT** configured to install automatically. See `Zen Cart
     documentation`_ for upgrading.

- SSL support out of the box.
- `Adminer`_ administration frontend for MySQL (listening on port
  12322 - uses SSL).
- Postfix MTA (bound to localhost) to allow sending of email (e.g.,
  password recovery).
- Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Credentials (passwords set at first boot)
-------------------------------------------

Administrator login is found at https://YOUR_DOMAIN_DOT_COM/manage/index.php

-  Webmin, SSH, MySQL: username **root**
-  Adminer: username **adminer**
-  Zen Cart: username **admin**


.. _Zen Cart: https://www.zen-cart.com/
.. _TurnKey Core: https://www.turnkeylinux.org/core
.. _Zen Cart documentation: https://www.zen-cart.com/content.php?148
.. _Adminer: https://www.adminer.org/
