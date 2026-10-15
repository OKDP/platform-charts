# spark-defaults

OKDP package of the Spark default properties of a namespace: ConfigMap
`spark-defaults` (key `spark-defaults.conf`) that Spark jobs mount.

A package in the okdp-compiler format: the former KuboCD module had static
(empty) values, and the upstream chart
[`oci://quay.io/okdp/charts/spark-defaults`](https://github.com/OKDP/okdp-sandbox)
1.0.0 was a plain Helm dependency. It is now the dependency `spark-defaults`
of `Chart.yaml`, whose values `values.cel.yaml` passes through from the
instance.

| Former module | Now | Rendered when |
|---|---|---|
| `main` | dependency `spark-defaults` (`oci://quay.io/okdp/charts` 1.0.0) | always |

## Parameters

None, as in the KuboCD package. The upstream values are reachable through the
`spark-defaults` key (not shown in the console, `{}` by default), passed to
the chart as they are, e.g.:

```yaml
spark-defaults:
  config:
    spark.eventLog.enabled: true
```

The chart accepts no `upstream.spark-defaults` values: the `spark-defaults`
parameter already carries any value of the chart.

## Notes

- The ConfigMap name `spark-defaults` is fixed by the upstream chart: one
  instance per namespace.
- No provided connection, no UI.

## Known gaps

None: the rendered objects are those of the former plain dependency (which
had no values ConfigMap either).

## Tests

```sh
scripts/compile-charts.sh catalog/spark-defaults/1.0.0-1.0.0   # compile, check and render ci/*-values.yaml
```
