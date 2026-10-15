# okdp-examples

OKDP package seeding the medallion lakehouse examples: a
`post-install,post-upgrade` Job creates the buckets and the Spark event log
directory, downloads the NYC TLC trip data into the bronze bucket, declares
the bronze tables in Trino and provisions the Polaris realms (catalogs,
roles, principals). It **consumes** `s3`, `trino` and `iceberg-catalog`
connections and provides none.

A package in the okdp-compiler format: the former KuboCD module `main` is
the upstream chart `oci://quay.io/okdp/charts/okdp-examples` 1.3.0, the
dependency of `Chart.yaml`, whose values `values.cel.yaml` computes from the
parameters (`config.schema.json`), over OKDP's defaults
(`okdp-examples.defaults.yaml`).

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `storage` | (required) | `s3` connection (its `internalUrl`, else `apiUrl`). |
| `s3SecretRef` | (required) | Secret with `accessKey`/`secretKey`: the job's S3 identity. |
| `trino` | (required) | `trino` connection or trino release of this namespace (its `url`). |
| `trinoOidcSecretRef` | (required) | Secret with `client_id`/`client_secret` used against Trino. |
| `polaris` | (required) | `iceberg-catalog` connection or polaris release of this namespace (its `internalUri`, else `uri`, without `/api/catalog`). |
| `polarisRealms` | (required) | polaris-admin model; per realm one principal with role `catalog_admin` and `credentialsSecret: {name, clientIdKey, clientSecretKey}`. |
| `bronzeBucket` / `silverBucket` / `goldBucket` | `bronze` / `silver` / `gold` | Buckets. |
| `bronzePrefix` / `bronzeDataUrl` | `mobility/nyc_tlc` / NYC TLC CloudFront | Bronze layout and source. |
| `sparkEventsLogDir` | `s3a://spark-events/event-logs` | Created if missing. |
| `cpu` / `memoryGi` | `0.5` / `0.5` | Job requests; limits are twice the requests. |

Platform values read from `global.okdp`: `oidc.issuerUri`, `proxy`.

The chart signs no user in, so `oidc.clientProvisioning` changes nothing here:
`trinoOidcSecretRef` and the realm's `credentialsSecret` are service accounts
(client credentials grant) whose names the Trino OPA rules and the Polaris
principals refer to (`service-account-<client id>`), so they are created in
Keycloak beforehand in both modes, not registered by DCR (a registered client
gets a generated client id).

## Upstream values

Any value of the `okdp-examples` chart can be set per instance, under
`upstream.okdp-examples`, merged over the values computed from the parameters
(`upstream` in `okdp.yaml`):

```yaml
upstream:
  okdp-examples:
    image: {repository: mirror.example.org/okdp/okdp-examples}
    job: {backoffLimit: 4}
    tolerations: [{key: dedicated, operator: Exists, effect: NoSchedule}]
    extraEnvRaw: [{name: EXTRA_FLAG, value: "1"}]           # appended to the chart's env
    commands:                                               # an extra step
      04-custom: {01-hello: echo hello}
```

The paths the platform relies on are refused (the object names, the Job's hook
annotations, the realms file generated from `polarisRealms`), and the lists
carrying the chart's Secrets and CA bundle are appended to rather than
replaced: see `protect` and `append` in `okdp.yaml` (also listed in the
schema description). An upstream value wins over the parameter it overlaps
(`resources` over `cpu`/`memoryGi`), and a `commands` step of the same group
and name replaces the chart's. No key or value may contain `{{` (the schema and
okdp-compile both refuse it).

## Hooks

The seed Job is a `post-install,post-upgrade` hook (Argo: PostSync, run on
every sync), idempotent (`mc mb ... || true`, `CREATE ... IF NOT EXISTS`).

## Changes from the KuboCD package

- Objects are named after the release (`fullnameOverride`).
- The upstream chart still names its OPA ConfigMaps
  `okdp-examples-opa-trino-data|rules` whatever the release (pre-existing: two
  instances in one namespace collide).

## Known gaps

What the former packages did that the okdp-compiler format cannot express
the same way:

- the values ConfigMap `<release>-okdp-examples-values` is gone: the compiled
  values replace it.

## Tests

```sh
scripts/compile-charts.sh catalog/okdp-examples/1.3.0-1.0.0   # compile, check and render ci/*-values.yaml
```
