# jupyterhub

OKDP package of [JupyterHub](https://jupyter.org/hub): multi-user notebooks
with OAuth sign-in against the platform OIDC provider, a jupyter-fs S3 file
browser and PySpark kernels running Spark on Kubernetes. It **consumes** an
`s3` connection and provides no connection.

A package in the okdp-compiler format: the former KuboCD modules are the
upstream charts of `Chart.yaml`, whose values `values.cel.yaml` computes from
the parameters (`config.schema.json`), over OKDP's defaults
(`<chart>.defaults.yaml`). OKDP's own objects (`objects` in `okdp.yaml`) are
rendered by the umbrella chart of the instance (`okdp.objects.yaml`):

| Former module | Now | Rendered when |
|---|---|---|
| `main` | chart `jupyterhub` (z2jh 4.4.2) | always |
| `spark-rbac` | chart `spark-rbac` (`oci://quay.io/okdp/charts` 1.0.1): ServiceAccount/Role `spark` | always |
| `oidc-dcr` | the mapping's `oidcClients`: the compiler adds chart `oidc-dcr` (the platform's oidc-dcr chart, `oci://quay.io/adaltas` 0.5.0 by default): Job `<release>-oidc-dcr` (pre-install/pre-upgrade hook) | `global.okdp.oidc.clientProvisioning: dcr` |
| (none) | OKDP's objects: ESO Password generators + ExternalSecret `<release>-hub-generated` (the hub passwords) | always |

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
`properties` of `sparkConnections`, written `${name}` as the contracts'
naming conventions are (an instance value holds no `{{`: okdp-compile refuses
it):

| Placeholder | Value | In |
|---|---|---|
| `${suffix}` | the platform's ingress suffix | all three |
| `${release}` | the release name | all three |
| `${namespace}` | the release namespace (also `NAMESPACE` in `sparkDefaults`) | all three |
| `${url}` | the hub URL | `welcomeNotebook` |
| `${connection}` | the PySpark connection's name | `properties` |
| `${storage.apiUrl}`, `${storage.region}` | the `storage` connection's | `properties` |
| `${oidc.tokenUrl}` | `global.okdp.oidc.tokenUrl` | `properties` |

Any other `${...}` (Spark's own `${env:VAR}`) is left as written. In
`properties`, `$(S3_ACCESS_KEY)`/`$(S3_SECRET_KEY)` become the connection's
own variables when it has an `s3SecretRef`.

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
at every `helm template`: Argo CD would never settle). The mapping hands the
chart a placeholder for the three, and OKDP's objects generate the real ones
once with ESO (`Password` generators, ExternalSecret
`<release>-hub-generated`, all three keys declared up front since a
`refreshInterval: "0"` Secret is never rewritten; kept on uninstall,
`helm.sh/resource-policy: keep` and Argo `Delete=false`, and adopted again by
the next install, so that a kept or restored hub database still decrypts its
auth state). The hub reads the cookie secret and the auth-state keys from it
first (`hub.existingSecret`). The proxy token is not taken from it yet: the
hub and proxy Deployments read `CONFIGPROXY_AUTH_TOKEN` from the chart's own
hub Secret (see Known gaps). The chart's own hub Secret `<release>-hub` stays
(Helm-managed: it carries the hub configuration, `values.yaml`, which follows
every upgrade); its three password keys hold the placeholder. The pre-pull
hook, whose checksum compares with the previous one (`lookup`), stays off and
protected (`prePuller.hook.enabled`).

## Upstream values

Any value of the `jupyterhub` and `spark-rbac` charts can be set per
instance, under `upstream.<chart>`, merged over the values computed from the
parameters (`upstream` in `okdp.yaml`):

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
replaced: see `protect` and `append` in `okdp.yaml` (also listed in the
schema descriptions). The notebook variables that depend on the instance (the
`<PREFIX>_S3_ACCESS_KEY`/`<PREFIX>_S3_SECRET_KEY` of the PySpark connections
with an `s3SecretRef`, the platform proxy variables) are refused by the
`errors` section of `okdp.yaml`. The env maps (`hub.extraEnv`,
`singleuser.extraEnv`) and `hub.extraConfig` merge key by key. An upstream
value wins over the parameter it overlaps
(`hub.config.GenericOAuthenticator.allowed_groups` over `oidcRoleMapping`,
`singleuser.cpu` over `cpu`). No key or value may contain `{{` (the schema
and okdp-compile both refuse it). `oidc-dcr` takes no upstream values.

## Changes from the former package

- The former OAuth client provisioning module is gone: the client is created
  in Keycloak beforehand or registered by DCR (identity is Keycloak only).
- `connections` (PySpark connections) is renamed `sparkConnections`.
- The hub passwords are ESO-generated: an upgrade from the KuboCD release gets
  a new cookie secret and new auth-state keys (users sign in again).
- The placeholders of the free-text parameters are written `${name}`
  (above): the `{{ ... }}` forms of Helm and KuboCD
  (`{{ .Values.global.okdp.ingress.suffix }}`, `{{ .Context.ingress.suffix }}`,
  `{{ storage.endpoints.apiUrl }}`, `{{ idp.endpoints.tokenUrl }}`...) are
  refused by okdp-compile, as any `{{` in an instance value.
- An instance's upstream values are its inline `upstream.<chart>` only: no
  `upstream.<chart>.yaml` file.

## Known gaps

What the okdp-lib-chart chart did to the rendered objects and values cannot
express (okdp-compiler gap list):

- **Security: the proxy token is the placeholder. Do not use this package in
  production before this is closed.** z2jh 4.4.2 hard-wires the
  `CONFIGPROXY_AUTH_TOKEN` `secretKeyRef` of the hub and proxy Deployments to
  its own Secret `<release>-hub` (key
  `hub.config.ConfigurableHTTPProxy.auth_token`), with no value to point it
  elsewhere; okdp-lib-chart re-pointed it to `<release>-hub-generated`
  (`okdp.vendor.secretKeyRef`). Here both Deployments read the placeholder
  `generated-by-external-secrets`: the hub and the proxy still agree, so the
  service works, but the proxy API token (Service `<release>-proxy-api`, port
  8001) is a known constant and the generated
  `hub.config.ConfigurableHTTPProxy.auth_token` is unused. Only the proxy
  NetworkPolicy (port `api` reachable from the pods labelled
  `hub.jupyter.org/network-access-proxy-api: "true"`, the hub) keeps notebooks
  away from that API, where the CNI enforces NetworkPolicies. Closing it
  needs an upstream value (the chart is rendered as published). A second
  `CONFIGPROXY_AUTH_TOKEN` through `hub.extraEnv` / `proxy.chp.extraEnv`
  would duplicate an env name (server-side apply refuses it), and an empty
  `auth_token` brings back `lookup` + `randAlphaNum`.
- the values ConfigMaps `<release>-<chart>-values` are gone: the compiled
  values replace them.

A fix comes with the standard render: z2jh derives its `component` labels
from `.Template.Name`, which okdp-lib-chart set to `vendor/jupyterhub/templates`
for every file, so the hub, the proxy, their Services and the proxy
NetworkPolicy were all `component: jupyterhub` (the Services selected both
pods). They are `hub`, `proxy`, `proxy-api`, `proxy-public`, `singleuser`,
`ingress` again. The `spec.selector` of the hub and proxy Deployments
changes with them, and a Deployment selector is immutable: an existing
release is migrated by deleting both Deployments before the first sync (the
hub database PVC and the Secrets stay). The hub pod's checksum annotations
change too (they cover the relabelled ConfigMap and Secret).

## Tests

```sh
scripts/compile-charts.sh catalog/jupyterhub/4.4.2-1.0.0   # compile, check and render ci/*-values.yaml
```
