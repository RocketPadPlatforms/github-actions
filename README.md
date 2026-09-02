# GitHub Actions

Common, reusable GitHub Actions used across RocketPadPlatforms repositories.
This is the GitHub equivalent of the [`gitlab-ci-templates`](https://gitlab.com/rocketpadplatforms/gitlab-ci-templates)
repository on GitLab.

Every tool is installed by downloading its official pinned release binary
directly from GitHub Releases — there is no CI container image to build,
publish or keep in sync (unlike the previous `jsonnet-ci-image`). Pinned
versions are tracked and bumped automatically by [Renovate](./renovate.json).

## Access

This repository is **private**. For other private repositories in the
`RocketPadPlatforms` organization to be able to reference these actions with
`uses: RocketPadPlatforms/github-actions/...@<ref>`, this repository's
**Settings → Actions → General → Access** must be set to *"Accessible from
repositories in the RocketPadPlatforms organization"*.

## Actions

### Setup actions

Install a tool and add it to `PATH`. Useful when you need the raw binary for
custom scripting beyond what the task actions below cover.

| Action | Installs | Default version |
|---|---|---|
| [`actions/setup-jsonnet`](./actions/setup-jsonnet) | `jsonnet`, `jsonnetfmt`, `jsonnet-lint` ([google/go-jsonnet](https://github.com/google/go-jsonnet)) | `0.20.0` |
| [`actions/setup-kubeconform`](./actions/setup-kubeconform) | `kubeconform` ([yannh/kubeconform](https://github.com/yannh/kubeconform)) | `v0.8.0` |
| [`actions/setup-vendir`](./actions/setup-vendir) | `vendir` ([carvel-dev/vendir](https://github.com/carvel-dev/vendir)) | `0.46.0` |

```yaml
- uses: RocketPadPlatforms/github-actions/actions/setup-jsonnet@v0
  with:
    version: "0.20.0" # optional, this is the default
```

### Task actions

Higher-level actions that install the tool they need themselves and run one
specific job, mirroring the jobs previously defined in
`gitlab-ci-templates`/`.gitlab-ci.yml`.

| Action | Equivalent of | Description |
|---|---|---|
| [`actions/jsonnet-render`](./actions/jsonnet-render) | `.jsonnet` job | Renders a Jsonnet entrypoint to JSON/YAML. |
| [`actions/jsonnet-lint`](./actions/jsonnet-lint) | `jsonnet:lint` | Runs `jsonnet-lint` over a directory tree. |
| [`actions/jsonnet-fmt-check`](./actions/jsonnet-fmt-check) | `jsonnet:format` | Fails if `jsonnetfmt -i` would change any file. |
| [`actions/jsonnet-test`](./actions/jsonnet-test) | `jsonnet:test` | Evaluates every `*_test.jsonnet` file. |
| [`actions/kubeconform-validate`](./actions/kubeconform-validate) | `.kubeconform` | Validates a rendered manifest file with kubeconform, JUnit output. |
| [`actions/vendir-check`](./actions/vendir-check) | `vendir:check` | Fails if `deps/vendor/` drifted from `vendir.yml`/`vendir.lock.yml`. |

Example workflow (mirrors `base`'s current merge-request pipeline):

```yaml
name: CI

on:
  pull_request:

jobs:
  jsonnet-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: RocketPadPlatforms/github-actions/actions/jsonnet-lint@v0
        with:
          exclude-path: "./deps/*"

  jsonnet-format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: RocketPadPlatforms/github-actions/actions/jsonnet-fmt-check@v0

  jsonnet-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: RocketPadPlatforms/github-actions/actions/jsonnet-test@v0

  jsonnet-render-and-validate:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        root: ["true", "false"]
    steps:
      - uses: actions/checkout@v5
      - id: render
        uses: RocketPadPlatforms/github-actions/actions/jsonnet-render@v0
        with:
          file: test/main.jsonnet
          args: "--tla-code root=${{ matrix.root }}"
      - uses: RocketPadPlatforms/github-actions/actions/kubeconform-validate@v0
        with:
          file: ${{ steps.render.outputs.output-file }}
          kubernetes-version: "1.27.4"

  vendir-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: RocketPadPlatforms/github-actions/actions/vendir-check@v0
        with:
          github-token: ${{ secrets.VENDIR_GITHUB_TOKEN }} # only needed for private deps
```

## Versioning & tagging

Releases are cut automatically by [release-please](./.github/workflows/release-please.yml)
from [Conventional Commits](https://www.conventionalcommits.org/), starting
at `0.1.0`. Consumers should pin to a major version tag (currently `@v0`),
not `@main`, so that fixes and non-breaking improvements roll out
automatically while breaking changes require an explicit consumer opt-in
(bumping to `@v1` once this reaches a stable 1.0 release, and so on).

## Contributing

- `actionlint` runs in CI against every workflow and action file.
- Keep each action self-contained (its own `setup-*` call) so it also works
  standalone, not only when composed with the others.
