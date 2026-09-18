# jupyterhub

OKDP chart of [JupyterHub](https://jupyter.org/hub): multi-user notebooks with
OAuth sign-in against the platform OIDC provider, a jupyter-fs S3 file
browser and PySpark kernels running Spark on Kubernetes. It **consumes** an
`s3` connection and provides no connection.

The former KuboCD modules are vendored charts (`vendor.yaml`, `vendor/`)
rendered by `okdp.vendor.render` with computed values (`templates/_values.tpl`):

| Former module | Now | Rendered when |
|---|---|---|
| `main` | `vendor/jupyterhub` (z2jh 4.4.2) | always |
| `spark-rbac` | `vendor/spark-rbac` (`oci://quay.io/okdp/charts` 1.0.1): ServiceAccount/Role `spark` | always |
| `oidc-client` | `vendor/oidc-client` (copy of `charts/oidc-client` 0.2.0) | `global.okdp.oidc.clientProvisioning: kubauth` |
| `oidc-dcr` | `vendor/oidc-dcr` (`oci://quay.io/adaltas` 0.3.3): Job `<release>-oidc-dcr` (pre-install/pre-upgrade hook) | `global.okdp.oidc.clientProvisioning: dcr` |

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `storage` | (required) | `s3` connection of the object store behind the file browser (`apiUrl`). |
| `s3SecretRef` | (required) | Secret with `accessKey`/`secretKey`: this instance's own S3 identity. |
| `cpu` / `memoryGi` | `0.5` / `1` | Notebook pod guarantees; limits are twice the guarantees. |
| `fileBrowserLocations[]` | `[]` | `{name, uri}` jupyter-fs locations (`s3://bucket`). |
| `oidcRoleMapping` | `{}` | GenericOAuthenticator overrides (`allowed_groups`, `admin_groups`, ...). |
| `welcomeNotebook` | `""` | `Welcome.ipynb` copied into each home. |
| `sparkConnections[]` | `[]` | `{name, properties, s3SecretRef?}`: Spark conf lines of a PySpark connection. **Was `connections`** (now the external connections map). |
| `pyspark[]` | `[]` | Names of the `sparkConnections` wired into the PySpark kernel. |
| `sparkDefaults` | `{}` | Spark conf defaults added to `PYSPARK_SUBMIT_ARGS`. |

Placeholders replaced in `welcomeNotebook`, `sparkDefaults` and the
`properties` of `sparkConnections` (values are no longer templated by
KuboCD): `{{ .Values.global.okdp.ingress.suffix }}` / `{{ .Context.ingress.suffix }}`,
`{{ .Release.Name }}` / `{{ .Release.metadata.name }}`,
`{{ .Release.Namespace }}` / `{{ .Release.namespace }}`; in `properties` also
`{{ connection.name }}`, `{{ storage.endpoints.apiUrl }}`, `{{ storage.region }}`,
`{{ idp.endpoints.tokenUrl }}`, and `$(S3_ACCESS_KEY)`/`$(S3_SECRET_KEY)`
become the connection's own variables when it has an `s3SecretRef`.

Platform values read from `global.okdp`: `ingress.suffix`, `ingress.className`,
`certificateIssuers.selfSigned.name`, `storageClass.workspace` (hub
database), `oidc.authUrl|tokenUrl|userinfoUrl|displayName|clientProvisioning`,
`oidc.kubauth.namespace` (kubauth mode), `proxy`.

## OAuth client

- `existing` (and `dcr`, which this chart does not implement): Secret
  `creds-<release>-oauth2` with `client_id`, `client_secret`,
  `JUPYTERHUB_CRYPT_KEY`.
- `kubauth`: the oidc-client module generates `<release>-<namespace>-oidc-creds`
  (same keys) and the OidcClient.

## Generated secrets

The upstream chart generates the proxy token, the cookie secret and the
auth-state keys of its hub Secret with `lookup` + `randAlphaNum` (a new value
at every `helm template`: Argo CD would never settle). The wrapper hands the
chart a placeholder for the three and generates the real ones once with ESO
(`Password` generators, ExternalSecret `<release>-hub-generated`, all three
keys declared up front since a `refreshInterval: "0"` Secret is never
rewritten; kept on uninstall, `helm.sh/resource-policy: keep` and Argo
`Delete=false`, and adopted again by the next install, so that a kept or
restored hub database still decrypts its auth state). The hub reads the
cookie secret and the auth-state keys from it
first (`hub.existingSecret`), and the proxy token references of the hub and
proxy Deployments are re-pointed to it (`okdp.vendor.secretKeyRef`). The
chart's own hub Secret `<release>-hub` stays (Helm-managed: it carries the
hub configuration, `values.yaml`, which follows every upgrade); its three
password keys hold the unused placeholder. Exceptions in
`okdp-guard-allow.yaml`.

## Changes from the KuboCD package

- `connections` (PySpark connections) is renamed `sparkConnections`.
- The hub passwords are ESO-generated: an upgrade from the KuboCD release gets
  a new cookie secret and new auth-state keys (users sign in again).

## Tests

```sh
helm dependency build charts/services/jupyterhub
for f in charts/services/jupyterhub/ci/*-values.yaml; do
  helm lint charts/services/jupyterhub -f "$f"
  helm template demo-jupyterhub charts/services/jupyterhub -n demo -f "$f" >/dev/null
done
scripts/vendor-charts.sh --check charts/services/jupyterhub
```
