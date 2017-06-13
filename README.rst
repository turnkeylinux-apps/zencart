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

- SSL support out of the box.
- `Adminer`_ administration frontend for MySQL (listening on port
  12322 - uses SSL).
- Postfix MTA (bound to localhost) to allow sending of email (e.g.,
  password recovery).
- Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Credentials (passwords set at first boot)
-------------------------------------------

Administrator login is found at `12.34.56.789/manage/index.php`_

-  Webmin, SSH, MySQL, Adminer: username **root**
-  Zen Cart: username **admin**


.. _Zen Cart: http://www.zen-cart.com/
.. _TurnKey Core: https://www.turnkeylinux.org/core
.. _Adminer: http://www.adminer.org/
