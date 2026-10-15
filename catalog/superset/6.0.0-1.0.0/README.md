# superset

OKDP package of [Apache Superset](https://superset.apache.org): dashboards and
SQL Lab over Trino datasources, OAuth2 sign-in against the platform OIDC
provider. It **consumes** `database-server` connections (metadata, examples)
and one `trino` connection per datasource; it provides no connection.

A package in the okdp-compiler format: the former KuboCD modules are the
upstream charts of `Chart.yaml` (its dependencies), whose values
`values.cel.yaml` computes from the parameters (`config.schema.json`), over
OKDP's defaults (`<key>.defaults.yaml`). `okdp.yaml` holds the rest: the
platform values required, what an instance may override, OKDP's own
objects (`objects`, rendered by the umbrella chart of the instance), the
OAuth client and the instance's URL and usage (`okdp.info.yaml`).

The former module `main` rendered OKDP's superset chart
(`quay.io/okdp/charts/superset` 0.15.2-2.0,
[source](https://github.com/okdp/charts/tree/main/charts/superset)), a
wrapper around the Apache Superset chart. The wrapper is folded into this
package: its defaults and Python config overrides are in the values of the
Apache chart (fixed ones in `superset.defaults.yaml`, computed ones in
`values.cel.yaml`), its env Secrets are OKDP objects (same names and keys):

| Former module | Now | Rendered when |
|---|---|---|
| `main` (OKDP wrapper) | OKDP objects: the env Secrets `<release>-db-env`, `-oauth2-env`, `-redis-env`, `-superset-env`, `-trino-oauth2-env`; its values in `superset.defaults.yaml` (fixed) and `values.cel.yaml` (computed) | always |
| `main` (Apache chart) | dependency `superset` (apache/superset 0.22.8, its bundled bitnami charts `postgresql` and `redis` disabled) | always |
| `main` (bitnami redis subchart) | OKDP objects: Deployment + Service `<release>-redis` (Valkey 9.1, `valkey/valkey`, BSD-3-Clause; no persistence) | always |
| `internal-secrets` | OKDP objects: ESO Password generators + ExternalSecret `<release>-internal` (`superset_secret_key`, `redis-password`) | always |
| (new) local admin | OKDP objects: ESO Password generator + ExternalSecret `<release>-admin` (`password`) | `global.okdp.oidc.enabled: false` |
| (new) `oidc-dcr` | `oidcClients` of `okdp.yaml`: the compiler adds the chart `oidc-dcr` (the platform's oidc-dcr chart, `oci://quay.io/adaltas` 0.5.0 by default): Job `<release>-oidc-dcr` (pre-install/pre-upgrade hook) | `global.okdp.oidc.clientProvisioning: dcr` |

The Apache Superset Helm chart is deprecated upstream (0.22.8 is marked
`deprecated: true`); upstream points to the
[Apache Superset Kubernetes operator](https://github.com/apache/superset-kubernetes-operator)
(v0.2.0, API `superset.apache.org/v1alpha1`), the future path for this chart
once its API is stable. It is a CRD and a controller, so adopting it needs the
contract's "only standard tooling" rule to be revisited.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `metadataDb` | (required) | `database-server` connection of the metadata database; its Secret holds `username`/`password`. |
| `examplesDb` | (required when `load_examples`) | `database-server` (PostgreSQL) connection receiving the examples. |
| `load_examples` | `false` | Load the Superset examples. They are downloaded from GitHub: leave it off without Internet access. |
| `datasources[]` | `[]` | `{name, trino (trino connection), catalog}`: one Superset database per item. `name`: `^[A-Za-z0-9][A-Za-z0-9 _.-]*$`; `catalog`: `^[A-Za-z0-9_.-]+$`. |
| `oidcRoleMapping` | `{}` | OIDC group → list of Superset roles. Keys and roles may not contain `{{`, `}}` or line breaks. |
| `cpu` / `memoryGi` / `workers` | `0.5` / `2` / `2` | Web server limits and gunicorn workers. |
| `locale` / `currency` / `d3Format` / `d3TimeFormat` | `en` / `""` / `{}` / `{}` | Chart number and date formats. `locale` is a CLDR locale id (`fr-FR`, `zh_Hant_TW`), `currency` an ISO 4217 code (`EUR`). `d3Format` / `d3TimeFormat` reach the Python config as base64-encoded JSON (data, never code). |

A `trino` reference is a connection (the platform's, the project's or the
instance's own) or the release name of a trino instance in the same namespace
(its `uri`, `trino://trino@trino-<namespace>.<suffix>:443`, is used).
A `database-server` reference is a connection or, by its name, an output of
an instance in the same namespace (e.g. `demo-pg-superset`, a database of a
cnpg-postgresql instance). A provider of another namespace is always a
connection.

Platform values read from `global.okdp`: `ingress.suffix`, `ingress.className`,
`certificateIssuers.selfSigned.name`,
`oidc.issuerUri|enabled|displayName|scope|usePKCE|insecureSkipVerify|clientProvisioning`,
`oidc.dcr.registrationUrl|authMethod` (dcr), `proxy`.

OAuth clients (when `global.okdp.oidc.enabled`), keys `client_id`/`client_secret`:

- `clientProvisioning: existing`: Secrets `creds-<release>-oauth2` (sign-in) and
  `creds-<release>-oauth2-trino` (Trino datasources), as before;
- `clientProvisioning: dcr`: one client for both, registered anonymously by the
  Job `<release>-oidc-dcr` (redirect URIs `https://superset-<namespace>.<suffix>/oauth-authorized/<displayName>`
  and `.../api/v1/database/oauth2/`, grants `authorization_code` and
  `refresh_token`, the platform scopes but `openid`) into Secret
  `<release>-<namespace>-dcr`. The Job needs the CA bundle Secret `certs-bundle`.

Without OIDC the init job creates the local `admin` user (if it does not
exist yet) with a password generated per instance by ESO: Secret
`<release>-admin`, key `password` (kept on uninstall, like `<release>-internal`).
The Apache chart can only put `init.adminUser.password` in its script, so its
own admin creation is off (`init.createAdmin: false`) and the package's
`init.command` creates the user from the `SUPERSET_ADMIN_PASSWORD` environment
variable.

TLS: the sign-in (`AUTH_OAUTH_SSL_CERTIFICATE_VERIFY`) and the Trino datasources
(`connect_args.verify`) verify certificates against the CA bundle
(`certs-bundle`, mounted at `/cacerts`, `REQUESTS_CA_BUNDLE`) unless
`global.okdp.oidc.insecureSkipVerify` is true.

## Upstream values

Any value of the `superset` chart can be set per instance, under
`upstream.superset`, merged over the values computed from the parameters
(`upstream` in `okdp.yaml`):

```yaml
upstream:
  superset:
    image: {repository: mirror.example.org/okdp/superset}
    supersetWorker: {replicas: {replicaCount: 2}}
    tolerations: [{key: dedicated, operator: Exists, effect: NoSchedule}]
    extraEnvRaw: [{name: EXTRA_FLAG, value: "1"}]     # appended to the chart's env
    configOverrides:                                   # a block added to superset_config.py
      row_limit: |
        ROW_LIMIT = 100000
```

The paths the platform relies on are refused (names and env Secrets, the
`configOverrides` blocks of the sign-in, the Trino OAuth2 and Valkey, the
metadata database and cache connections, the local admin creation,
`forceReload`, the ingress host), and the lists carrying the chart's Secrets
and wait init containers are appended to rather than replaced: see `protect`
and `append` in `okdp.yaml` (also listed in the schema description). An
upstream value wins over the parameter it overlaps (`supersetNode.resources`
over `cpu`/`memoryGi`, `extraConfigs` over `datasources`). `configOverrides`
blocks are Python, run after the package's: they can redefine any setting,
the protection only keeps the package's blocks in place. No key or value may
contain `{{` (the schema and okdp-compile both refuse it). `oidc-dcr` takes no
upstream values.

## Hooks

The Apache chart's init job (schema upgrade, roles, local admin without OIDC,
examples, datasources import) is a `post-install,post-upgrade` hook (Argo:
PostSync), idempotent. Its init container waits for the databases.

## Changes from the KuboCD package

- The cache and Celery broker is Valkey, Service `<release>-redis` (was the
  bitnami redis `<release>-main-redis-headless` with a PVC): the bitnami chart
  reads its password back with `lookup` and its images are no longer
  published. The cache and the Celery queue are not persisted.
- Apache chart 0.22.8 (was 0.15.2 under the wrapper): the Superset
  Deployments select on `app.kubernetes.io/{name,instance,component}` (were
  `app`/`release`) and lose the `-main` name suffix, so they are recreated,
  not updated in place (a selector is immutable). The image stays
  `quay.io/okdp/superset:6.0.0`; the wait init containers use it too (the
  `-dockerize` variant is no longer needed).
- The generated secret is `<release>-internal` (was `creds-<release>-internal`).
  It is kept on uninstall with its ExternalSecret and generators
  (`helm.sh/resource-policy: keep`, Argo `Delete=false`) and adopted again by
  the next install: the rows of the database are encrypted with
  `superset_secret_key`.
- The forceReload pod annotations (randAlphaNum, a new value at each
  render) are pinned off and protected.
- Without OIDC the local admin password is generated (was `admin`/`admin`).
  An existing install keeps its `admin` user and password: reset it with
  `superset fab reset-password --username admin --password "$SUPERSET_ADMIN_PASSWORD"`
  in a Superset pod.
- TLS verification follows `global.okdp.oidc.insecureSkipVerify` (it was
  always off for the sign-in and the Trino datasources).

## Known gaps

What the okdp-lib-chart chart did to the rendered objects and values cannot
express (okdp-compiler gap list):

- the values ConfigMaps `<release>-superset-values` and
  `<release>-oidc-dcr-values` are gone: the compiled values replace them;
- the descriptor ConfigMap `<release>-okdp` is gone: the instance's URL and
  usage are in `okdp.info.yaml`, beside its compiled chart;
- the bundled bitnami charts `postgresql` and `redis` are no longer dropped
  from the chart: it is rendered as published, both disabled by
  `superset.defaults.yaml` (and protected), so they render nothing.

## Tests

```sh
scripts/compile-charts.sh catalog/superset/6.0.0-1.0.0   # compile, check and render ci/*-values.yaml
```

The cases: `examples-trino` (OIDC with existing clients, examples, an
internal and an external Trino datasource), `dcr` (the same, the OAuth client
registered by DCR), `no-oidc-proxy` (OIDC off, the local admin, a proxy,
sizing), and one failing case per rule of the `errors` section.
