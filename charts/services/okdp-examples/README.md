# okdp-examples

OKDP chart seeding the medallion lakehouse examples: a
`post-install,post-upgrade` Job creates the buckets and the Spark event log
directory, downloads the NYC TLC trip data into the bronze bucket, declares
the bronze tables in Trino and provisions the Polaris realms (catalogs,
roles, principals). It **consumes** `s3`, `trino` and `iceberg-catalog`
connections and provides none.

The former KuboCD module `main` is the vendored chart
`oci://quay.io/okdp/charts/okdp-examples` 1.3.0 (`vendor.yaml`, `vendor/`),
rendered by `okdp.vendor.render` with computed values (`templates/_values.tpl`).

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

Any value of the vendored `okdp-examples` chart can be set per instance under
`upstream.okdp-examples`, merged over the values computed from the parameters
(okdp-lib-chart `okdp.vendor.render`, option `upstream`):

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
replaced: see `okdp-examples-wrapper.upstream` in `templates/_values.tpl` (also
listed in the schema description). An upstream value wins over the parameter it
overlaps (`resources` over `cpu`/`memoryGi`), and a `commands` step of the same
group and name replaces the chart's. No key or value may contain `{{` (the
schema and okdp-lib-chart both refuse it).

## Hooks

The seed Job is a `post-install,post-upgrade` hook (Argo: PostSync, run on
every sync), idempotent (`mc mb ... || true`, `CREATE ... IF NOT EXISTS`).

## Changes from the KuboCD package

- Objects are named after the release (`fullnameOverride`).
- The upstream chart still names its OPA ConfigMaps
  `okdp-examples-opa-trino-data|rules` whatever the release (pre-existing: two
  instances in one namespace collide).

## Tests

```sh
scripts/vendor-charts.sh charts/services/okdp-examples   # download vendor/ (not committed)
helm dependency build charts/services/okdp-examples
for f in charts/services/okdp-examples/ci/*-values.yaml; do
  helm lint charts/services/okdp-examples -f "$f"
  helm template demo-examples charts/services/okdp-examples -n demo -f "$f" >/dev/null
done
```
