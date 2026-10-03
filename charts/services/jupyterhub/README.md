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
`oidc.dcr.registrationUrl|authMethod` (dcr), `proxy`.

## OAuth client

- `clientProvisioning: existing`: the client is created in Keycloak beforehand,
  Secret `creds-<release>-oauth2` with `client_id`, `client_secret`,
  `JUPYTERHUB_CRYPT_KEY`.
- `clientProvisioning: dcr`: the Job `<release>-oidc-dcr` registers it
  anonymously (`dcr.authMethod: anonymous`; redirect URI
  `https://jupyterhub-<namespace>.<suffix>/hub/oauth_callback`, grants
  `authorization_code` and `refresh_token`, scopes `profile email groups`) and
  writes Secret `<release>-<namespace>-dcr` (`client_id`, `client_secret`); the
  crypt key of the auth state is then the generated
  `hub.config.CryptKeeper.keys` of `<release>-hub-generated`. The Job needs the CA
  bundle Secret `certs-bundle`.

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

## Upstream values

Any value of the vendored `jupyterhub` and `spark-rbac` charts can be set per
instance under `upstream.<chart>`, merged over the values computed from the
parameters (okdp-lib-chart `okdp.vendor.render`, option `upstream`):

```yaml
upstream:
  jupyterhub:
    hub: {image: {name: mirror.example.org/jupyterhub/k8s-hub}}
    cull: {enabled: true, timeout: 7200}
    singleuser:
      nodeSelector: {workload: notebooks}
      extraEnv: {EXTRA_FLAG: "1"}                   # merged into the chart's env map
      storage:
        extraVolumes: [{name: shared, persistentVolumeClaim: {claimName: shared}}]  # appended
        extraVolumeMounts: [{name: shared, mountPath: /shared}]
      profileList: [{display_name: Minimal, kubespawner_override: {image: quay.io/jupyter/minimal-notebook}}]  # appended
  spark-rbac:
    serviceAccount: {annotations: {eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/spark}}
```

The paths the platform relies on are refused (names, the ESO-generated hub
passwords, OIDC sign-in, the ingress host, the notebook env and files the
platform wires, the spark ServiceAccount), and the lists carrying the hub roles,
the CA bundle volume and the PySpark profile are appended to rather than
replaced: see `okdp-jupyterhub.upstream.jupyterhub` and
`okdp-jupyterhub.upstream.sparkRbac` in `templates/_values.tpl` (also listed in
the schema descriptions). The env maps (`hub.extraEnv`, `singleuser.extraEnv`)
and `hub.extraConfig` merge key by key. An upstream value wins over the
parameter it overlaps (`hub.config.GenericOAuthenticator.allowed_groups` over
`oidcRoleMapping`, `singleuser.cpu` over `cpu`). No key or value may contain
`{{` (the schema and okdp-lib-chart both refuse it). `oidc-dcr` takes no
upstream values.

## Changes from the KuboCD package

- The former OAuth client provisioning module is gone: the client is created
  in Keycloak beforehand or registered by DCR (identity is Keycloak only).
- `connections` (PySpark connections) is renamed `sparkConnections`.
- The hub passwords are ESO-generated: an upgrade from the KuboCD release gets
  a new cookie secret and new auth-state keys (users sign in again).

## Tests

```sh
scripts/vendor-charts.sh charts/services/jupyterhub   # download vendor/ (not committed)
helm dependency build charts/services/jupyterhub
for f in charts/services/jupyterhub/ci/*-values.yaml; do
  helm lint charts/services/jupyterhub -f "$f"
  helm template demo-jupyterhub charts/services/jupyterhub -n demo -f "$f" >/dev/null
done
```
