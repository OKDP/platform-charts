# spark-operator

OKDP package of the [Kubeflow Spark Operator](https://github.com/kubeflow/spark-operator):
runs Spark applications on Kubernetes through the `SparkApplication`,
`ScheduledSparkApplication` and `SparkConnect` custom resources.

A package in the okdp-compiler format: `values.cel.yaml` computes the values
of the upstream chart `spark-operator` 2.5.2
(`https://kubeflow.github.io/spark-operator`, the dependency of `Chart.yaml`)
from the parameters below (`config.schema.json`), over OKDP's defaults
(`spark-operator.defaults.yaml`):

| Former module | Now | Rendered when |
|---|---|---|
| `noname` | chart `spark-operator` (kubeflow 2.5.2), its CRDs from the chart's `crds/` | always |

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `controllerReplicas` | `1` | Controller replicas. |
| `controllerLogLevel` | `info` | `debug`, `info`, `warn` or `error`. |
| `controllerWorkers` | `10` | Reconcile concurrency. |
| `jobNamespaces` | `[]` | Namespaces where Spark jobs run (they must exist). Empty, or containing `""`, allows all. |
| `webhookEnabled` | `true` | Admission webhook (validation, mutation). |
| `metricsEnabled` | `true` | Prometheus metrics. |
| `podMonitorEnabled` | `false` | PodMonitor (needs `metricsEnabled` and the Prometheus operator CRDs; the render fails without them). |

No platform value is read. No provided connection, no UI. The ServiceAccount
and RBAC of the jobs come from the `spark-rbac` service
(`spark.serviceAccount.create` / `spark.rbac.create` stay false).

## Upstream values

Any value of the `spark-operator` chart can be set per instance, under
`upstream.spark-operator`, merged over the values computed from the
parameters (`upstream` in `okdp.yaml`):

```yaml
upstream:
  spark-operator:
    image: {registry: mirror.example.org}
    controller:
      resources: {limits: {memory: 1Gi}}
      tolerations: [{key: dedicated, operator: Exists, effect: NoSchedule}]
      volumes: [{name: ivy, emptyDir: {}}]                # appended
      volumeMounts: [{name: ivy, mountPath: /opt/ivy}]
```

The paths the platform relies on are refused (names, `hook`, `certManager`,
`spark.jobNamespaces`, the job and operator ServiceAccounts and RBAC), and the
controller and webhook `volumes` and `volumeMounts` are appended to rather than
replaced: see `protect` and `append` in `okdp.yaml` (also listed in the schema
descriptions). `append` extends the package's lists, not the chart's default
ones, which Helm replaces: OKDP's defaults restate the chart's controller
`/tmp` and webhook serving certificates volumes, so that an instance's items
come after them. An upstream value wins
over the parameter it overlaps (`controller.replicas` over
`controllerReplicas`). Setting `controller.podSecurityContext` or
`webhook.podSecurityContext` replaces the null of OKDP's defaults: the chart's
`fsGroup: 185` does not come back unless written. No key or value may contain
`{{` (the schema and okdp-compile both refuse it).

## CRDs

The CRDs are the chart's `crds/` directory, rendered as the chart publishes
it: Helm installs them with the first release and never upgrades them, and
`helm template` prints them only with `--include-crds`. The upstream
pre-upgrade hook that would apply them (`hook.upgradeCrd`) stays off and
protected. Upgrading them with the release is a deployer setting:

- Flux: `upgrade.crds: CreateReplace` (and `install.crds: Create`, the
  default) on the instance's HelmRelease;
- Argo CD applies `crds/` on every sync; the CRDs exceed the client-side
  apply annotation limit, so the Application syncs with
  `ServerSideApply=true`.

Helm never deletes CRDs of `crds/`: uninstalling the release keeps them (and
every SparkApplication). Two instances in one cluster share the CRDs, as
before.

## Changes from the former package

- Resource names derive from the release `<project>-<instance>` (no KuboCD
  module suffix): `<release>-spark-operator-controller`, or
  `<release>-controller` when the release name contains `spark-operator`
  (upstream `fullname`).
- The CRDs are the chart's `crds/` again: they were moved into the chart's
  templates (`vendor.yaml` `crdsAsTemplates`), annotated
  `helm.sh/resource-policy: keep` and
  `argocd.argoproj.io/sync-options: Delete=false,ServerSideApply=true`, and
  upgraded by every `helm upgrade`. The chart is now rendered as published:
  the upgrade and Argo CD's server-side apply are the deployer's settings
  above.

## Tests

```sh
scripts/compile-charts.sh catalog/spark-operator/2.5.2-1.0.0   # compile, check and render ci/*-values.yaml
```
