# superset

OKDP chart of [Apache Superset](https://superset.apache.org): dashboards and
SQL Lab over Trino datasources, OAuth2 sign-in against the platform OIDC
provider. It **consumes** `database-server` connections (metadata, examples)
and one `trino` connection per datasource; it provides no connection.

The former module `main` rendered OKDP's superset chart
(`quay.io/okdp/charts/superset` 0.15.2-2.0,
[source](https://github.com/okdp/charts/tree/main/charts/superset)), a
wrapper around the Apache Superset chart. The wrapper is folded into this
chart: its defaults and Python config overrides are in the computed values
(`templates/_values.tpl`), its env Secrets in `templates/env-secrets.yaml`
(same names and keys). Only the Apache chart is vendored (`vendor.yaml`) and
rendered by `okdp.vendor.render` (`templates/superset.yaml`):

| Former module | Now | Rendered when |
|---|---|---|
| `main` (OKDP wrapper) | `templates/env-secrets.yaml`: `<release>-db-env`, `-oauth2-env`, `-redis-env`, `-superset-env`, `-trino-oauth2-env`; its values in `templates/_values.tpl` | always |
| `main` (Apache chart) | `vendor/superset` (apache/superset 0.22.8, bundled bitnami charts dropped) | always |
| `main` (bitnami redis subchart) | `templates/valkey.yaml`: Deployment + Service `<release>-redis` (Valkey 9.1, `valkey/valkey`, BSD-3-Clause; no persistence) | always |
| `internal-secrets` | `okdp.generatedSecret` `<release>-internal` (`superset_secret_key`, `redis-password`) | always |
| (new) local admin | `okdp.generatedSecret` `<release>-admin` (`password`) | `global.okdp.oidc.enabled: false` |
| (new) `oidc-dcr` | `vendor/oidc-dcr` (`oci://quay.io/adaltas` 0.3.3): Job `<release>-oidc-dcr` (pre-install/pre-upgrade hook) | `global.okdp.oidc.clientProvisioning: dcr` |

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
| `examplesDb` | (required) | `database-server` (PostgreSQL) connection receiving the examples, used when `load_examples`. |
| `load_examples` | `true` | Load the Superset examples. |
| `datasources[]` | `[]` | `{name, trino (trino connection), catalog}`: one Superset database per item. `name`: `^[A-Za-z0-9][A-Za-z0-9 _.-]*$`; `catalog`: `^[A-Za-z0-9_.-]+$`. |
| `oidcRoleMapping` | `{}` | OIDC group → list of Superset roles. Keys and roles may not contain `{{`, `}}` or line breaks. |
| `cpu` / `memoryGi` / `workers` | `0.5` / `2` / `2` | Web server limits and gunicorn workers. |
| `locale` / `currency` / `d3Format` / `d3TimeFormat` | `en` / `""` / `{}` / `{}` | Chart number and date formats. `locale` is a CLDR locale id (`fr-FR`, `zh_Hant_TW`), `currency` an ISO 4217 code (`EUR`). `d3Format` / `d3TimeFormat` reach the Python config as base64-encoded JSON (data, never code). |

A `trino` reference is a connection file of the project or the release name of
a trino instance in the same namespace (its `uri`,
`trino://trino@trino-<namespace>.<suffix>:443`, is used). `database-server`
references are always connection files.

Platform values read from `global.okdp`: `ingress.suffix`, `ingress.className`,
`certificateIssuers.selfSigned.name`,
`oidc.issuerUri|enabled|displayName|scope|usePKCE|clientProvisioning`,
`oidc.dcr.registrationUrl|authMethod` (dcr), `proxy`.

OAuth clients (when `global.okdp.oidc.enabled`), keys `client_id`/`client_secret`:

- `clientProvisioning: existing`: Secrets `creds-<release>-oauth2` (sign-in) and
  `creds-<release>-oauth2-trino` (Trino datasources), as before;
- `clientProvisioning: dcr`: one client for both, registered anonymously by the Job
  `<release>-oidc-dcr` (redirect URIs `https://superset-<namespace>.<suffix>/oauth-authorized/<displayName>`
  and `.../api/v1/database/oauth2/`, grants `authorization_code` and
  `refresh_token`, the platform scopes but `openid`) into Secret
  `<release>-<namespace>-dcr`. The Job needs the CA bundle Secret `certs-bundle`.

Without OIDC the init job creates the local `admin` user (if it does not
exist yet) with a password generated per instance by ESO: Secret
`<release>-admin`, key `password` (kept on uninstall, like `<release>-internal`).
The Apache chart can only put `init.adminUser.password` in its script, so its
own admin creation is off (`init.createAdmin: false`) and the wrapper's
`init.command` creates the user from the `SUPERSET_ADMIN_PASSWORD` environment
variable.

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
- The forceReload pod annotations (randAlphaNum) are pinned off
  (`okdp-guard-allow.yaml`).
- Without OIDC the local admin password is generated (was `admin`/`admin`).
  An existing install keeps its `admin` user and password: reset it with
  `superset fab reset-password --username admin --password "$SUPERSET_ADMIN_PASSWORD"`
  in a Superset pod.

## Tests

```sh
helm dependency build charts/services/superset
for f in charts/services/superset/ci/*-values.yaml; do
  helm lint charts/services/superset -f "$f"
  helm template demo-superset charts/services/superset -n demo -f "$f" >/dev/null
done
scripts/vendor-charts.sh --check charts/services/superset
```
