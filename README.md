[![ci](https://github.com/okdp/platform-charts/actions/workflows/ci.yml/badge.svg)](https://github.com/okdp/platform-charts/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/okdp/platform-charts)](https://github.com/okdp/platform-charts/releases/latest)&ensp;&ensp;
[![KuboCD](https://img.shields.io/badge/kubocd-v0.3.2-green.svg)](https://github.com/kubocd/kubocd)&ensp;&ensp;
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.28+-blue.svg)](https://kubernetes.io/)&ensp;&ensp;
[![License Apache2](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)
<a href="https://okdp.io">
<img src="https://okdp.io/logos/okdp-notext.svg" height="20px" style="margin: 0 2px;" />
</a>

## Overview

This repository builds and publishes the OKDP platform packages used to operate platform services with [KuboCD](https://www.kubocd.io/).

It is **packages-only**: it owns the package definitions under `charts/`, the Helm charts under `charts/` that some of them bundle, and the CI that builds and publishes the result as OCI artifacts. It does **not** own the deployment layer (releases, contexts, Flux/KuboCD bootstrap). Deployment lives in [`OKDP/okdp-sandbox`](https://github.com/OKDP/okdp-sandbox), which consumes the packages published here.

## KuboCD Concepts

- **Package**: a versioned OCI artifact that bundles a KuboCD application descriptor and one or more Helm charts. The manifests under `charts/` define the packages published by this repository.
- **Connection**: a typed endpoint identified by a contract. A package consumes one through a `connectionRef` parameter and publishes one through `outputs`. The contracts used here are `s3`, `database-server`, `hive`, `iceberg-catalog` and `trino`.

Packages are deployed through KuboCD **Releases** that reference layered **Contexts**. Those deployment resources are maintained in [`OKDP/okdp-sandbox`](https://github.com/OKDP/okdp-sandbox), not here.

## Structure

```
charts/                 # Helm charts owned here, bundled into the packages that reference them
├── internal-secrets/
└── oidc-client/
charts/
├── system/             # Platform foundation packages
│   ├── okdp-control-plane-server/
│   └── okdp-control-plane-ui/
└── services/           # Data and application service packages
    ├── airflow/
    ├── hive-metastore/
    ├── jupyterhub/
    ├── okdp-examples/
    ├── polaris/
    ├── spark-defaults/
    ├── spark-history-server/
    ├── spark-operator/
    ├── spark-rbac/
    ├── superset/
    └── trino/
platform-packages-values.yaml   # OCI publish target (packageRepository), the source of truth used by CI
```

Key paths:

- [`charts/system`](./charts/system): platform foundation packages.
- [`charts/services`](./charts/services): data and application service packages.
- [`charts`](./charts): Helm charts maintained in this repository. Packages pull them through `source.local.path` and the build bundles them into the OCI artifact.
- [`platform-packages-values.yaml`](./platform-packages-values.yaml): the OCI repository packages are published to.

## Building Packages

The OCI repository packages are published to is defined once in [`platform-packages-values.yaml`](./platform-packages-values.yaml) (`packageRepository`). Use the same value for local builds.

### Basic Build Command

```bash
# Build a system package
kubocd package ./charts/system/okdp-control-plane-server/okdp-control-plane-server.yaml --ociRepoPrefix quay.io/okdp/platform-charts

# Build a service package
kubocd package ./charts/services/superset/superset.yaml --ociRepoPrefix quay.io/okdp/platform-charts
```

### Custom OCI Repository

```bash
# Using a different OCI registry
kubocd package ./charts/system/okdp-control-plane-ui/okdp-control-plane-ui.yaml --ociRepoPrefix myregistry.io/my-org/packages

# Using a different prefix for packages
kubocd package ./charts/services/jupyterhub/jupyterhub.yaml --ociRepoPrefix harbor.company.com/okdp-prod
```

### Examples

```bash
# Build all system packages
for pkg in charts/system/*/; do
  kubocd package "$pkg"*.yaml --ociRepoPrefix quay.io/okdp/platform-charts
done

# Build specific package
kubocd package ./charts/services/jupyterhub/jupyterhub.yaml --ociRepoPrefix quay.io/okdp/platform-charts
```

### Build Output

Packages are pushed to: `{ociRepoPrefix}/{package-name}:{tag}`

Example: `quay.io/okdp/platform-charts/superset:6.0.0-p02`

## GitHub CI and Publishing

The GitHub workflows share the reusable [`kubocd-package-template.yml`](./.github/workflows/kubocd-package-template.yml) workflow for both CI validation and publishing.

### CI Workflow

[`ci.yml`](./.github/workflows/ci.yml) runs on pushes, pull requests, and manual dispatch. It:

- reads the OCI package prefix from [`platform-packages-values.yaml`](./platform-packages-values.yaml);
- builds **every** package manifest under `charts/` that contains `modules:`;
- pushes CI test packages to the repository-scoped GitHub Container Registry path.

Building covers every package, so packaging errors are caught repo-wide. Deployment of the published packages (Flux/KuboCD bootstrap, contexts, releases) and its end-to-end validation live in [`OKDP/okdp-sandbox`](https://github.com/OKDP/okdp-sandbox), not here.

The KuboCD package CI job is skipped for fork pull requests because GitHub intentionally gives those runs a read-only token, which cannot push to GHCR.

### CI Registry

The `ci` workflow builds packages for CI validation and pushes them to the repository-scoped GitHub Container Registry path:

```text
ghcr.io/okdp/platform-charts/platform-charts/{package-name}:{tag}
```

### Release Publishing

Published release packages use the public repository from [`platform-packages-values.yaml`](./platform-packages-values.yaml):

```text
quay.io/okdp/platform-charts/{package-name}:{tag}
```

[`publish.yml`](./.github/workflows/publish.yml) can be dispatched manually and publishes packages to Quay using `REGISTRY_USERNAME` and `REGISTRY_ROBOT_TOKEN`. [`release-please.yml`](./.github/workflows/release-please.yml) triggers it when Release Please creates a new release after a merged pull request.
