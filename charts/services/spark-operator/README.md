# spark-operator

OKDP chart of the [Kubeflow Spark Operator](https://github.com/kubeflow/spark-operator):
runs Spark applications on Kubernetes through the `SparkApplication`,
`ScheduledSparkApplication` and `SparkConnect` custom resources.

It renders the upstream chart `spark-operator` 2.5.2
(`https://kubeflow.github.io/spark-operator`), vendored under `vendor/` (see
`vendor.yaml`), with values computed from the parameters below
(`templates/_values.tpl`).

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

## CRDs

Helm installs the `crds/` directory of the chart being installed only, and
`okdp.vendor.render` renders `templates/`: `templates/crds.yaml` renders
`vendor/spark-operator/crds/*.yaml` as regular objects, annotated with
`helm.sh/resource-policy: keep` and
`argocd.argoproj.io/sync-options: Delete=false,ServerSideApply=true`:

- uninstalling the release keeps the CRDs (and every SparkApplication), as
  Helm does with `crds/`;
- Argo applies them server-side (they exceed the client-side apply annotation
  limit);
- they are upgraded with the chart, where the KuboCD module installed them once
  (`hook.upgradeCrd` stays false).

Two instances in one cluster share the CRDs and fight over them, as before.

## Changes from the KuboCD package

- Resource names derive from the release `<project>-<instance>` (no KuboCD
  module suffix): `<release>-spark-operator-controller`, or
  `<release>-controller` when the release name contains `spark-operator`
  (upstream `fullname`).
- CRDs as above.

## Tests

```sh
helm dependency build charts/services/spark-operator
for f in charts/services/spark-operator/ci/*-values.yaml; do
  helm lint charts/services/spark-operator -f "$f"
  helm template demo-spark-operator charts/services/spark-operator -n demo -f "$f" >/dev/null
done
scripts/vendor-charts.sh --check charts/services/spark-operator
```
