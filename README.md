[![ci](https://github.com/okdp/platform-charts/actions/workflows/ci.yml/badge.svg)](https://github.com/okdp/platform-charts/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/okdp/platform-charts)](https://github.com/okdp/platform-charts/releases/latest)&ensp;&ensp;
[![Helm](https://img.shields.io/badge/helm-3%20%7C%204-blue.svg)](https://helm.sh/)&ensp;&ensp;
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.30+-blue.svg)](https://kubernetes.io/)&ensp;&ensp;
[![License Apache2](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)
<a href="https://okdp.io">
<img src="https://okdp.io/logos/okdp-notext.svg" height="20px" style="margin: 0 2px;" />
</a>

## Overview

This repository builds and publishes the OKDP platform charts: one Helm chart per
platform service. They build on the `okdp-lib-chart` library chart, which lives in
[`OKDP/okdp-lib-chart`](https://github.com/OKDP/okdp-lib-chart).

It owns the charts only. Deploying them is done from a deployments Git repository,
by FluxCD (HelmRelease) or Argo CD (ApplicationSet), directly or through the OKDP
console, which commits to that repository. The reference layout lives in
[`OKDP/okdp-sandbox`](https://github.com/OKDP/okdp-sandbox) (`gitops/`). Both engines
render the same chart with the same values layers, so the result is identical.

## Structure

```
charts/
├── system/              # platform control plane
│   ├── okdp-control-plane-server/
│   └── okdp-control-plane-ui/
└── services/            # data and application services
    ├── airflow/  hive-metastore/  jupyterhub/  okdp-examples/  polaris/
    ├── spark-defaults/  spark-history-server/  spark-operator/  spark-rbac/
    └── superset/  trino/
scripts/vendor-charts.sh # downloads the vendored upstream charts (canonical copy)
```

A service chart (`charts/<category>/<name>/`):

```
Chart.yaml            version <upstream>-<okdp semver>, appVersion <upstream>
values.yaml           the service parameters (the former KuboCD parameters)
values.schema.json    draft-07, with the x-ui-* / x-okdp-* hints the console reads
vendor.yaml           upstream charts rendered with computed values
vendor/<name>/        their pristine unpacked copy (downloaded, not committed)
templates/            okdp-lib-chart calls, computed values, descriptor
ci/*-values.yaml      test values (each carries a global.okdp platform block)
README.md
```

See the [`okdp-lib-chart` README](https://github.com/OKDP/okdp-lib-chart#readme) for the values contract
(`global.okdp`, `connections`), the helpers, and how a KuboCD package translates.

## Values

Every chart receives three layers, in this order: the platform values
(`global.okdp`: ingress, OIDC, proxy, certificate issuers, storage classes), the
connection files the instance lists (`connections.<name>`), then the instance's own
parameters. A connection reference parameter names either a connection or another
OKDP instance of the same project (`hive`, `iceberg-catalog`, `trino`).

Identity is Keycloak only: `global.okdp.oidc.clientProvisioning` is `existing` (the
OAuth client is created in Keycloak beforehand, its credentials in a Secret) or
`dcr` (dynamic client registration: every chart that signs users in registers its
client with its own oidc-dcr Job `<release>-oidc-dcr`, see `okdp.vendor.oidcDcr`).

Every service chart renders a descriptor ConfigMap `<release>-okdp` (service,
version, URL, usage, provided connections) that the console lists.

## Working on a chart

The charts depend on `okdp-lib-chart` from the OCI registry
`oci://quay.io/okdp/okdp-lib-chart` (`helm dependency build` fetches it).

```bash
# upstream charts: download vendor/ (not committed) after a clone or a vendor.yaml change
scripts/vendor-charts.sh charts/services/trino

# render and lint
helm dependency build charts/services/trino
helm template demo-trino charts/services/trino -n demo -f charts/services/trino/ci/opa-opal-values.yaml
helm lint charts/services/trino -f charts/services/trino/ci/opa-opal-values.yaml
```

### Auditing the values of the upstream charts

Each vendored upstream chart is rendered with values computed by the wrapper
(`_values.tpl`), merged over its `values.yaml`. `okdp.vendor.render` writes
the result, what the upstream chart actually received, to a ConfigMap
`<release>-<chart>-values` (key `values.yaml`, label `okdp.io/vendor-values`),
so it can be read and diffed like a plain Helm `values.yaml`:

```bash
# offline, before committing: every render, or one (bare YAML, for diff)
scripts/show-values.sh charts/services/trino -f charts/services/trino/ci/opa-opal-values.yaml
diff <(scripts/show-values.sh --only trino charts/services/trino -f a.yaml) \
     <(scripts/show-values.sh --only trino charts/services/trino -f b.yaml)

# in the cluster
kubectl -n demo get cm -l okdp.io/vendor-values
kubectl -n demo get cm demo-trino-trino-values -o jsonpath='{.data.values\.yaml}'
```

As part of the release, the ConfigMap also shows in `helm get manifest` and in
Argo CD and Flux diffs. A chart rendering the same upstream chart twice names
each render (`"valuesName"`, see `polaris-admin.yaml`). See the
[`okdp-lib-chart` README](https://github.com/OKDP/okdp-lib-chart#readme) to
turn it off.

`vendor.yaml` entries take `name`, `repository` (`https://`, `oci://`, or
`file://` for a chart of this repository), `version`, optional `chart` (upstream
name) and optional `drop` (paths relative to the vendored chart root removed after
unpacking, e.g. `charts/postgresql`). The script header documents them; the copies
of `scripts/vendor-charts.sh` in the other OKDP chart repositories must stay
identical to this one.

Chart rules (enforced by CI, see
[`OKDP/gh-workflows`](https://github.com/OKDP/gh-workflows)): no `lookup`, no random
or time function, no `.Release.IsInstall`/`IsUpgrade`, hooks limited to
pre/post-install/upgrade (Argo CD renders with `helm template`). Generated
passwords come from External Secrets Operator generators (`okdp.generatedSecret`).
A justified exception in a vendored upstream chart goes in the chart's
`okdp-guard-allow.yaml`.

## CI and publishing

The workflows call the reusable
[`okdp-chart-ci.yml`](https://github.com/OKDP/gh-workflows#okdp-chart-ci-okdp-chart-ciyml)
of `OKDP/gh-workflows`: `vendor-charts.sh` (downloads `vendor/`), chart guard, schema check,
`helm dependency build`, `helm lint`, `helm template` with every `ci/*-values.yaml`,
`kubeconform`, then `helm package` + `helm push`.

| Workflow | When | Charts | Pushed to |
| --- | --- | --- | --- |
| [`ci.yml`](.github/workflows/ci.yml) | push, pull request | changed (a change under `.github/` selects every chart) | `oci://ghcr.io/okdp/platform-charts/charts`, version `0.0.0-ci.<branch>.g<sha>` |
| [`release-please.yml`](.github/workflows/release-please.yml) | release pull request merged | released paths | `oci://quay.io/okdp/platform-charts/<chart>`, `Chart.yaml` version |
| [`publish.yml`](.github/workflows/publish.yml) | manual | every chart, published versions skipped | same |

Versions: a service chart is `<upstream>-<okdp semver>` (e.g. `480.0.0-1.0.1`).
release-please owns the OKDP half in
[`.release-please-manifest.json`](.release-please-manifest.json);
[`compose-oci-tag.sh`](.github/scripts/compose-oci-tag.sh) writes the composite into
`Chart.yaml` on the release branch. `okdp-lib-chart` is released from its own
repository: a change there does not re-release these charts, bump their
`okdp-lib-chart` range or touch them to pick it up.

Fork pull requests are validated without pushing (their token cannot write packages).
