#!/usr/bin/env bash
# The repository's validate command (.panoptic.json "validate": "bash scripts/validate.sh"),
# run by `claude-factory work commit` on the gate host. Offline and fast: it
# runs the named tests that need no network and no platform runner, and
# leaves the network-bound and per-platform checks (fetch, smoke) to CI
# (build.yml via pr.yml).
#
#   1. shellcheck over every shell script;
#   2. named test test/digest-mismatch.sh (a digest mismatch, or an archive
#      holding more than the binary, fails the fetch; the true digest passes);
#   3. named tests test/launcher.test.js, over a launcher staged by
#      scripts/stage.sh from a fixture fetch directory (fake binaries for every
#      platform in upstream.json, a fixture LICENSE), so stage.sh itself runs too.
#
# Needs bash, jq, tar, gzip, curl, node and shellcheck on the gate host.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
# The gate reports only the exit status; keep the full output for diagnosis.
mkdir -p build
exec > >(tee build/validate.log) 2>&1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "== shellcheck"
shellcheck scripts/*.sh test/*.sh

echo "== named test: digest mismatch"
bash test/digest-mismatch.sh

echo "== named tests: launcher (staged from a fixture fetch)"
for platform in $(jq -r '.assets | keys | join(" ")' upstream.json); do
  mkdir -p "$work/fetch/$platform"
  printf '#!/bin/sh\necho fixture\n' >"$work/fetch/$platform/kustomize"
  chmod 755 "$work/fetch/$platform/kustomize"
done
printf 'Apache License\nVersion 2.0, January 2004\n(fixture)\n' >"$work/fetch/LICENSE"
bash scripts/stage.sh "$work/fetch" "$work/npm" >/dev/null
KUSTOMIZE_LAUNCHER_DIR="$work/npm/kustomize" node --test test/launcher.test.js

echo "validate: OK"
