#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if rg -n 'cups-browsed|cups-cups-browsed' \
  "$root/PKGBUILD" "$root/monarch.install"; then
  echo "monarch still owns cups-browsed configuration" >&2
  exit 1
fi

echo "monarch leaves cups-browsed configuration unowned"

if [[ -n ${MONARCH_SOURCE_PATH:-} ]]; then
  temporary=$(mktemp -d)
  trap 'rm -rf "$temporary"' EXIT
  export MONARCH_SRC="$MONARCH_SOURCE_PATH"
  source "$root/PKGBUILD"
  srcdir="$temporary/src"
  pkgdir="$temporary/pkg"
  mkdir -p "$srcdir" "$pkgdir"
  ln -s "$MONARCH_SOURCE_PATH" "$srcdir/monarch"
  pkgver=$(pkgver)
  package_monarch
  [[ $(<"$pkgdir/usr/share/monarch/version") == "$pkgver" ]]
  [[ $(<"$pkgdir/usr/share/monarch/revision") == "$(git -C "$MONARCH_SOURCE_PATH" rev-parse HEAD)" ]]
  [[ -L $pkgdir/usr/bin/monarch ]]
  [[ ! -e $pkgdir/etc/skel/.local/state/noctalia ]]
  [[ ! -e $pkgdir/etc/skel/.local/share/noctalia ]]
  echo "monarch no longer seeds Noctalia state or plugins into new homes"
fi
