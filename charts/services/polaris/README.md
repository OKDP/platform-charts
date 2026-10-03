# polaris

OKDP chart of [Apache Polaris](https://polaris.apache.org/), an Iceberg REST
catalog, with its console. It **provides** an `iceberg-catalog` connection and
**consumes** a `database-server` (PostgreSQL) and an `s3` connection.

It renders three upstream charts, vendored under `vendor/` (see
`vendor.yaml`), with values computed from the parameters below
(`templates/_values.tpl`):

| Former module | Chart | Rendered as |
|---|---|---|
| internal-secrets | (replaced) | ESO `Password` + `ExternalSecret` `<release>-root` (`templates/root-secret.yaml`) |
| bootstrap | `oci://quay.io/okdp/charts/polaris-admin` 1.0.0, `phase: bootstrap` | Job `<release>-bootstrap`, post-install/post-upgrade hook, weight -5 |
| main | `polaris` 1.3.0-incubating (Apache) | `<release>-polaris`, ingress `polaris-<namespace>.<suffix>` |
| principals | `polaris-admin` 1.0.0, `phase: principals` | Job `<release>-principals`, post-install/post-upgrade hook, weight 5 (only with principals) |
| console | `oci://quay.io/okdp/charts/polaris-console` 0.2.0 | `<release>-polaris-console`, ingress `polaris-console-<namespace>.<suffix>` |
| (new) oidc-dcr | `oci://quay.io/adaltas/oidc-dcr` 0.4.0, twice | Jobs `<release>-oidc-dcr` and `<release>-console-oidc-dcr` (pre-install/pre-upgrade hooks), only with `global.okdp.oidc.clientProvisioning: dcr` |

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
  (confidential, grant `client_credentials`) by the Job `<release>-oidc-dcr` into
  Secret `<release>-<namespace>-dcr`, same keys; the console's (public,
  `token_endpoint_auth_method: none`, redirect URI
  `https://polaris-console-<namespace>.<suffix>/auth/callback`, grants
  `authorization_code` and `refresh_token`, the platform scopes but `openid`, plus
  `roles offline_access`) by the Job `<release>-console-oidc-dcr` into Secret
  `<release>-<namespace>-console-dcr` (`client_id`), which the console's
  `VITE_OIDC_CLIENT_ID` reads (the console chart's `extraEnv` takes values only:
  the wrapper re-points that env in the rendered Deployment).

## Upstream values

Any value of the vendored `polaris`, `polaris-console` and `polaris-admin`
charts can be set per instance under `upstream.<chart>`, merged over the values
computed from the parameters (okdp-lib-chart `okdp.vendor.render`, option
`upstream`):

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
chart's Secrets are appended to rather than replaced: see
`okdp-polaris.upstream.polaris`, `okdp-polaris.upstream.console` and
`okdp-polaris.upstream.admin` in `templates/_values.tpl` (also listed in the
schema descriptions). `upstream.polaris-admin` applies to both renders of that
chart (`bootstrap.*` is read by the bootstrap Job only, `principals.*` by the
principals Job only). An upstream value wins over the parameter it overlaps
(`resources.limits.memory` over `memoryGi`). No key or value may contain `{{`
(the schema and okdp-lib-chart both refuse it). `oidc-dcr` takes no upstream
values.

## Provided connection

`<release>` (contract `iceberg-catalog`):

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
- The `db` connection must be PostgreSQL (the render fails otherwise).
- The server logs at `INFO` (was `DEBUG`).
- `realm`, `principals[].name` and `principals[].roles[]` are restricted to
  `^[A-Za-z0-9_.-]+$`: the polaris-admin Jobs interpolate them into shell scripts.

## Tests

```sh
scripts/vendor-charts.sh charts/services/polaris   # download vendor/ (not committed)
helm dependency build charts/services/polaris
for f in charts/services/polaris/ci/*-values.yaml; do
  helm lint charts/services/polaris -f "$f"
  helm template demo-polaris charts/services/polaris -n demo -f "$f" >/dev/null
done
```
