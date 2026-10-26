#!/usr/bin/env bash
# Named test: a release archive whose sha256 does not match the digest pinned
# in upstream.json fails scripts/fetch.sh, which the build runs before it
# stages, packs or publishes anything, and leaves neither the archive nor an
# extracted binary behind. The same archive with its true digest is accepted
# and its binary extracted, so the check is not vacuous; an archive holding
# anything besides the one binary is refused even when its digest matches.
# Runs offline: the "release" is local files.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

asset=kustomize_v9.9.9_linux_amd64.tar.gz
mkdir -p "$work/release" "$work/src" "$work/evil"
printf 'not really kustomize\n' >"$work/src/kustomize"
tar -czf "$work/release/$asset" -C "$work/src" kustomize
printf 'not really kustomize\n' >"$work/evil/kustomize"
printf 'surprise\n' >"$work/evil/extra"
tar -czf "$work/release/evil.tar.gz" -C "$work/evil" kustomize extra
printf '                                 Apache License\n                           Version 2.0, January 2004\n' >"$work/release/LICENSE"
true_digest=$(sha256 "$work/release/$asset")
evil_digest=$(sha256 "$work/release/evil.tar.gz")
wrong_digest=$(printf '%064d' 0)

manifest() { # <asset name> <digest>
  jq -n --arg n "$1" --arg d "sha256:$2" \
    '{version: "9.9.9", repack: 0, assets: {"linux-x64": {name: $n, digest: $d}}}'
}

fetch() { # <manifest file> <outdir>
  UPSTREAM_JSON=$1 UPSTREAM_BASE_URL="file://$work/release" UPSTREAM_LICENSE_URL="file://$work/release/LICENSE" \
    bash "$root/scripts/fetch.sh" "$2"
}

manifest "$asset" "$wrong_digest" >"$work/wrong.json"
set +e
fetch "$work/wrong.json" "$work/out-wrong" >"$work/wrong.log" 2>&1
rc=$?
set -e
cat "$work/wrong.log"
test "$rc" -ne 0 || { echo "digest-mismatch: fetch accepted an archive whose digest does not match" >&2; exit 1; }
grep -q "sha256 mismatch for $asset" "$work/wrong.log" || { echo "digest-mismatch: the failure does not name the mismatch" >&2; exit 1; }
test ! -e "$work/out-wrong/assets/$asset" || { echo "digest-mismatch: the mismatching archive was left behind" >&2; exit 1; }
test ! -e "$work/out-wrong/linux-x64" || { echo "digest-mismatch: the mismatching archive was extracted" >&2; exit 1; }

manifest evil.tar.gz "$evil_digest" >"$work/evil.json"
set +e
fetch "$work/evil.json" "$work/out-evil" >"$work/evil.log" 2>&1
rc=$?
set -e
cat "$work/evil.log"
test "$rc" -ne 0 || { echo "digest-mismatch: fetch extracted an archive holding more than the binary" >&2; exit 1; }
test ! -e "$work/out-evil/linux-x64" || { echo "digest-mismatch: the unexpected archive was extracted" >&2; exit 1; }

manifest "$asset" "$true_digest" >"$work/true.json"
fetch "$work/true.json" "$work/out-true"
cmp "$work/src/kustomize" "$work/out-true/linux-x64/kustomize"

echo "digest-mismatch: OK"
