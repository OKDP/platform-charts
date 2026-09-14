# spark-defaults

OKDP chart of the Spark default properties of a namespace: ConfigMap
`spark-defaults` (key `spark-defaults.conf`) that Spark jobs mount.

The former KuboCD module had static (empty) values, so the upstream chart
[`oci://quay.io/okdp/charts/spark-defaults`](https://github.com/OKDP/okdp-sandbox)
1.0.0 is a plain Helm dependency (no vendoring).

## Parameters

None, as in the KuboCD package. The upstream values are reachable through the
dependency slot `spark-defaults` (not shown in the console), e.g.:

```yaml
spark-defaults:
  config:
    spark.eventLog.enabled: true
```

## Notes

- The ConfigMap name `spark-defaults` is fixed by the upstream chart: one
  instance per namespace.
- No provided connection, no UI.

## Tests

```sh
helm dependency build charts/services/spark-defaults
for f in charts/services/spark-defaults/ci/*-values.yaml; do
  helm lint charts/services/spark-defaults -f "$f"
  helm template demo-spark-defaults charts/services/spark-defaults -n demo -f "$f" >/dev/null
done
```
