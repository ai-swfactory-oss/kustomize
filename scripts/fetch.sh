#!/usr/bin/env bash
# Downloads the upstream kustomize release archives named in upstream.json,
# verifies each against its pinned sha256 digest, and extracts the one binary
# each archive carries. An archive whose digest does not match is deleted and
# the script exits 1, so nothing unverified is extracted, staged, packed or
# published.
#
#   scripts/fetch.sh <outdir> [platform ...]     (default: every platform)
#
# UPSTREAM_JSON overrides the manifest (default: upstream.json at the root);
# UPSTREAM_BASE_URL and UPSTREAM_LICENSE_URL override where the release assets
# and the LICENSE are downloaded from (the tests point them at local files).
#
# Upstream tags kustomize releases "kustomize/v<version>" (the repository also
# releases api/, kyaml/ and cmd/config/ modules), so the tag's slash is
# URL-encoded in the download path.
#
# Result: <outdir>/assets/<asset name>   (the original upstream archive)
#         <outdir>/<platform>/kustomize  (the binary from that archive, executable)
#         <outdir>/LICENSE               (kubernetes-sigs/kustomize's LICENSE at the tag)
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest=${UPSTREAM_JSON:-$root/upstream.json}
out=${1:?usage: fetch.sh <outdir> [platform ...]}
shift

if [ "$#" -gt 0 ]; then
  platforms=("$@")
else
  read -r -a platforms <<<"$(jq -r '.assets | keys | join(" ")' "$manifest")"
fi

version=$(jq -er .version "$manifest")
base=${UPSTREAM_BASE_URL:-https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv$version}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

mkdir -p "$out/assets"
for platform in "${platforms[@]}"; do
  name=$(jq -er --arg p "$platform" '.assets[$p].name' "$manifest")
  digest=$(jq -er --arg p "$platform" '.assets[$p].digest' "$manifest")
  case "$digest" in
    sha256:*) expected=${digest#sha256:} ;;
    *) echo "fetch: $platform: digest '$digest' is not sha256:<hex>" >&2; exit 1 ;;
  esac
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { echo "fetch: $platform: digest '$digest' is not sha256:<64 hex>" >&2; exit 1; }

  asset="$out/assets/$name"
  echo "fetch: $platform <- $base/$name"
  curl -fsSL --retry 3 --retry-delay 5 -o "$asset" "$base/$name"

  actual=$(sha256 "$asset")
  if [ "$actual" != "$expected" ]; then
    echo "fetch: $platform: sha256 mismatch for $name" >&2
    echo "  expected $expected" >&2
    echo "  actual   $actual" >&2
    rm -f "$asset"
    exit 1
  fi
  echo "fetch: $platform: sha256 $actual OK"

  # The archive holds exactly one member, the kustomize binary at its root.
  # Extract that member only, and refuse anything else in it.
  members=$(tar -tzf "$asset")
  [ "$members" = kustomize ] || { echo "fetch: $platform: $name holds '$members', expected only 'kustomize'" >&2; exit 1; }
  dest="$out/$platform"
  rm -rf "$dest"
  mkdir -p "$dest"
  tar -xzf "$asset" -C "$dest" kustomize
  if [ ! -f "$dest/kustomize" ] || [ -L "$dest/kustomize" ]; then
    echo "fetch: $platform: kustomize is not a regular file" >&2; exit 1
  fi
  chmod 755 "$dest/kustomize"
done

license_url=${UPSTREAM_LICENSE_URL:-https://raw.githubusercontent.com/kubernetes-sigs/kustomize/kustomize/v$version/LICENSE}
curl -fsSL --retry 3 --retry-delay 5 -o "$out/LICENSE" "$license_url"
if ! grep -q 'Apache License' "$out/LICENSE" || ! grep -q 'Version 2.0, January 2004' "$out/LICENSE"; then
  echo "fetch: the LICENSE at kubernetes-sigs/kustomize kustomize/v$version is not the expected Apache-2.0 text" >&2; exit 1
fi
