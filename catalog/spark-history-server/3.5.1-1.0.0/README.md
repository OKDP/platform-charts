# spark-history-server

OKDP package of the Spark History Server (completed Spark applications, event
logs on S3) behind the OKDP Spark web proxy (`/sparkui` proxies running
applications too). It **consumes** an `s3` connection and provides none.

A package in the okdp-compiler format: the former KuboCD modules are the
upstream charts of `Chart.yaml`, whose values `values.cel.yaml` computes from
the parameters below (`config.schema.json`), over OKDP's defaults
(`<chart>.defaults.yaml`, named in `okdp.yaml`). OKDP's own objects are in the
`objects` of `okdp.yaml`, rendered by the umbrella (`okdp.objects.yaml`):

| Former module | Now | Rendered as |
|---|---|---|
| main | chart `spark-history-server` (`oci://quay.io/okdp/charts/spark-history-server` 1.0.0) | `<release>-spark-history-server` |
| proxy | chart `spark-web-proxy` (`oci://quay.io/okdp/charts/spark-web-proxy` 0.1.0) | `<release>-spark-web-proxy`, ingress `spark-web-proxy-<namespace>.<suffix>` |
| (new) oidc-dcr | the `oidcClients` of `okdp.yaml`: the compiler adds chart `oidc-dcr` (the platform's oidc-dcr chart, `oci://quay.io/adaltas/oidc-dcr` 0.5.0 by default) | Job `<release>-oidc-dcr` (pre-install/pre-upgrade hook), only with `global.okdp.oidc.clientProvisioning: dcr` |
| (new) | `objects`: ESO Password generator + ExternalSecret `<release>-auth-cookie` | with OIDC |

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

## Upstream values

Any value of the `spark-history-server` and `spark-web-proxy` charts can be
set per instance, under `upstream.<chart>`, merged over the values computed
from the parameters (`upstream` in `okdp.yaml`):

```yaml
upstream:
  spark-history-server:
    image: {repository: mirror.example.org/okdp/spark}
    tolerations: [{key: dedicated, operator: Exists, effect: NoSchedule}]
    extraEnvs: [{name: EXTRA_FLAG, value: "1"}]    # appended to the chart's env
    config: {spark.history.retainedApplications: 100}
  spark-web-proxy:
    resources: {limits: {memory: 256Mi}}
```

The paths the platform relies on are refused, and the lists carrying the
chart's Secrets and CA bundle are appended to rather than replaced: see
`protect` and `append` in `okdp.yaml` (also listed in the schema
descriptions). Spark properties under `spark-history-server.config` have dots
in their names: the ones the platform sets (OIDC filter, ACLs, event log
directory, S3 endpoint and credentials, UI port) are protected in brackets,
each with the properties that start with it (`config["spark.admin.acls*"]`),
and the `errors` of `okdp.yaml` check that every property is a single-line
scalar with a plain property name (the `config` map is written as a
properties file). An image other than the OKDP Spark image must carry the
OKDP OIDC filter when OIDC is on. No key or value may contain `{{` (the schema
and okdp-compile both refuse it). `oidc-dcr` takes no upstream values.

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
- Upstream values are given inline only, under `upstream.<chart>` (no
  `upstream.<chart>.yaml` file of the instance any more).

## Known limitations (unchanged)

- The ingress host is per namespace: one instance per namespace.

## Known gaps

- The values ConfigMaps `<release>-<chart>-values` of the former
  okdp-lib-chart charts are gone: the compiled values (`instance.values.yaml`)
  replace them.

## Tests

```sh
scripts/compile-charts.sh catalog/spark-history-server/3.5.1-1.0.0   # compile, check and render ci/*-values.yaml
```

`ci/<case>-platform.yaml` holds each case's platform values,
`ci/<case>-connections.yaml` its connections: the cases share none.
