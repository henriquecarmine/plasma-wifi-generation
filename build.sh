#!/usr/bin/env bash
# Builds everything from source: catalogues, the .plasmoid for the KDE Store,
# and the source tarball the RPM spec expects.
#
# The compiled catalogues (.mo) are NOT in git — they are generated from the
# .po files here. Committing build output means the day someone edits a .po
# and forgets to recompile, the shipped translation silently disagrees with
# the source.
set -euo pipefail

ID=com.henrique.wifigeracao
DOMAIN=plasma_applet_$ID
NAME=plasma-applet-wifi-generation
VERSION=$(python3 -c "import json;print(json.load(open('package/metadata.json'))['KPlugin']['Version'])")
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"

echo "== Wi-Fi Generation $VERSION =="

# 1. Refresh the template from the source, so a forgotten string shows up.
xgettext --from-code=UTF-8 --language=JavaScript \
	--keyword=i18nd:2 --keyword=i18ndp:2,3 \
	--package-name="Wi-Fi Generation" --package-version="$VERSION" \
	-o po/plasma_applet.pot package/contents/ui/main.qml

# 2. Compile each catalogue INTO the package, and refuse to ship a broken one.
rm -rf package/contents/locale
for po in po/*.po; do
	lang=$(basename "$po" .po)
	dir="package/contents/locale/$lang/LC_MESSAGES"
	mkdir -p "$dir"
	msgfmt --check --statistics -o "$dir/$DOMAIN.mo" "$po"
done

# 3. The .plasmoid for the KDE Store — a plain zip of the package.
mkdir -p dist
rm -f "dist/wifi-generation-$VERSION.plasmoid"
( cd package && cp ../LICENSE ../README.md . 2>/dev/null || true
  zip -qr "../dist/wifi-generation-$VERSION.plasmoid" . -x '.*' )
rm -f package/LICENSE package/README.md

# 4. The source tarball the .spec expects.
tmp=$(mktemp -d)
mkdir -p "$tmp/$NAME-$VERSION/$ID" "$tmp/$NAME-$VERSION/po"
cp -a package/. "$tmp/$NAME-$VERSION/$ID/"
cp LICENSE README.md "$tmp/$NAME-$VERSION/$ID/"
cp po/*.po po/*.pot "$tmp/$NAME-$VERSION/po/"
( cd "$tmp" && tar czf "$HERE/dist/$NAME-$VERSION.tar.gz" "$NAME-$VERSION" )
rm -rf "$tmp"

echo
echo "dist/wifi-generation-$VERSION.plasmoid   -> KDE Store"
echo "dist/$NAME-$VERSION.tar.gz               -> put in ~/rpmbuild/SOURCES/ and run:"
echo "                                            rpmbuild -ba $NAME.spec"
