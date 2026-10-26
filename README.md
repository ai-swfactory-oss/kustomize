# kustomize

[![update](https://github.com/ai-swfactory-oss/kustomize/actions/workflows/update.yml/badge.svg)](https://github.com/ai-swfactory-oss/kustomize/actions/workflows/update.yml)
[![build](https://github.com/ai-swfactory-oss/kustomize/actions/workflows/build.yml/badge.svg)](https://github.com/ai-swfactory-oss/kustomize/actions/workflows/build.yml)

[kustomize](https://github.com/kubernetes-sigs/kustomize) (kubernetes-sigs/kustomize) as npm packages: the **native upstream binary** per platform, updated and published automatically to GitHub Packages. No WASM, no download at install time, no install scripts.

| Package | What |
|---|---|
| `@ai-swfactory-oss/kustomize` | Thin: the `kustomize` bin, and `binaryPath()` / `upstreamVersion` for Node. Depends optionally on the four platform packages, pinned exactly. |
| `@ai-swfactory-oss/kustomize-linux-x64` | `bin/kustomize` from upstream `kustomize_v<ver>_linux_amd64.tar.gz` |
| `@ai-swfactory-oss/kustomize-linux-arm64` | `bin/kustomize` from upstream `kustomize_v<ver>_linux_arm64.tar.gz` |
| `@ai-swfactory-oss/kustomize-darwin-x64` | `bin/kustomize` from upstream `kustomize_v<ver>_darwin_amd64.tar.gz` |
| `@ai-swfactory-oss/kustomize-darwin-arm64` | `bin/kustomize` from upstream `kustomize_v<ver>_darwin_arm64.tar.gz` |

npm installs only the platform package whose `os`/`cpu` match. Each binary is the unmodified `kustomize` from the upstream release archive, and that archive is verified against the sha256 digest pinned in [`upstream.json`](upstream.json). Windows is not packaged (the ruling scope is darwin and linux); upstream's `windows_amd64.zip` could be added as `win32-x64` later.

## Install

The packages live on GitHub Packages, which needs two things even for public packages.

1. The scope line, in your project's `.npmrc` (safe to commit):

   ```
   @ai-swfactory-oss:registry=https://npm.pkg.github.com
   ```

2. A token with `read:packages` (a classic personal access token), in your **user** `~/.npmrc`, never in the repository:

   ```
   //npm.pkg.github.com/:_authToken=<token>
   ```

   In GitHub Actions, use `actions/setup-node` with `registry-url: https://npm.pkg.github.com`, `scope: "@ai-swfactory-oss"` and `NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`, and grant the job `packages: read`.

Then:

```sh
npm install --save-dev @ai-swfactory-oss/kustomize
npx kustomize version
npx kustomize build overlays/prod
```

From Node, spawn the binary directly; there is no node process in between:

```js
const { spawnSync } = require('node:child_process');
const { binaryPath, upstreamVersion } = require('@ai-swfactory-oss/kustomize');

const built = spawnSync(binaryPath(), ['build', 'overlays/prod'], { encoding: 'utf8' });
```

- `binaryPath(platform = process.platform, arch = process.arch)` returns the absolute path of the binary.
  - It throws `UnsupportedPlatformError` (with `platform` and `arch`) when no binary is published for that os and cpu.
  - It throws `PlatformPackageMissingError` (with `platform`, `arch` and `packageName`) when one is published but its package is not installed, for example after `--omit=optional`.
- `upstreamVersion` is the kustomize version the binary reports, for example `5.8.3` (`kustomize version` prints `v5.8.3`).
- `supportedPlatforms` lists the `<os>-<cpu>` pairs a binary is published for.

Installing with `--omit=optional` (or `--no-optional`) leaves no binary; `kustomize` then says so and exits 1.

## Verify what you installed

The binaries are **upstream's release binaries, unmodified**. `scripts/fetch.sh` downloads each archive and refuses it unless its sha256 matches the digest pinned in [`upstream.json`](upstream.json); it then extracts the archive's single member, `kustomize`, and refuses an archive holding anything else. The pinned digest is the one the GitHub API reports for the asset, and the update workflow also checks it equals upstream's own `checksums.txt`. Nothing is rebuilt.

On top of that, every publish run creates **GitHub build-provenance attestations** ([`actions/attest-build-provenance`](https://github.com/actions/attest-build-provenance), SLSA provenance signed through Sigstore) for each npm tarball and each `kustomize` binary it publishes. Verify with the [GitHub CLI](https://cli.github.com/):

```sh
gh attestation verify node_modules/@ai-swfactory-oss/kustomize-linux-x64/bin/kustomize \
  --repo ai-swfactory-oss/kustomize \
  --signer-workflow ai-swfactory-oss/kustomize/.github/workflows/build.yml
```

To tie a binary back to upstream yourself, take the upstream archive named in the platform package's `NOTICE`. Check its sha256 against the digest there, extract it, then `cmp` its `kustomize` with the installed binary. Each GitHub release here also carries the original upstream archives.

The attestation proves that this repository's `build.yml` packaged the file from the named commit. It does not say who compiled kustomize: upstream did, and the pinned digest is what ties the binary to upstream's release.

## Versions

- The package version **equals the kustomize version** (`5.8.3`), for all five packages.
- A **re-pack** of the same kustomize release (a packaging fix only, rare) is published as `<version>-r.<n>`, for example `5.8.3-r.1`. You get one by setting `"repack": <n>` in `upstream.json`.
  - Semver orders `5.8.3-r.1` *below* `5.8.3`, so the publish job always passes the explicit dist-tag `latest`.
  - A range like `^5.8.3` does not select a re-pack; pin it exactly if you need it.
- Every published version has a GitHub release `v<package version>`.
- `packages/kustomize/package.json` carries no `version`: `scripts/stage.sh` sets it from `upstream.json` when it renders the launcher.

## How it stays up to date (no maintenance)

| Workflow | When | What |
|---|---|---|
| `update` | Daily 04:23 UTC; keepalive on the 1st of each month | Lists `kubernetes-sigs/kustomize` releases and keeps only non-prerelease `kustomize/v<semver>` tags (the repository also releases `api/`, `kyaml/` and `cmd/config/`). If the newest is newer than `upstream.json`, it rewrites `upstream.json` with the asset names and the sha256 digests the GitHub API reports for them, checks each against upstream's `checksums.txt`, and opens a pull request from `update/kustomize-<version>`. It then builds and tests that branch on every platform. Separately, if the GitHub release for main's version is missing, it runs `build` with publishing, so a failed publish is retried the next day. |
| `build` | Push to `main` touching `upstream.json`, `scripts/`, `packages/`, `test/` or the workflow; manual; called by `update` | Runs the named digest-mismatch test, fetches the four archives (failing on any sha256 mismatch or unexpected member), stages the packages, runs the launcher tests and packs once. Each platform runner installs the packed tarballs into a scratch project. There it checks `binaryPath()`, that the binary equals the one in a freshly verified archive, `kustomize version`, and a `kustomize build` with a name prefix and a patch. Publishing (never on pull requests) attests every tarball and binary, then pushes the tested tarballs to GitHub Packages, platform packages first, skipping versions that already exist. Last, it creates the release. |
| `pr` | Every pull request | `build` without publishing. |
| `failures` | After every `update` or `build` run on `main` | A failure opens one issue labelled `build-failure` (or comments on the open one); the next successful run closes it. |

A failing run publishes nothing new; the previous versions keep being served. Each release carries the npm tarballs as published, the original upstream archives and `SHA256SUMS` over all of them.

## Local build

```sh
bash test/digest-mismatch.sh                     # named test, offline
bash scripts/fetch.sh build/upstream             # download + verify + extract
bash scripts/stage.sh build/upstream build/npm   # render the packages
env KUSTOMIZE_LAUNCHER_DIR=build/npm/kustomize node --test test/launcher.test.js
npm pack ./build/npm/kustomize ./build/npm/kustomize-*/ --pack-destination dist/tgz
bash scripts/smoke.sh dist/tgz darwin-arm64      # install and test like CI
```

Needs `bash`, `curl`, `jq`, `tar` and Node.

## License

- The scripts and workflows in this repository are **MIT** (see [`LICENSE`](LICENSE)).
- The **npm packages are Apache-2.0**, the license of kustomize (Copyright The Kubernetes Authors). Each package ships the upstream `LICENSE` and a `NOTICE`. Upstream ships no `NOTICE` file of its own; the binary is not modified.

This project is not affiliated with the Kubernetes project or the CNCF.
