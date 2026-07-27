#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/install.sh <destination>" >&2
  exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(dirname -- "$script_dir")
destination=$1
staging="$destination/.kvist-install-$$"

cleanup() {
  rm -rf "$staging"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$staging/bin" "$staging/odin"
odin build "$repo_root/src/cli/kvist" -o:speed -out:"$staging/bin/kvist"

for package in core data edn bit arr map set str soa parallel test regex reload hot live; do
  cp -R "$repo_root/src/kvist/$package" "$staging/$package"
done
cp -R "$repo_root/src/odin/olive_reload" "$staging/odin/olive_reload"

mkdir -p "$destination/bin" "$destination/odin"
rm -f "$destination/bin/kvist"
mv "$staging/bin/kvist" "$destination/bin/kvist"

for package in core data edn bit arr map set str soa parallel test regex reload hot live; do
  rm -rf "$destination/$package"
  mv "$staging/$package" "$destination/$package"
done
rm -rf "$destination/odin/olive_reload"
mv "$staging/odin/olive_reload" "$destination/odin/olive_reload"

# These packages were bundled before the official-package repository split.
for package in io json cli html http; do
  rm -rf "$destination/$package"
done
