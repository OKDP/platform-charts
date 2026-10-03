# spark-operator

OKDP chart of the [Kubeflow Spark Operator](https://github.com/kubeflow/spark-operator):
runs Spark applications on Kubernetes through the `SparkApplication`,
`ScheduledSparkApplication` and `SparkConnect` custom resources.

It renders the upstream chart `spark-operator` 2.5.2
(`https://kubeflow.github.io/spark-operator`), vendored under `vendor/` (see
`vendor.yaml`), with values computed from the parameters below (fixed ones in
`vendor-values/spark-operator.yaml`, computed ones in `templates/_values.tpl`).

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

Any value of the vendored `spark-operator` chart can be set per instance under
`upstream.spark-operator`, merged over the values computed from the parameters
(okdp-lib-chart `okdp.vendor.render`, option `upstream`):

```yaml
upstream:
  spark-operator:
    image: {registry: mirror.example.org}
    controller:
      resources: {limits: {memory: 1Gi}}
      tolerations: [{key: dedicated, operator: Exists, effect: NoSchedule}]
      volumes: [{name: ivy, emptyDir: {}}]                # appended to /tmp
      volumeMounts: [{name: ivy, mountPath: /opt/ivy}]
```

The paths the platform relies on are refused (names, `hook`, `certManager`,
`spark.jobNamespaces`, the job and operator ServiceAccounts and RBAC), and the
controller and webhook `volumes` and `volumeMounts` are appended to rather than
replaced (their vendored defaults carry the controller's `/tmp` and the
webhook's serving certificates): see `okdp-spark-operator.upstream` in
`templates/_values.tpl` (also listed in the schema descriptions). An upstream
value wins over the parameter it overlaps (`controller.replicas` over
`controllerReplicas`). Setting `controller.podSecurityContext` or
`webhook.podSecurityContext` replaces the null the chart computes: the vendored
`fsGroup: 185` does not come back unless written. No key or value may contain
`{{` (the schema and okdp-lib-chart both refuse it).

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
scripts/vendor-charts.sh charts/services/spark-operator   # download vendor/ (not committed)
helm dependency build charts/services/spark-operator
for f in charts/services/spark-operator/ci/*-values.yaml; do
  helm lint charts/services/spark-operator -f "$f"
  helm template demo-spark-operator charts/services/spark-operator -n demo -f "$f" >/dev/null
done
```
