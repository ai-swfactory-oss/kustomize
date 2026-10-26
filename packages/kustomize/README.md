# @ai-swfactory-oss/kustomize

[kustomize](https://github.com/kubernetes-sigs/kustomize) (kubernetes-sigs/kustomize), Kubernetes native configuration management, as an npm package that runs the **native upstream binary** for your platform (no WASM, no download at install time, no install scripts).

Platforms: `linux-x64`, `linux-arm64`, `darwin-x64`, `darwin-arm64`. The binary comes from the matching optional dependency `@ai-swfactory-oss/kustomize-<platform>-<arch>`: the unmodified `kustomize` from the upstream release archive, verified against the archive's sha256 digest.

## Install

The packages are on GitHub Packages. Point the scope at it (in your project's `.npmrc`):

```
@ai-swfactory-oss:registry=https://npm.pkg.github.com
```

GitHub Packages requires a token even for public packages: a classic personal access token with `read:packages`, in your user `~/.npmrc` (never commit it):

```
//npm.pkg.github.com/:_authToken=<token>
```

In GitHub Actions, `actions/setup-node` with `registry-url: https://npm.pkg.github.com` and `NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` does this (the workflow needs `packages: read`).

```sh
npm install --save-dev @ai-swfactory-oss/kustomize
npx kustomize version
```

## Use

```sh
kustomize build overlays/prod
```

From Node, spawn the binary directly:

```js
const { binaryPath, upstreamVersion } = require('@ai-swfactory-oss/kustomize');
// binaryPath(): absolute path to the native kustomize binary for this os and cpu
// upstreamVersion: the kustomize version, e.g. "5.8.3"
```

`binaryPath()` throws `UnsupportedPlatformError` (with `platform` and `arch`) when no binary is published for this os and cpu, and `PlatformPackageMissingError` when one is but its package was not installed (for example with `--omit=optional`).

## Verify

Every published tarball and binary has a GitHub build-provenance attestation:

```sh
gh attestation verify node_modules/@ai-swfactory-oss/kustomize-linux-x64/bin/kustomize \
  --repo ai-swfactory-oss/kustomize
```

The binary itself is upstream's release binary, unmodified, its archive's sha256 pinned (see `NOTICE` in the platform package). Details: https://github.com/ai-swfactory-oss/kustomize#verify-what-you-installed

## Versions

The package version equals the kustomize version. A rare re-pack of the same kustomize release (packaging fix only) is published as `<version>-r.<n>` with the `latest` dist-tag.

## License

Apache-2.0, the license of kustomize. See `LICENSE` and `NOTICE`.
