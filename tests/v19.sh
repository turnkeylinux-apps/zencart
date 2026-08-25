#!/bin/bash -e

set -o pipefail

SOURCE_RECORD=/usr/local/share/turnkey-zencart/source
WEBROOT=/var/www/zencart
ADMIN_NAME=admin
ADMIN_PASSWORD=turnkey

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

record_value() {
    key=$1
    value=$(sed -n "s/^${key}=//p" "$SOURCE_RECORD")
    [ -n "$value" ] || fail "missing source record key: $key"
    printf '%s\n' "$value"
}

[ -f "$SOURCE_RECORD" ] || fail "missing installed source record"
[ "$(record_value version)" = v2.2.2 ] || fail "unexpected Zen Cart version"
[ "$(record_value tag_commit)" = 63cf0ec3324d49767d25a07d168cdecb829e4d2a ] || fail "unexpected release tag commit"
[ "$(record_value archive_sha256)" = 5fdb86e97460975b5f7a5e25affd3616b2470b96001aa3f1192bd0cc4c0efadc ] || fail "unexpected release archive digest"

installed_version=$(php -r 'include $argv[1]; echo PROJECT_VERSION_MAJOR, ".", PROJECT_VERSION_MINOR;' "$WEBROOT/includes/version.php")
[ "$installed_version" = 2.2.2 ] || fail "runtime version differs from pinned release"
[ "$(php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;')" = 8.4 ] || fail "unexpected PHP runtime version"
[ ! -e "$WEBROOT/zc_install" ] || fail "installer remains exposed"
[ ! -e "$WEBROOT/admin" ] || fail "default administrator path remains exposed"
[ -f "$WEBROOT/manage/login.php" ] || fail "administrator login is missing"

for conf in "$WEBROOT/includes/configure.php" "$WEBROOT/manage/includes/configure.php"; do
    [ "$(stat -c '%U:%G %a' "$conf")" = "root:www-data 640" ] || fail "unsafe configuration ownership or mode: $conf"
done

apache2ctl configtest >/dev/null
apache2ctl -S 2>&1 | grep -q '/etc/apache2/sites-enabled/zencart.conf' || fail "Zen Cart Apache site is not enabled"
mysqladmin ping >/dev/null || fail "MariaDB is not responding"

domain=$(php -r 'include $argv[1]; echo parse_url(HTTPS_SERVER, PHP_URL_HOST);' "$WEBROOT/includes/configure.php")
[ -n "$domain" ] || fail "configured storefront domain is empty"
base_url="https://$domain"
curl_base=(curl -kfsS --resolve "$domain:443:127.0.0.1")

storefront=$("${curl_base[@]}" "$base_url/")
printf '%s' "$storefront" | grep -qi 'Zen Cart' || fail "storefront did not render Zen Cart"

cookie=$(mktemp /tmp/zencart-v19-cookie.XXXXXX)
trap 'rm -f "$cookie"' EXIT
login_page=$("${curl_base[@]}" -c "$cookie" -b "$cookie" "$base_url/manage/login.php")
security_token=$(printf '%s' "$login_page" | sed -n 's/.*name="securityToken" value="\([^"]*\)".*/\1/p' | head -1)
[ -n "$security_token" ] || fail "administrator login token is missing"

"${curl_base[@]}" -L -c "$cookie" -b "$cookie" \
    --data-urlencode "securityToken=$security_token" \
    --data-urlencode "action=do$security_token" \
    --data-urlencode "admin_name=$ADMIN_NAME" \
    --data-urlencode "admin_pass=$ADMIN_PASSWORD" \
    "$base_url/manage/login.php" >/dev/null

server_info=$("${curl_base[@]}" -L -c "$cookie" -b "$cookie" "$base_url/manage/server_info.php")
printf '%s' "$server_info" | grep -q '<body class="sysinfoBody">' || fail "administrator session did not reach server information"

category_id=$(mysql zencart -NBe "INSERT INTO zen_categories (parent_id, sort_order, date_added, categories_status) VALUES (0, 0, NOW(), 1); SELECT LAST_INSERT_ID();")
[ "$category_id" -gt 0 ] || fail "acceptance category was not created"
mysql zencart --batch --execute "INSERT INTO zen_categories_description (categories_id, language_id, categories_name, categories_description) VALUES ($category_id, 1, 'Wave 2 Acceptance', 'Disposable acceptance category');"

"${curl_base[@]}" -L -c "$cookie" -b "$cookie" \
    --data-urlencode "securityToken=$security_token" \
    --data-urlencode product_type=1 \
    --data-urlencode products_status=1 \
    --data-urlencode 'products_name[1]=Wave 2 Acceptance Product' \
    --data-urlencode 'products_description[1]=Zen Cart v19 product round trip' \
    --data-urlencode 'products_url[1]=' \
    --data-urlencode products_quantity=5 \
    --data-urlencode products_model=WAVE2-V19 \
    --data-urlencode products_mpn= \
    --data-urlencode products_price=19.95 \
    --data-urlencode products_price_w=0 \
    --data-urlencode products_date_available= \
    --data-urlencode products_weight=0 \
    --data-urlencode products_length=0 \
    --data-urlencode products_width=0 \
    --data-urlencode products_height=0 \
    --data-urlencode products_virtual=0 \
    --data-urlencode products_tax_class_id=0 \
    --data-urlencode manufacturers_id=0 \
    --data-urlencode products_quantity_order_min=1 \
    --data-urlencode products_quantity_order_units=1 \
    --data-urlencode products_quantity_order_max=0 \
    --data-urlencode products_priced_by_attribute=0 \
    --data-urlencode product_is_free=0 \
    --data-urlencode product_is_call=0 \
    --data-urlencode products_quantity_mixed=0 \
    --data-urlencode product_is_always_free_shipping=0 \
    --data-urlencode products_qty_box_status=1 \
    --data-urlencode products_sort_order=0 \
    --data-urlencode products_discount_type=0 \
    --data-urlencode products_discount_type_from=0 \
    --data-urlencode products_price_sorter=0 \
    --data-urlencode products_image= \
    "$base_url/manage/product.php?cPath=$category_id&action=insert_product" >/dev/null

product_id=$(mysql zencart -NBe "SELECT products_id FROM zen_products WHERE products_model='WAVE2-V19' ORDER BY products_id DESC LIMIT 1")
[ "$product_id" -gt 0 ] || fail "administrator product creation did not persist"
[ "$(mysql zencart -NBe "SELECT products_name FROM zen_products_description WHERE products_id=$product_id AND language_id=1")" = "Wave 2 Acceptance Product" ] || fail "product name differs in MariaDB"

product_page=$("${curl_base[@]}" "$base_url/index.php?main_page=product_info&products_id=$product_id")
printf '%s' "$product_page" | grep -q 'Wave 2 Acceptance Product' || fail "created product could not be read from the storefront"

postconf -h inet_interfaces | grep -qx loopback-only || fail "Postfix is not restricted to loopback"
printf 'Subject: Zen Cart v19 acceptance\n\nLocal application mail check.\n' | timeout 20 /usr/sbin/sendmail root@localhost

update_check=$(turnkey-zencart-update --check)
printf '%s\n' "$update_check" | grep -qx 'installed=v2.2.2' || fail "updater installed version mismatch"
printf '%s\n' "$update_check" | grep -qx 'candidate=v2.2.2' || fail "updater candidate version mismatch"
printf '%s\n' "$update_check" | grep -qx 'candidate_commit=63cf0ec3324d49767d25a07d168cdecb829e4d2a' || fail "updater tag commit mismatch"
printf '%s\n' "$update_check" | grep -qx 'candidate_archive_sha256=5fdb86e97460975b5f7a5e25affd3616b2470b96001aa3f1192bd0cc4c0efadc' || fail "updater archive digest mismatch"
printf '%s\n' "$update_check" | grep -qx 'status=up-to-date' || fail "updater did not report stable status"

update_apply=$(turnkey-zencart-update --apply --dry-run)
printf '%s\n' "$update_apply" | grep -qx 'apply=dry-run verified exact candidate' || fail "updater apply plan was not verified"

if [ -n "${TKL_TEST_RESULT:-}" ]; then
    cat > "$TKL_TEST_RESULT" <<EOF
package_source=official Zen Cart v2.2.2 tag 63cf0ec3324d49767d25a07d168cdecb829e4d2a
installed_version=Zen Cart v2.2.2 on PHP 8.4
runtime_checks=storefront, administrator login, product create-read, MariaDB, Apache, and loopback application mail passed
updater_command=turnkey-zencart-update --check; turnkey-zencart-update --apply --dry-run
updater_result=verified exact v2.2.2 tag and archive; installed release is current
updater_channel=official Zen Cart v2.2 patch releases
integrity_evidence=official archive SHA256 5fdb86e97460975b5f7a5e25affd3616b2470b96001aa3f1192bd0cc4c0efadc
EOF
fi

echo "PASS: Zen Cart storefront, administrator login, product round trip, database, mail, and updater"
echo "zencart=v2.2.2 tag_commit=63cf0ec3324d49767d25a07d168cdecb829e4d2a"
