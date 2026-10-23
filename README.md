# GitHub Actions

Common, reusable GitHub Actions used across RocketPadPlatforms repositories. This is the GitHub equivalent of the [`gitlab-ci-templates`](https://gitlab.com/rocketpadplatforms/gitlab-ci-templates) repository on GitLab.

Every tool is installed by downloading its official pinned release binary directly from GitHub Releases — there is no CI container image to build, publish or keep in sync (unlike the previous `jsonnet-ci-image`). Pinned versions are tracked and bumped automatically by [Renovate](./renovate.json).

## Actions

### Setup actions

Install a tool and add it to `PATH`. Useful when you need the raw binary for
custom scripting beyond what the task actions below cover.

| Action | Installs |
|---|---|
| [`actions/setup-jsonnet`](./actions/setup-jsonnet) | `jsonnet`, `jsonnetfmt`, `jsonnet-lint` ([google/go-jsonnet](https://github.com/google/go-jsonnet)) |
| [`actions/setup-kubeconform`](./actions/setup-kubeconform) | `kubeconform` ([yannh/kubeconform](https://github.com/yannh/kubeconform)) |
| [`actions/setup-vendir`](./actions/setup-vendir) | `vendir` ([carvel-dev/vendir](https://github.com/carvel-dev/vendir)) |
| [`actions/setup-opentofu`](./actions/setup-opentofu) | `tofu` ([opentofu/opentofu](https://github.com/opentofu/opentofu)) |

```yaml
- uses: RocketPadPlatforms/github-actions/actions/setup-jsonnet@v1
  with:
    version: "0.20.0"
```

### Task actions

Higher-level actions that install the tool they need themselves and run one specific job, mirroring the jobs previously defined in `gitlab-ci-templates`/`.gitlab-ci.yml`.

| Action | Equivalent of | Description |
|---|---|---|
| [`actions/jsonnet-render`](./actions/jsonnet-render) | `.jsonnet` job | Renders a Jsonnet entrypoint to JSON/YAML. |
| [`actions/jsonnet-lint`](./actions/jsonnet-lint) | `jsonnet:lint` | Runs `jsonnet-lint` over a directory tree. |
| [`actions/jsonnet-fmt-check`](./actions/jsonnet-fmt-check) | `jsonnet:format` | Fails if `jsonnetfmt -i` would change any file. |
| [`actions/jsonnet-test`](./actions/jsonnet-test) | `jsonnet:test` | Evaluates every `*_test.jsonnet` file. |
| [`actions/kubeconform-validate`](./actions/kubeconform-validate) | `.kubeconform` | Validates a rendered manifest file with kubeconform, JUnit output. |
| [`actions/vendir-check`](./actions/vendir-check) | `vendir:check` | Fails if `deps/vendor/` drifted from `vendir.yml`/`vendir.lock.yml`. |
| [`actions/opentofu-fmt-check`](./actions/opentofu-fmt-check) | `.opentofu:fmt` | Fails if `tofu fmt -recursive` would change any file. |
| [`actions/opentofu-validate`](./actions/opentofu-validate) | `.opentofu:validate` | Runs `tofu init -backend=false` + `tofu validate`. |
| [`actions/github-app-git-auth`](./actions/github-app-git-auth) | n/a | Mints a GitHub App installation token and configures git to use it for `github.com` HTTPS fetches (e.g. private Terraform module sources). |
| [`actions/kind-registry-mirror`](./actions/kind-registry-mirror) | n/a | Makes a kind cluster's nodes pull images through a registry mirror (pull-through cache), with fallback to the registries. See [below](#kind-registry-mirror). |

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
      - uses: RocketPadPlatforms/github-actions/actions/jsonnet-lint@v1
        with:
          exclude-path: "./deps/*"

  jsonnet-format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: RocketPadPlatforms/github-actions/actions/jsonnet-fmt-check@v1

  jsonnet-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: RocketPadPlatforms/github-actions/actions/jsonnet-test@v1

  jsonnet-render-and-validate:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        root: ["true", "false"]
    steps:
      - uses: actions/checkout@v5
      - id: render
        uses: RocketPadPlatforms/github-actions/actions/jsonnet-render@v1
        with:
          file: test/main.jsonnet
          args: "--tla-code root=${{ matrix.root }}"
      - uses: RocketPadPlatforms/github-actions/actions/kubeconform-validate@v1
        with:
          file: ${{ steps.render.outputs.output-file }}
          kubernetes-version: "1.27.4"

  vendir-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: RocketPadPlatforms/github-actions/actions/vendir-check@v1
        with:
          github-token: ${{ secrets.VENDIR_GITHUB_TOKEN }} # only needed for private deps
          # Only for dependencies whose upstream moves the locked ref (e.g. a
          # re-created tag), so the locked commit can't be fetched anymore.
          # They are refreshed, not compared against the committed files.
          unpinned-paths: |
            vendor/github.com/org/repo/dir
```

Example Terraform/OpenTofu module workflow:

```yaml
name: CI

on:
  pull_request:

jobs:
  fmt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: RocketPadPlatforms/github-actions/actions/opentofu-fmt-check@v1

  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      # Only needed if a module source in this configuration points at a
      # private repository (e.g. git::https://github.com/OWNER/private-module.git).
      - uses: RocketPadPlatforms/github-actions/actions/github-app-git-auth@v1
        with:
          app-id: ${{ secrets.RPP_CI_REPO_READER_APP_ID }}
          private-key: ${{ secrets.RPP_CI_REPO_READER_PRIVATE_KEY }}
          repositories: private-module
      - uses: RocketPadPlatforms/github-actions/actions/opentofu-validate@v1
```

### kind-registry-mirror

Anonymous pulls from Docker Hub and other public registries are rate
limited. A kind cluster that deploys many images can hit those limits,
especially when several jobs run at once from the same address. This
action points the containerd of every kind node at a pull-through cache.

For each entry in `registries`, every node gets
`/etc/containerd/certs.d/<registry>/hosts.toml`:

```toml
server = "https://registry-1.docker.io"

[host."<mirror>/v2/docker.io"]
  capabilities = ["pull", "resolve"]
  override_path = true
```

containerd tries the mirror first and falls back to `server` when the
mirror fails, so an outage of the mirror only brings back the rate limits.
containerd reads these files on every pull; no restart is needed.

Requirements:

- The kind config must make containerd read this directory:

  ```yaml
  containerdConfigPatches:
  - |-
    [plugins."io.containerd.cri.v1.images".registry]
      config_path = "/etc/containerd/certs.d"
  ```

- The mirror serves each upstream under a path prefix named after the
  registry (`<mirror>/v2/docker.io/library/redis/...`) and allows anonymous
  reads. With [zot](https://zotregistry.dev/), that is an on-demand `sync`
  entry per upstream with `"destination": "/<registry>"` and
  `http.compat: ["docker2s2"]`; see
  [the test configuration](./.github/tests/kind-registry-mirror/zot-config.json).
- The mirror is reachable from the kind nodes. The action checks
  `<mirror>/v2/` from the first node. If it does not answer within
  `timeout` seconds, the action only logs a warning and changes nothing.

With an empty `mirror` the action does nothing, so a repository variable
can switch it on and off:

```yaml
- uses: helm/kind-action@v1.15.1
  with:
    config: kind-config.yaml # with the containerdConfigPatches above
- uses: RocketPadPlatforms/github-actions/actions/kind-registry-mirror@v1
  with:
    mirror: ${{ vars.REGISTRY_MIRROR }}
```

Inputs:

| Input | Default | Description |
|---|---|---|
| `mirror` | `""` | Base URL of the mirror. Empty skips the action. |
| `registries` | `docker.io`, `public.ecr.aws`, `quay.io`, `ghcr.io`, `registry.k8s.io` | One `registry=upstream-url` per line, e.g. `docker.io=https://registry-1.docker.io`. |
| `cluster-name` | `chart-testing` | Name of the kind cluster (kind-action's default). |
| `timeout` | `10` | Seconds to wait for `<mirror>/v2/`. |

Images pulled by the runner's Docker daemon, such as the kind node image,
are not affected.

## Versioning & tagging

Releases are cut automatically by [release-please](./.github/workflows/release-please.yml) from [Conventional Commits](https://www.conventionalcommits.org/). Consumers should pin to a major version tag (e.g. `@v1`), not `@main`, so that fixes and non-breaking improvements roll out automatically while breaking changes require an explicit consumer opt-in (bumping to the next major version).

## Contributing

- `actionlint` runs in CI against every workflow and action file.
- Keep each action self-contained (its own `setup-*` call) so it also works standalone, not only when composed with the others.
