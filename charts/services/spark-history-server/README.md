# spark-history-server

OKDP chart of the Spark History Server (completed Spark applications, event
logs on S3) behind the OKDP Spark web proxy (`/sparkui` proxies running
applications too). It **consumes** an `s3` connection and provides none.

It renders two upstream charts, vendored under `vendor/` (see `vendor.yaml`),
with values computed from the parameters below (`templates/_values.tpl`):

| Former module | Chart | Rendered as |
|---|---|---|
| main | `oci://quay.io/okdp/charts/spark-history-server` 1.0.0 | `<release>-spark-history-server` |
| proxy | `oci://quay.io/okdp/charts/spark-web-proxy` 0.1.0 | `<release>-spark-web-proxy`, ingress `spark-web-proxy-<namespace>.<suffix>` |
| (new) oidc-dcr | `oci://quay.io/adaltas/oidc-dcr` 0.3.3 | Job `<release>-oidc-dcr` (pre-install/pre-upgrade hook), only with `global.okdp.oidc.clientProvisioning: dcr` |

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `storage` | (required) | `s3` connection of the store holding the event logs (`s3a://spark-events/event-logs`); `internalUrl` is preferred over `apiUrl`. |
| `s3SecretRef` | (required) | Secret with `accessKey`/`secretKey`: this instance's own S3 identity. |
| `roleMapping` | empty lists | OIDC groups for the Spark ACLs: `admin_groups`, `history_admin_groups`, `modify_groups`, `view_groups`. |
| `cpu` | `0.5` | CPU limit (vCPU); request 250m. |
| `memoryGi` | `1` | Memory limit (GiB); request 512Mi. |

Platform values read from `global.okdp`: `ingress.suffix`, `ingress.className`,
`certificateIssuers.selfSigned.name`, and when `oidc.enabled` (default true)
`oidc.issuerUri`, `oidc.scope`, `oidc.usePKCE`, `oidc.insecureSkipVerify`, `oidc.clientProvisioning`,
`oidc.dcr.registrationUrl|authMethod` (dcr). The OAuth client of the history
server's OIDC filter (keys `client_id`, `client_secret`) is read from Secret
`creds-<release>-oauth2` (`clientProvisioning: existing`) or
`<release>-<namespace>-dcr` (`dcr`: registered anonymously by the Job
`<release>-oidc-dcr`, redirect URI `https://spark-web-proxy-<namespace>.<suffix>/home`,
grants `authorization_code` and `refresh_token`, the platform scopes but `openid`,
plus `offline_access`). The CA bundle comes from Secret `certs-bundle` (key
`bundle.p12`), also read by the DCR Job.

With OIDC, the filter's cookie encryption key is per instance: Secret
`<release>-auth-cookie` (key `cookie-cipher-secret-key`, 32 characters, AES-256),
generated once by an ESO `Password` generator and passed to the filter through
the `AUTH_COOKIE_ENCRYPTION_KEY` environment variable (the filter reads it when
the Spark property `cookie-cipher-secret-key` is unset). Deleting the Secret
rotates the key and only signs every user out.

S3 certificate checking (`-Dcom.amazonaws.sdk.disableCertChecking`) is turned
off only when `global.okdp.oidc.insecureSkipVerify` is true; otherwise the S3
endpoint is verified against the CA bundle (`JAVA_TOOL_OPTIONS` trust store).

## Changes from the KuboCD package

- The history Service is `<release>-spark-history-server` (was
  `<release>-main`), the proxy `<release>-spark-web-proxy`.
- OIDC follows `okdp.oidc`: enabled unless `global.okdp.oidc.enabled` is
  false (the package defaulted to false when the key was missing; the platform
  values set it). With OIDC off, the OAuth client Secret is no longer
  required.
- `clientProvisioning: dcr` is supported (the package required
  `creds-<release>-oauth2`).
- The OIDC filter cookie cipher key is generated per instance (it was a
  constant shared by every installation). Upgrading signs the current users
  out once.
- S3 certificate checking follows `global.okdp.oidc.insecureSkipVerify` (it
  was always off).

## Known limitations (unchanged)

- The ingress host is per namespace: one instance per namespace.

## Tests

```sh
helm dependency build charts/services/spark-history-server
for f in charts/services/spark-history-server/ci/*-values.yaml; do
  helm lint charts/services/spark-history-server -f "$f"
  helm template demo-spark-history charts/services/spark-history-server -n demo -f "$f" >/dev/null
done
scripts/vendor-charts.sh --check charts/services/spark-history-server
```
