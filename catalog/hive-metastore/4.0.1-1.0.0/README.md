# hive-metastore

OKDP package of the [Hive Metastore](https://hive.apache.org/): table schemas,
partitions and data locations for Trino, Spark and Hive, over an S3 warehouse
and a SQL database. It **provides** a `hive` connection and **consumes** a
`database-server` and an `s3` connection.

A package in the okdp-compiler format: `values.cel.yaml` computes the values
of the upstream chart
[`oci://quay.io/okdp/charts/hive-metastore`](https://github.com/okdp/hive-metastore)
1.4.0, the dependency of `Chart.yaml`, from the parameters below
(`config.schema.json`), over OKDP's defaults
(`hive-metastore.defaults.yaml`); `okdp.yaml` holds the rules of the
instance, what it publishes and what an instance may override.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `db` | (required) | `database-server` connection hosting the metastore schema. Its credentials Secret (`secretRef`) holds `username` and `password`. |
| `storage` | (required) | `s3` connection of the object store holding the warehouse. |
| `s3SecretRef` | (required) | Secret with `accessKey`/`secretKey`: this metastore's own S3 identity. |
| `warehouseBucket` | `hive` | Bucket used as the warehouse directory. |
| `cpu` | `0.5` | CPU request (vCPU); the limit is twice the request. |
| `memoryGi` | `0.5` | Memory request (GiB); the limit is twice the request. |

No platform value is read. The `database-server` and `s3` contracts have no
internal naming convention: `db` and `storage` name a connection
(`connections.<name>` of the platform, the project or the instance) or, by
its name, an output of another instance of the same namespace (e.g.
`demo-pg-hive`, a database of a cnpg-postgresql instance), whose release
this one then waits for. A provider of another namespace is always a
connection.

## Upstream values

Any value of the `hive-metastore` chart can be set per instance, under
`upstream.hive-metastore`, merged over the values computed from the
parameters (`upstream` in `okdp.yaml`):

```yaml
upstream:
  hive-metastore:
    image: {repository: mirror.example.org/okdp/hive-metastore}
    tolerations: [{key: dedicated, operator: Exists, effect: NoSchedule}]
    extraEnvRaw: [{name: HADOOP_HEAPSIZE, value: "2048"}]   # appended to the computed env
    s3: {requestTimeout: 60000}
```

The paths the platform relies on are refused (the Service name and port the
`hive` connection publishes, the database and S3 credentials, the storage
backend, the schema Job's hook annotations), and `extraEnvRaw`, which carries
the database user Secret, is appended to rather than replaced: see `protect`
and `append` in `okdp.yaml` (also listed in the schema description). An
upstream value wins over the parameter it overlaps (`resources` over
`cpu`/`memoryGi`). No key or value may contain `{{` (the schema and
okdp-compile both refuse it).

## Provided connection

`<release>` (contract `hive`), in `okdp.info.yaml`:

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

## Known gaps

What the okdp-lib-chart chart did to the rendered objects and values cannot
express:

- the values ConfigMap `<release>-hive-metastore-values` (audit of the merged
  values) is gone: the compiled values (`instance.values.yaml`) replace it.

## Tests

```sh
scripts/compile-charts.sh catalog/hive-metastore/4.0.1-1.0.0   # compile, check and render ci/*-values.yaml
```

`ci/no-connections-values.yaml` and `ci/db-without-secret-values.yaml` must
fail with the messages of the errors section.
