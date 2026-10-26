#!/usr/bin/env bash
# Single-quoted jq programs and Markdown backticks are literal on purpose.
# shellcheck disable=SC2016
# Renders the npm packages from the verified upstream release.
#
#   scripts/stage.sh <fetchdir> <outdir>
#
# <fetchdir> is the output of scripts/fetch.sh (every platform).
# Result: <outdir>/kustomize            the launcher (bin, binaryPath(), upstreamVersion)
#         <outdir>/kustomize-<platform> one package per platform binary
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest=${UPSTREAM_JSON:-$root/upstream.json}
fetched=${1:?usage: stage.sh <fetchdir> <outdir>}
out=${2:?usage: stage.sh <fetchdir> <outdir>}

scope=@ai-swfactory-oss
repo_url=https://github.com/ai-swfactory-oss/kustomize.git
upstream=$(jq -er .version "$manifest")
version=$(bash "$root/scripts/pkgver.sh")
read -r -a platforms <<<"$(jq -r '.assets | keys | join(" ")' "$manifest")"

common='{
  license: "Apache-2.0",
  author: "ai-swfactory",
  homepage: "https://github.com/ai-swfactory-oss/kustomize#readme",
  bugs: { url: "https://github.com/ai-swfactory-oss/kustomize/issues" },
  repository: { type: "git", url: $repo },
  publishConfig: { registry: "https://npm.pkg.github.com" }
}'

notice() { # <package name> <asset lines>
  cat "$root/packages/NOTICE.in"
  printf '\nThis package: %s %s, re-packaged from kustomize v%s.\n' "$1" "$version" "$upstream"
  printf 'Upstream release: https://github.com/kubernetes-sigs/kustomize/releases/tag/kustomize%%2Fv%s\n\n' "$upstream"
  printf '%s\n' "$2"
}

rm -rf "$out"
mkdir -p "$out"

optional='{}'
for platform in "${platforms[@]}"; do
  os=${platform%%-*}
  cpu=${platform#*-}
  binary=kustomize
  name="$scope/kustomize-$platform"
  asset=$(jq -er --arg p "$platform" '.assets[$p].name' "$manifest")
  digest=$(jq -er --arg p "$platform" '.assets[$p].digest' "$manifest")
  dir="$out/kustomize-$platform"

  mkdir -p "$dir/bin"
  cp "$fetched/$platform/$binary" "$dir/bin/$binary"
  chmod 755 "$dir/bin/$binary"
  cp "$fetched/LICENSE" "$dir/LICENSE"
  notice "$name" "Binary: bin/$binary, the unmodified kustomize binary from upstream asset $asset ($digest)." >"$dir/NOTICE"
  {
    printf '# %s\n\n' "$name"
    printf 'The native [kustomize](https://github.com/kubernetes-sigs/kustomize) v%s binary for `%s` / `%s`.\n\n' "$upstream" "$os" "$cpu"
    printf 'Do not install this package directly: install [`%s/kustomize`](https://github.com/ai-swfactory-oss/kustomize), which depends on it optionally and runs it.\n\n' "$scope"
    printf 'The binary is the unmodified `kustomize` from the upstream release archive `%s` (`%s`).\n\n' "$asset" "$digest"
    printf 'Provenance: `gh attestation verify bin/%s --repo ai-swfactory-oss/kustomize` (run in this package directory).\n\n' "$binary"
    printf 'License: Apache-2.0 (see `LICENSE` and `NOTICE`).\n'
  } >"$dir/README.md"

  jq -n --arg name "$name" --arg version "$version" --arg upstream "$upstream" \
    --arg os "$os" --arg cpu "$cpu" --arg binary "bin/$binary" --arg repo "$repo_url" \
    "{
      name: \$name,
      version: \$version,
      description: \"kustomize \(\$upstream) native binary for \(\$os)-\(\$cpu) (used by @ai-swfactory-oss/kustomize)\",
      keywords: [\"kustomize\", \"kubernetes\", \"yaml\"],
      os: [\$os],
      cpu: [\$cpu],
      files: [\$binary, \"LICENSE\", \"NOTICE\", \"README.md\"],
      preferUnplugged: true
    } + $common" >"$dir/package.json"

  optional=$(jq -c --arg n "$name" --arg v "$version" '. + {($n): $v}' <<<"$optional")
done

launcher="$out/kustomize"
mkdir -p "$launcher"
cp -R "$root/packages/kustomize/." "$launcher/"
cp "$fetched/LICENSE" "$launcher/LICENSE"
notice "$scope/kustomize" "This package holds no binary: it runs the one from $scope/kustomize-<platform>-<arch>." >"$launcher/NOTICE"
jq --arg version "$version" --arg repo "$repo_url" --argjson optional "$optional" \
  ". + {version: \$version, optionalDependencies: \$optional} + $common" \
  "$root/packages/kustomize/package.json" >"$launcher/package.json"
chmod 755 "$launcher/bin/kustomize.js"

echo "stage: $version ($upstream) -> $out"
ls -1 "$out"
