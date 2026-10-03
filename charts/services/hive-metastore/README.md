# hive-metastore

OKDP chart of the [Hive Metastore](https://hive.apache.org/): table schemas,
partitions and data locations for Trino, Spark and Hive, over an S3 warehouse
and a SQL database. It **provides** a `hive` connection and **consumes** a
`database-server` and an `s3` connection.

It renders the upstream chart
[`oci://quay.io/okdp/charts/hive-metastore`](https://github.com/okdp/hive-metastore)
1.4.0, vendored under `vendor/` (see `vendor.yaml`), with values computed from
the parameters below (`templates/_values.tpl`).

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `db` | (required) | `database-server` connection hosting the metastore schema. Its credentials Secret (`secretRef`) holds `username` and `password`. |
| `storage` | (required) | `s3` connection of the object store holding the warehouse. |
| `s3SecretRef` | (required) | Secret with `accessKey`/`secretKey`: this metastore's own S3 identity. |
| `warehouseBucket` | `hive` | Bucket used as the warehouse directory. |
| `cpu` | `0.5` | CPU request (vCPU); the limit is twice the request. |
| `memoryGi` | `0.5` | Memory request (GiB); the limit is twice the request. |

Platform values read from `global.okdp`: none beyond what the descriptor needs.
`db` and `storage` must be external connections (`connections.<name>`): the
`database-server` and `s3` contracts have no internal naming convention.

## Upstream values

Any value of the vendored `hive-metastore` chart can be set per instance under
`upstream.hive-metastore`, merged over the values computed from the parameters
(okdp-lib-chart `okdp.vendor.render`, option `upstream`):

```yaml
upstream:
  hive-metastore:
    image: {repository: mirror.example.org/okdp/hive-metastore}
    tolerations: [{key: dedicated, operator: Exists, effect: NoSchedule}]
    extraEnvRaw: [{name: HADOOP_HEAPSIZE, value: "2048"}]   # appended to the chart's env
    s3: {requestTimeout: 60000}
```

The paths the platform relies on are refused (the Service name and port the
`hive` connection publishes, the database and S3 credentials, the storage
backend, the schema Job's hook annotations), and `extraEnvRaw`, which carries
the database user Secret, is appended to rather than replaced: see
`hive-metastore.upstream` in `templates/_values.tpl` (also listed in the schema
description). An upstream value wins over the parameter it overlaps
(`resources` over `cpu`/`memoryGi`). No key or value may contain `{{` (the
schema and okdp-lib-chart both refuse it).

## Provided connection

`<release>` (contract `hive`):

```yaml
thriftUri: thrift://<release>-hive-metastore.<namespace>.svc:9083
```

A consumer in the same namespace references it by the release name
(`<project>-<instance>`, e.g. `demo-hive`), without a connection file.

## Hooks

The upstream schema initialisation Job is a `post-install,post-upgrade` hook
(Argo: PostSync, run on every sync). It is idempotent: it initialises the
schema only when `metastore_db_properties` is missing.

## Changes from the KuboCD package

- The Service is `<release>-hive-metastore` (was `<release>`), the name the
  `hive` contract's internal convention gives consumers.
- The connection published was `kcd-<release>-metastore`; it is now `<release>`.

## Tests

```sh
scripts/vendor-charts.sh charts/services/hive-metastore   # download vendor/ (not committed)
helm dependency build charts/services/hive-metastore
for f in charts/services/hive-metastore/ci/*-values.yaml; do
  helm lint charts/services/hive-metastore -f "$f"
  helm template demo-hive charts/services/hive-metastore -n demo -f "$f" >/dev/null
done
```
