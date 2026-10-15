# polaris

OKDP package of [Apache Polaris](https://polaris.apache.org/), an Iceberg REST
catalog, with its console. It **provides** an `iceberg-catalog` connection and
**consumes** a `database-server` (PostgreSQL) and an `s3` connection.

A package in the okdp-compiler format: the former KuboCD modules are the
upstream charts of `Chart.yaml`, whose values `values.cel.yaml` computes from
the parameters below (`config.schema.json`), over OKDP's defaults
(`<key>.defaults.yaml`, named in `okdp.yaml`; one file per polaris-admin
render). A chart rendered twice is two dependencies of `Chart.yaml`:
polaris-admin, under the keys `polaris-admin` (bootstrap) and
`polaris-admin-principals` (its alias). The compiler adds the OAuth clients'
charts (`oidcClients` of `okdp.yaml`); OKDP's own objects are in the `objects`
of `okdp.yaml`, rendered by the umbrella (`okdp.objects.yaml`):

| Former module | Now | Rendered as |
|---|---|---|
| internal-secrets | `objects` | ESO `Password` + `ExternalSecret` `<release>-root` |
| bootstrap | key `polaris-admin` (`oci://quay.io/okdp/charts/polaris-admin` 1.0.0), `phase: bootstrap` | Job `<release>-bootstrap`, post-install/post-upgrade hook, weight -5 |
| main | key `polaris` (`polaris` 1.3.0-incubating, `https://downloads.apache.org/polaris/helm-chart/`) | `<release>-polaris`, ingress `polaris-<namespace>.<suffix>` |
| principals | key `polaris-admin-principals` (the polaris-admin chart again, its alias), `phase: principals` | Job `<release>-principals`, post-install/post-upgrade hook, weight 5 (only with principals) |
| console | key `polaris-console` (`oci://quay.io/okdp/charts/polaris-console` 0.3.0) | `<release>-polaris-console`, ingress `polaris-console-<namespace>.<suffix>` |
| (new) oidc-dcr | the `oidcClients` of `okdp.yaml`, two clients: the compiler adds the charts `oidc-dcr` and `console-oidc-dcr`, both rendered by the platform's oidc-dcr chart (`oci://quay.io/adaltas/oidc-dcr` 0.5.0 by default) | Jobs `<release>-oidc-dcr` and `<release>-console-oidc-dcr` (pre-install/pre-upgrade hooks), only with `global.okdp.oidc.clientProvisioning: dcr` |

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `db` | (required) | `database-server` connection (engine `postgresql`) hosting the metastore. Its Secret (`secretRef`) holds `username` and `password`. |
| `storage` | (required) | `s3` connection backing the catalogs (`apiUrl`, `region`). |
| `s3SecretRef` | (required) | Secret with `accessKey`/`secretKey`: this instance's own S3 identity (STS, metadata). |
| `realm` | `default` | Realm served, published in the connection. `^[A-Za-z0-9_.-]+$` (the polaris-admin Jobs pass it to a shell). |
| `principals` | `[]` | `[{name, roles: [...]}]` created in the realm by the principals Job. Names and roles match `^[A-Za-z0-9_.-]+$` (the Job interpolates them into a shell script). |
| `memoryGi` | `1` | Server memory limit (GiB); request 512Mi. |

Platform values read from `global.okdp`: `ingress.suffix`, `ingress.className`,
`certificateIssuers.selfSigned.name`, `oidc.issuerUri`, `oidc.scope`,
`oidc.clientProvisioning`, `oidc.dcr.registrationUrl|authMethod` (dcr). The CA
bundle comes from Secret `certs-bundle` (the DCR Jobs read it too).

OAuth clients:

- `clientProvisioning: existing`: the server's from Secret `creds-<release>-oauth2`
  (`client_id`, `client_secret`); the console signs users in with the public
  client `polaris-console`, created in Keycloak beforehand.
- `clientProvisioning: dcr`: both are registered anonymously. The server's
  (confidential, grant `client_credentials`, no redirect URI) by the Job
  `<release>-oidc-dcr` (chart `oidc-dcr`) into
  Secret `<release>-<namespace>-dcr`, same keys; the console's (public,
  `token_endpoint_auth_method: none`, redirect URI
  `https://polaris-console-<namespace>.<suffix>/auth/callback`, grants
  `authorization_code` and `refresh_token`, the platform scopes but `openid`, plus
  `roles offline_access`) by the Job `<release>-console-oidc-dcr` (chart
  `console-oidc-dcr`) into Secret `<release>-<namespace>-console-dcr`
  (`client_id`), which the console's `VITE_OIDC_CLIENT_ID` reads (`extraEnv`
  `valueFrom`, polaris-console 0.3.0 or later).

## Upstream values

Any value of the `polaris`, `polaris-console` and `polaris-admin` charts can
be set per instance, under `upstream.<key>`, merged over the values computed
from the parameters (`upstream` in `okdp.yaml`):

```yaml
upstream:
  polaris:
    image: {repository: mirror.example.org/apache/polaris}
    tolerations: [{key: dedicated, operator: Exists, effect: NoSchedule}]
    extraEnv: [{name: EXTRA_FLAG, value: "1"}]        # appended to the chart's extraEnv
    authentication:
      tokenBroker: {secret: {name: polaris-token-keys}} # one key pair for every replica
  polaris-console:
    resources: {limits: {memory: 256Mi}}
  polaris-admin:                                      # both Jobs: bootstrap and principals
    bootstrap: {backoffLimit: 3}
```

The paths the platform relies on are refused, and the lists carrying the
chart's Secrets are appended to rather than replaced: see `protect` and
`append` in `okdp.yaml` (also listed in the schema descriptions).
`upstream.polaris-admin` applies to both renders of that chart (`bootstrap.*`
is read by the bootstrap Job only, `principals.*` by the principals Job
only): okdp-compile checks it against the protected paths of `polaris-admin`
and applies it to the bootstrap render, and `values.cel.yaml` merges it over
the computed values of the principals render (`polaris-admin-principals`,
which takes no upstream values of its own). An upstream value wins over the
parameter it overlaps (`resources.limits.memory` over `memoryGi`). No key or
value may contain `{{` (the schema and okdp-compile both refuse it).
`oidc-dcr` and `console-oidc-dcr` take no upstream values.

`serviceMonitor` of `polaris` is protected: its template reads
`.Capabilities.APIVersions`, which Flux (`helm install`) and Argo CD (`helm
template`) do not see alike; it stays disabled, as upstream.

## Provided connection

`<release>` (contract `iceberg-catalog`), in `okdp.info.yaml`:

```yaml
uri: https://polaris-<namespace>.<suffix>/api/catalog
internalUri: http://<release>-polaris.<namespace>.svc:8181/api/catalog
realm: <realm>
```

A consumer in the same namespace references it by the release name; an
internal reference carries no `realm` (the contract convention cannot derive
it), so trino needs `warehouse` on such a catalog.

## Ordering

The KuboCD modules ran in sequence (internal-secrets, bootstrap, main,
principals and console). Now everything is one release:

- the root credentials are an ESO `ExternalSecret`, a regular object. The
  bootstrap Job was a pre-install hook of its own module; it would now wait
  for a Secret created after it, so it is a **post-install/post-upgrade** hook
  (Argo: PostSync). Its pod starts once ESO has written the Secret;
- Polaris starts before its realm is bootstrapped and serves it once the Job
  is done; the principals Job (higher weight) runs after bootstrap and waits
  for Polaris itself;
- both Jobs are idempotent (`already bootstrapped`, HTTP 409 accepted).

## Changes from the KuboCD package

- The API Service is `<release>-polaris` (was `<release>-main`), the name the
  `iceberg-catalog` contract promises; the published connection is `<release>`
  (was `kcd-<release>-catalog`).
- Root credentials: Secret `<release>-root` (was `creds-<release>-root`),
  generated once by ESO and kept on uninstall
  (`helm.sh/resource-policy: keep`, Argo `Delete=false`), as `keep: true` did.
- Console TLS Secret `<release>-polaris-console-tls` (was `polaris-console-tls`).
- The `db` connection must be PostgreSQL (the compile fails otherwise).
- The server logs at `INFO` (was `DEBUG`).
- `realm`, `principals[].name` and `principals[].roles[]` are restricted to
  `^[A-Za-z0-9_.-]+$`: the polaris-admin Jobs interpolate them into shell scripts.
- Upstream values are given inline only, under `upstream.<key>` (no
  `upstream.<key>.yaml` file of the instance any more).

## Known gaps

- The values ConfigMaps `<release>-<chart>-values` of the former
  okdp-lib-chart charts are gone: the compiled values (`instance.values.yaml`)
  replace them.
- polaris-console 0.3.0 (`extraEnv` `valueFrom`, `podLabels`) is the chart of
  the polaris-console repository not yet published to
  `oci://quay.io/okdp/charts`: until it is, `helm dependency build` of an
  instance fails on it.

## Tests

```sh
scripts/compile-charts.sh catalog/polaris/1.3.0-incubating-1.0.0   # compile, check and render ci/*-values.yaml
```

`ci/<case>-platform.yaml` holds each case's platform values,
`ci/<case>-connections.yaml` its connections: the cases share none.
