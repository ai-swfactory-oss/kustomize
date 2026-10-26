#!/usr/bin/env bash
# The single-quoted node programs are literal on purpose.
# shellcheck disable=SC2016
# Named test, per platform: installs the packed tarballs into a scratch project,
# as a consumer would, and checks that binaryPath() resolves to an executable
# file that is the unmodified upstream binary, that `kustomize version` prints
# upstreamVersion, and that it builds a kustomization.
#
#   scripts/smoke.sh <tgzdir> <platform>      e.g. dist/tgz linux-x64
#
# The pinned digest is the archive's, so the binary is checked against the
# binary inside a fresh, digest-verified copy of that archive (scripts/fetch.sh).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tgz=$(cd "${1:?usage: smoke.sh <tgzdir> <platform>}" && pwd)
platform=${2:?usage: smoke.sh <tgzdir> <platform>}
upstream=$(jq -er .version "$root/upstream.json")
version=$(bash "$root/scripts/pkgver.sh")

launcher="$tgz/ai-swfactory-oss-kustomize-$version.tgz"
native="$tgz/ai-swfactory-oss-kustomize-$platform-$version.tgz"

for f in "$launcher" "$native"; do
  test -f "$f" || { echo "smoke: missing $f" >&2; exit 1; }
  if tar -xzOf "$f" package/package.json | jq -e '.scripts // {} | keys | any(test("install"))' >/dev/null; then
    echo "smoke: $f declares an install script" >&2; exit 1
  fi
done

work=$(mktemp -d)
bash "$root/scripts/fetch.sh" "$work/upstream" "$platform"
reference="$work/upstream/$platform/kustomize"

cd "$work" || exit 1
printf '{"name":"smoke","version":"1.0.0","private":true}\n' >package.json
npm install --no-audit --no-fund "$launcher" "$native"

echo "== npm ls"
npm ls --all || true

echo "== binaryPath(), upstreamVersion and kustomize version"
node -e '
  const { execFileSync } = require("node:child_process");
  const fs = require("node:fs");
  const kustomize = require("@ai-swfactory-oss/kustomize");
  const [expected, reference] = process.argv.slice(1);
  if (kustomize.upstreamVersion !== expected) throw new Error(`upstreamVersion ${kustomize.upstreamVersion} != ${expected}`);
  const bin = kustomize.binaryPath();
  if (!fs.statSync(bin).isFile()) throw new Error(`${bin} is not a file`);
  fs.accessSync(bin, fs.constants.X_OK);
  if (!fs.readFileSync(bin).equals(fs.readFileSync(reference))) throw new Error(`${bin} is not the binary in the verified upstream archive`);
  const printed = execFileSync(bin, ["version"], { encoding: "utf8" }).trim();
  if (printed !== `v${expected}`) throw new Error(`${bin} version printed ${printed}, expected v${expected}`);
  console.log(bin, printed);
' "$upstream" "$reference"

echo "== kustomize command: build a kustomization"
bin="$work/node_modules/.bin/kustomize"
mkdir -p app
cat >app/configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: settings
data:
  mode: base
EOF
cat >app/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namePrefix: smoke-
resources:
  - configmap.yaml
patches:
  - patch: |-
      - op: replace
        path: /data/mode
        value: patched
    target:
      kind: ConfigMap
      name: settings
EOF
"$bin" build app >built.yaml
cat built.yaml
grep -qx '  name: smoke-settings' built.yaml || { echo "smoke: namePrefix not applied" >&2; exit 1; }
grep -qx '  mode: patched' built.yaml || { echo "smoke: patch not applied" >&2; exit 1; }

echo "smoke: $platform OK"
