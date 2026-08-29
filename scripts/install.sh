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

relocate_odin_imports() {
  for source_file in "$1"/*.kvist; do
    [ -f "$source_file" ] || continue
    relocated_file="$source_file.relocated"
    sed 's#"\.\./\.\./odin/#"../odin/#g' "$source_file" >"$relocated_file"
    mv "$relocated_file" "$source_file"
  done
}

mkdir -p "$staging/bin" "$staging/odin"
odin build "$repo_root/src/cli/kvist" -o:speed -out:"$staging/bin/kvist"

for package_dir in "$repo_root"/src/kvist/*; do
  [ -d "$package_dir" ] || continue
  package=${package_dir##*/}
  cp -R "$package_dir" "$staging/$package"
  # Installed packages are one directory closer to their Odin runtimes than
  # packages in the repository's src/kvist layout.
  relocate_odin_imports "$staging/$package"
done
for runtime_dir in "$repo_root"/src/odin/*; do
  [ -d "$runtime_dir" ] || continue
  runtime=${runtime_dir##*/}
  [ "$runtime" = kvist ] && continue
  cp -R "$runtime_dir" "$staging/odin/$runtime"
done

mkdir -p "$destination/bin" "$destination/odin"
rm -f "$destination/bin/kvist"
mv "$staging/bin/kvist" "$destination/bin/kvist"

for package_dir in "$repo_root"/src/kvist/*; do
  [ -d "$package_dir" ] || continue
  package=${package_dir##*/}
  rm -rf "$destination/$package"
  mv "$staging/$package" "$destination/$package"
done
for runtime_dir in "$repo_root"/src/odin/*; do
  [ -d "$runtime_dir" ] || continue
  runtime=${runtime_dir##*/}
  [ "$runtime" = kvist ] && continue
  rm -rf "$destination/odin/$runtime"
  mv "$staging/odin/$runtime" "$destination/odin/$runtime"
done

# Remove packages that are no longer bundled.
for package in hot live io json cli html http; do
  rm -rf "$destination/$package"
done
