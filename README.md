[![ci](https://github.com/okdp/platform-charts/actions/workflows/ci.yml/badge.svg)](https://github.com/okdp/platform-charts/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/okdp/platform-charts)](https://github.com/okdp/platform-charts/releases/latest)&ensp;&ensp;
[![Helm](https://img.shields.io/badge/helm-3%20%7C%204-blue.svg)](https://helm.sh/)&ensp;&ensp;
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.30+-blue.svg)](https://kubernetes.io/)&ensp;&ensp;
[![License Apache2](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)
<a href="https://okdp.io">
<img src="https://okdp.io/logos/okdp-notext.svg" height="20px" style="margin: 0 2px;" />
</a>

## Overview

This repository is a **catalog** of OKDP platform services: one package per
service version, in the format of
[`okdp-compile`](https://github.com/OKDP/okdp-compiler), which compiles the
values of an instance into the values of each upstream chart the service is
made of, OKDP's own objects and what the instance publishes. The upstream
charts are rendered as published, from their own repositories: nothing of
this repository is published as a chart, everything OKDP stays in Git.

A platform reads the catalog from Git: its `platform/catalog.yaml` lists the
catalog repositories (`repositories: [{name: platform-charts, url: <git url>,
ref: <branch|tag|commit>}]`), and the versions of a service are the
`catalog/<service>/<version>/` directories found at `ref`. Deploying the
instances is done from the deployments repositories, by Flux or Argo CD,
directly or through the OKDP console, which commits there. The reference
layout lives in [`OKDP/okdp-sandbox`](https://github.com/OKDP/okdp-sandbox)
(`gitops/`).

## Structure

```
catalog/<service>/<version>/   one package version, immutable once released
contracts/                     the contracts the packages provide or consume (<contract>.schema.json)
scripts/compile-charts.sh      compiles, checks and renders the test cases of packages (canonical copy)
```

| Service | Version | Upstream charts |
|---|---|---|
| [airflow](catalog/airflow/3.2.1-1.0.0) | `3.2.1-1.0.0` | `airflow` 1.22.0 (airflow.apache.org) |
| [hive-metastore](catalog/hive-metastore/4.0.1-1.0.0) | `4.0.1-1.0.0` | `hive-metastore` 1.4.0 (quay.io/okdp/charts) |
| [jupyterhub](catalog/jupyterhub/4.4.2-1.0.0) | `4.4.2-1.0.0` | `jupyterhub` 4.4.2 (hub.jupyter.org), `spark-rbac` 1.0.1 |
| [okdp-examples](catalog/okdp-examples/1.3.0-1.0.0) | `1.3.0-1.0.0` | `okdp-examples` 1.3.0 (quay.io/okdp/charts) |
| [polaris](catalog/polaris/1.3.0-incubating-1.0.0) | `1.3.0-incubating-1.0.0` | `polaris` 1.3.0-incubating (downloads.apache.org), `polaris-admin` 1.0.0 (twice: `polaris-admin`, `polaris-admin-principals`), `polaris-console` 0.3.0 |
| [spark-defaults](catalog/spark-defaults/1.0.0-1.0.0) | `1.0.0-1.0.0` | `spark-defaults` 1.0.0 (quay.io/okdp/charts) |
| [spark-history-server](catalog/spark-history-server/3.5.1-1.0.0) | `3.5.1-1.0.0` | `spark-history-server` 1.0.0, `spark-web-proxy` 0.1.0 (quay.io/okdp/charts) |
| [spark-operator](catalog/spark-operator/2.5.2-1.0.0) | `2.5.2-1.0.0` | `spark-operator` 2.5.2 (kubeflow.github.io) |
| [spark-rbac](catalog/spark-rbac/1.0.1-1.0.0) | `1.0.1-1.0.0` | `spark-rbac` 1.0.1 (quay.io/okdp/charts) |
| [superset](catalog/superset/6.0.0-1.0.0) | `6.0.0-1.0.0` | `superset` 0.22.8 (apache.github.io) |
| [trino](catalog/trino/480.0.0-1.0.0) | `480.0.0-1.0.0` | `trino` 1.42.2, `opa-kube-mgmt` 11.0.12, `opal` 0.0.30 |
| [okdp-control-plane-server](catalog/okdp-control-plane-server/0.9.0-1.0.0) | `0.9.0-1.0.0` | none: OKDP's own objects |
| [okdp-control-plane-ui](catalog/okdp-control-plane-ui/0.9.0-1.0.0) | `0.9.0-1.0.0` | none: OKDP's own objects |

A package (`catalog/<service>/<version>/`, laid out as a Helm umbrella chart
over its upstream charts, never packaged):

```
Chart.yaml                name: <service>, version: <version> (<upstream>-<okdp semver>),
                          dependencies: the upstream charts, each pinned in its own repository
okdp.yaml                 OKDP's part: roles and dependsOn (catalog metadata), require (platform
                          values), defaults, upstream (what an instance may set: protect, append),
                          then vars, errors, objects (OKDP's own objects), instance (URL, usage),
                          provides (connections published), oidcClients (OAuth clients)
values.cel.yaml           the values of each upstream chart, by dependency key, YAML + CEL
<key>.defaults.yaml       OKDP's defaults of the chart <key>, plain YAML
config.schema.json        the parameters: types, defaults, x-ui-* hints, x-okdp-connection-ref
README.md                 parameters, platform values read, charts, known gaps
ci/<case>-values.yaml     test instances (a first line "# error: <message>": a case that must fail)
ci/platform.yaml          the platform values of the cases (global.okdp), when they share them
ci/<case>-platform.yaml   a case's own platform values
ci/<case>-connections.yaml a case's own connections
```

The format is described in
[`okdp-compiler`](https://github.com/OKDP/okdp-compiler):
[writing a package](https://github.com/OKDP/okdp-compiler/blob/main/docs/02_writing_package.md),
[the service definition](https://github.com/OKDP/okdp-compiler/blob/main/docs/specs/02_service_definition.md),
[inputs and outputs](https://github.com/OKDP/okdp-compiler/blob/main/docs/specs/01_inputs_outputs.md).

## Values

A compile reads the context, by level: the platform's values (`global.okdp`:
ingress, OIDC, proxy, certificate issuers, storage classes) and connections,
a project's, an instance's own connections; then the instance's values, its
parameters and its upstream values (`upstream.<key>`). A connection
reference parameter names either a connection of the context or a provider
in the same namespace: for a contract with a naming convention (`hive`,
`iceberg-catalog`, `trino`), the release name of another OKDP instance,
resolved by the convention; for a contract without one (`s3`,
`database-server`), the name of an output another instance publishes. The
compiler resolves it against its contract (`contracts/`) before the mapping
runs, and prints the instances it depends on (on stderr), whose releases
this one waits for. A provider of another namespace is always a connection
of the context.

Each upstream chart then receives, merged in this order: its own defaults
(Helm applies them), OKDP's defaults (`<key>.defaults.yaml`), the values the
mapping computes (`values.cel.yaml`), and the instance's upstream values,
except the paths the package protects (`okdp.yaml`). The compiled values
hold no chart default.

Identity is Keycloak only: `global.okdp.oidc.clientProvisioning` is
`existing` (the OAuth client is created in Keycloak beforehand, its
credentials in a Secret) or `dcr` (dynamic client registration: the compiler
adds one oidc-dcr chart per client of the package's `oidcClients`, rendered
by the platform's oidc-dcr chart, `oci://quay.io/adaltas/oidc-dcr` 0.5.0 by
default).

OKDP's own objects (generated Secrets, hooks, custom resources, the control
plane's workloads) are the package's `objects`: the compiled umbrella renders
them from `okdp.objects.yaml`, as written. What an instance publishes (URL,
usage, provided connections), which the console lists, is
`okdp.info.yaml`, beside the compiled umbrella in the deployments
repository. Generated passwords come from External Secrets Operator
generators: a compile is deterministic, it never produces a secret.

Each upstream chart is rendered as a subchart of the instance's umbrella,
as published: under Helm 4, a null default nested in a map of a chart's
`values.yaml`, which the values leave unset, stays null in a subchart,
where the chart alone drops it. A template reads both alike, except with
`hasKey`, `toYaml` and `range` over the map.

## Working on a package

```bash
export OKDP_CONTRACTS=$PWD/contracts        # the contract schemas
export OKDP_CHARTS=~/.cache/okdp/charts     # the chart cache of the checks (helm pull --untar)
pkg=catalog/trino/480.0.0-1.0.0

# compile one test instance: the umbrella chart, its values, OKDP's objects
okdp-compile --package $pkg --context $pkg/ci/platform.yaml \
  --context $pkg/ci/opa-opal-platform.yaml -f $pkg/ci/opa-opal-values.yaml \
  --release demo-trino --namespace demo -o /tmp/demo-trino

# check it against the upstream charts' defaults and values.schema.json
okdp-compile --check --charts $OKDP_CHARTS --package $pkg ... (the same inputs, no -o)

# render it as a deployment does
chart=$(mktemp -d) && cp -R /tmp/demo-trino/. "$chart" && helm dependency build "$chart"
helm template demo-trino "$chart" -n demo -f /tmp/demo-trino/instance.values.yaml

# every test case of packages, compiled, checked and rendered
scripts/compile-charts.sh $pkg
scripts/compile-charts.sh catalog/*/*
```

`scripts/compile-charts.sh` documents its inputs in its header: it pulls the
charts the checks need into `$OKDP_CHARTS`, and needs `okdp-compile`
(`$OKDP_COMPILE`), `helm` and `yq`. The copies of the script in the other
OKDP catalog repositories must stay identical to this one, and so must the
contracts both catalogs hold.

A released version directory is immutable: a change of a service is a new
version, a copy of the directory under its new version (`Chart.yaml`
`version`). The upstream half of the version follows the main upstream
chart (`480.0.0` for Trino 480), the OKDP half is SemVer of the package.

## CI and releases

[`ci.yml`](.github/workflows/ci.yml) runs
[`catalog-template.yml`](.github/workflows/catalog-template.yml) on every
package on each pull request and push: it builds `okdp-compile` from
[okdp-compiler](https://github.com/OKDP/okdp-compiler) and runs
`scripts/compile-charts.sh catalog/*/*` (compile, check against the
upstream charts, render). Nothing is published.

[`release-please.yml`](.github/workflows/release-please.yml) releases the
repository as a whole: merging its release pull request tags `vX.Y.Z` and
updates `CHANGELOG.md`, a ref a platform's `catalog.yaml` can pin.
