#!/usr/bin/env bash
# The repository's validate command (.panoptic.json "validate": "bash scripts/validate.sh"),
# run by `claude-factory work commit` on the gate host. It runs the same path
# the PR CI runs (build.yml), for the gate host's own platform, so the receipt
# covers the smoke and not only the offline tests:
#
#   1. shellcheck over every shell script;
#   2. named test test/digest-mismatch.sh (a digest mismatch, or an archive
#      holding more than the binary, fails the fetch; the true digest passes);
#   3. scripts/fetch.sh for every platform in upstream.json (sha256 verified;
#      about 20 MB from the kustomize release), then scripts/stage.sh;
#   4. named tests test/launcher.test.js over that staged launcher;
#   5. npm pack of every staged package, once;
#   6. named test scripts/smoke.sh for the gate host's platform: install the
#      packed tarballs into a scratch project, binaryPath(), the binary equals
#      the verified upstream one, `kustomize version`, `kustomize build`, and
#      no install script.
#
# The other three platforms' smoke runs in CI (pr.yml, build.yml).
# Needs network, bash, jq, tar, gzip, curl, node, npm and shellcheck.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
# The gate reports only the exit status; keep the full output for diagnosis.
mkdir -p build
exec > >(tee build/validate.log) 2>&1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) echo "validate: unsupported gate host OS $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64 | aarch64) cpu=arm64 ;;
  x86_64 | amd64) cpu=x64 ;;
  *) echo "validate: unsupported gate host CPU $(uname -m)" >&2; exit 1 ;;
esac
host="$os-$cpu"
jq -e --arg p "$host" '.assets | has($p)' upstream.json >/dev/null ||
  { echo "validate: no kustomize package is built for the gate host ($host)" >&2; exit 1; }

echo "== shellcheck"
shellcheck scripts/*.sh test/*.sh

echo "== named test: digest mismatch"
bash test/digest-mismatch.sh

echo "== fetch (sha256 verified) and stage"
bash scripts/fetch.sh "$work/upstream"
bash scripts/stage.sh "$work/upstream" "$work/npm"

echo "== named tests: launcher"
KUSTOMIZE_LAUNCHER_DIR="$work/npm/kustomize" node --test test/launcher.test.js

echo "== pack"
mkdir -p "$work/tgz"
for dir in "$work"/npm/*/; do
  npm pack "$dir" --pack-destination "$work/tgz" >/dev/null
done
ls -1 "$work/tgz"

echo "== named test: smoke on the gate host ($host)"
bash scripts/smoke.sh "$work/tgz" "$host"

echo "validate: OK"
