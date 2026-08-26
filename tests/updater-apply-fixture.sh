#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
UPDATER=$REPO_ROOT/overlay/usr/local/sbin/turnkey-zencart-update
UPSTREAM=https://github.com/zencart/zencart.git
OLD_VERSION=v2.2.1
NEW_VERSION=v2.2.2
NEW_COMMIT=63cf0ec3324d49767d25a07d168cdecb829e4d2a
NEW_ARCHIVE_SHA256=5fdb86e97460975b5f7a5e25affd3616b2470b96001aa3f1192bd0cc4c0efadc

fixture=$(mktemp -d "$REPO_ROOT/.zencart-updater-fixture.XXXXXX")
cleanup() {
    rm -rf "$fixture"
}
trap cleanup EXIT HUP INT TERM

resolve_tag_commit() {
    version=$1
    refs=$(git -C / ls-remote --tags "$UPSTREAM" "refs/tags/$version" "refs/tags/$version^{}")
    direct=$(printf '%s\n' "$refs" | awk -v ref="refs/tags/$version" '$2 == ref {print $1}')
    commit=$(printf '%s\n' "$refs" | awk -v ref="refs/tags/$version^{}" '$2 == ref {print $1}')
    [ -n "$commit" ] || commit=$direct
    printf '%s\n' "$commit" | grep -Eq '^[0-9a-f]{40}$'
    printf '%s\n' "$commit"
}

old_commit=$(resolve_tag_commit "$OLD_VERSION") || {
    echo "unable to resolve official $OLD_VERSION commit" >&2
    exit 1
}
old_archive=$fixture/zencart-$OLD_VERSION.zip
curl -LfsS "https://github.com/zencart/zencart/archive/refs/tags/$OLD_VERSION.zip" -o "$old_archive"
old_archive_sha256=$(sha256sum "$old_archive" | awk '{print $1}')
mkdir "$fixture/extract"
unzip -q "$old_archive" -d "$fixture/extract"

fixture_root=$fixture/root
webroot=$fixture_root/var/www/zencart
source_record=$fixture_root/usr/local/share/turnkey-zencart/source
mkdir -p "$(dirname "$webroot")" "$(dirname "$source_record")" "$fixture_root/var/cache"
mv "$fixture/extract/zencart-${OLD_VERSION#v}" "$webroot"
mv "$webroot/admin" "$webroot/manage"

printf '%s\n' '<?php // preserved storefront configuration fixture' >"$webroot/includes/configure.php"
printf '%s\n' '<?php // preserved renamed-admin configuration fixture' >"$webroot/manage/includes/configure.php"
printf '%s\n' 'preserved product image fixture' >"$webroot/images/fixture-product-image.txt"
printf '%s\n' 'preserved product download fixture' >"$webroot/download/fixture-product-download.txt"
printf '%s\n' \
    "version=$OLD_VERSION" \
    "tag_commit=$old_commit" \
    "archive_sha256=$old_archive_sha256" \
    'channel=official Zen Cart v2.2 patch releases' >"$source_record"

real_git=$(command -v git)
fakebin=$fixture/fakebin
mkdir "$fakebin"
cat >"$fakebin/git" <<'EOF'
#!/bin/bash
set -o pipefail
for arg in "$@"; do
    if [ "$arg" = ls-remote ]; then
        "$TKL_ZENCART_FIXTURE_REAL_GIT" "$@" | awk '
            $2 == "refs/tags/v2.2.2" || $2 == "refs/tags/v2.2.2^{}" {
                $1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            }
            { print $1 "\t" $2 }
        '
        exit
    fi
done
exec "$TKL_ZENCART_FIXTURE_REAL_GIT" "$@"
EOF
chmod 0755 "$fakebin/git"
if PATH="$fakebin:$PATH" \
        TKL_ZENCART_FIXTURE_REAL_GIT="$real_git" \
        TKL_ZENCART_UPDATE_ROOT="$fixture_root" \
        "$UPDATER" --check >"$fixture/mismatch.out" 2>"$fixture/mismatch.err"; then
    echo "updater accepted a checkout that differed from the resolved tag commit" >&2
    exit 1
fi
grep -Fqx \
    "fetched checkout does not match official tag commit for $NEW_VERSION" \
    "$fixture/mismatch.err"

storefront_conf_before=$(sha256sum "$webroot/includes/configure.php" | awk '{print $1}')
admin_conf_before=$(sha256sum "$webroot/manage/includes/configure.php" | awk '{print $1}')
product_image_before=$(sha256sum "$webroot/images/fixture-product-image.txt" | awk '{print $1}')
product_download_before=$(sha256sum "$webroot/download/fixture-product-download.txt" | awk '{print $1}')

apply_output=$(TKL_ZENCART_UPDATE_ROOT="$fixture_root" "$UPDATER" --apply)
grep -Fqx "installed=$OLD_VERSION" <<<"$apply_output"
grep -Fqx "candidate=$NEW_VERSION" <<<"$apply_output"
grep -Fqx "candidate_commit=$NEW_COMMIT" <<<"$apply_output"
grep -Fqx "candidate_archive_sha256=$NEW_ARCHIVE_SHA256" <<<"$apply_output"
grep -Fqx 'status=update-available' <<<"$apply_output"
grep -Fqx 'apply=complete' <<<"$apply_output"

[ "$(sha256sum "$webroot/includes/configure.php" | awk '{print $1}')" = "$storefront_conf_before" ]
[ "$(sha256sum "$webroot/manage/includes/configure.php" | awk '{print $1}')" = "$admin_conf_before" ]
[ "$(sha256sum "$webroot/images/fixture-product-image.txt" | awk '{print $1}')" = "$product_image_before" ]
[ "$(sha256sum "$webroot/download/fixture-product-download.txt" | awk '{print $1}')" = "$product_download_before" ]
[ ! -e "$webroot/admin" ]
[ -f "$webroot/manage/index.php" ]
[ "$(sed -n 's/^version=//p' "$source_record")" = "$NEW_VERSION" ]
[ "$(sed -n 's/^tag_commit=//p' "$source_record")" = "$NEW_COMMIT" ]
[ "$(sed -n 's/^archive_sha256=//p' "$source_record")" = "$NEW_ARCHIVE_SHA256" ]
[ "$(php -r 'include $argv[1]; echo PROJECT_VERSION_MAJOR, ".", PROJECT_VERSION_MINOR;' "$webroot/includes/version.php")" = "${NEW_VERSION#v}" ]

php -l "$webroot/index.php" >/dev/null
php -l "$webroot/manage/index.php" >/dev/null
php -l "$webroot/includes/modules/pages/product_info/main_template_vars.php" >/dev/null

printf '%s\n' \
    'fixture_update=v2.2.1->v2.2.2' \
    "candidate_commit=$NEW_COMMIT" \
    'provenance_mismatch=rejected' \
    'config=preserved' \
    'data=preserved' \
    'renamed_admin=preserved-and-updated' \
    'source_record=updated-and-provenance-bound' \
    'storefront=php-syntax-pass' \
    'admin=php-syntax-pass' \
    'product=php-syntax-pass' \
    'PASS: disposable official Zen Cart updater apply fixture'
