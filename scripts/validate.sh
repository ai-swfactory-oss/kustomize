#!/usr/bin/env bash
# The repository's validate command (.panoptic.json "validate": "bash scripts/validate.sh"),
# run by `claude-factory work commit` on the gate host. It runs the same path
# the PR CI runs (build.yml), for the gate host's own platform, so the receipt
# covers the smoke and not only the offline tests:
#
#   1. shellcheck over every shell script, and a YAML syntax check of every
#      workflow in .github/workflows with the packaged yamllint
#      (@ai-swfactory-oss/yamllint, installed into a scratch prefix, never
#      globally). A known-bad fixture must fail it first, so the check is not
#      vacuous. A workflow GitHub cannot parse never runs. Then no script,
#      test or workflow may pipe into a reader that can exit before its input
#      ends (head, grep -q, a quitting sed, tar): under pipefail the writer
#      then fails on the closed pipe, at random. A fixture holding each form
#      must be flagged first;
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

echo "== workflow YAML syntax (packaged yamllint)"
yamllint_version=1.38.0
mkdir -p "$work/yamllint"
printf '{"name":"validate-yamllint","version":"1.0.0","private":true}\n' >"$work/yamllint/package.json"
# The scope's registry line comes from this repository's .npmrc; the token,
# if any, stays in the user's own ~/.npmrc.
cp .npmrc "$work/yamllint/.npmrc"
npm install --prefix "$work/yamllint" --no-save --no-audit --no-fund \
  "@ai-swfactory-oss/yamllint@$yamllint_version" >"$work/yamllint-install.log" 2>&1 ||
  { cat "$work/yamllint-install.log"; echo "validate: could not install @ai-swfactory-oss/yamllint@$yamllint_version" >&2; exit 1; }
yamllint="$work/yamllint/node_modules/.bin/yamllint"
[ -x "$yamllint" ] || { echo "validate: $yamllint is missing after install" >&2; exit 1; }
# Syntax only: no style rules, so only a document YAML cannot parse fails.
syntax_only='{rules: {}}'
printf 'jobs:\n  a:\n    steps:\n      - name: bad (linux: colon)\n' >"$work/bad-workflow.yml"
if "$yamllint" -d "$syntax_only" "$work/bad-workflow.yml" >"$work/bad-workflow.txt" 2>&1; then
  cat "$work/bad-workflow.txt"; echo "validate: yamllint accepted a workflow YAML cannot parse" >&2; exit 1
fi
cat "$work/bad-workflow.txt"
"$yamllint" -d "$syntax_only" .github/workflows/*.yml
echo "workflows: YAML syntax OK"

echo "== no pipe into an early-exiting reader"
# Write the producer's output to a file first, then read the file.
# A single bar (not ||), then the reader.
early_exit='(^|[^|])\|[[:space:]]*(head|tar|grep[[:space:]]+(-[A-Za-z]*q|--quiet)|sed[[:space:]][^|]*[0-9$/]q)([[:space:]]|$)'
# The fixture spells the bar through a variable so this file does not match.
bar='|'
printf '%s\n' "a $bar head -n1" "b $bar grep -q x" "c $bar grep -Eq x" "d $bar sed 1q" "e $bar tar -xf - m" >"$work/pipes-bad.sh"
grep -cE "$early_exit" "$work/pipes-bad.sh" >"$work/pipes-bad.count" || true
[ "$(cat "$work/pipes-bad.count")" = 5 ] || { echo "validate: the pipe check missed a fixture form" >&2; exit 1; }
# Comment lines are prose, not commands.
if grep -nE "$early_exit" scripts/*.sh test/*.sh .github/workflows/*.yml | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' >"$work/pipes.txt"; then
  cat "$work/pipes.txt"; echo "validate: a pipe ends in a reader that can exit early; write to a file first" >&2; exit 1
fi
echo "pipes: no early-exiting reader"

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
