# airflow

OKDP chart of [Apache Airflow](https://airflow.apache.org/) 3.2.1 with the
KubernetesExecutor, OIDC login (Flask AppBuilder) and DAGs from git-sync. It
**consumes** a `database-server` and an `s3` connection and provides none.

It renders two upstream charts, vendored under `vendor/` (see `vendor.yaml`),
with values computed from the parameters below (`templates/_values.tpl`):

| Former module | Chart | Rendered |
|---|---|---|
| oidc-dcr | `oci://quay.io/adaltas/oidc-dcr` 0.4.0 | only with `global.okdp.oidc.clientProvisioning: dcr` |
| internal-secrets | (replaced) | ESO `Password` generators + `ExternalSecret` `<release>-internal` |
| main | `airflow` 1.22.0 (`https://airflow.apache.org`), bundled `postgresql` subchart dropped (`vendor.yaml` `drop`) | `<release>-*`, ingress `airflow-<namespace>.<suffix>` |

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `db` | (required) | `database-server` connection of the metadata database. Checked only (contract, existence of the connection file). |
| `metadataSecret` | (required) | Secret with key `connection`: the full SQLAlchemy connection string. |
| `storage` | (required) | `s3` connection the DAGs use (`AWS_ENDPOINT_URL_S3` = `internalUrl`, else `apiUrl`; `AWS_REGION`). |
| `s3SecretRef` | (required) | Secret with `accessKey`/`secretKey` for the DAGs. |
| `oidcRoleMapping` | `{}` | OIDC group -> Airflow roles, e.g. `{airflow-admins: [Admin]}`. Keys and roles may not contain `{{`, `}}` or line breaks (the API server config goes through the upstream `tpl`). |
| `dagsGitSync` | `{}` | Upstream `dags.gitSync` scalar values: `enabled`, `repo`, `branch`, `ref`, `rev`, `depth`, `maxFailures`, `subPath`, `period`, `wait`, `sshKeySecret`, `knownHosts`, `containerName`, `uid`, `httpPort` (other keys are refused: several reach the upstream `tpl` or are pasted as raw YAML); `ref` is mirrored onto `branch`; `credentialsSecret.name` names the git credentials Secret. |
| `schedulerMemoryGi`, `webserverMemoryGi`, `dagProcessorMemoryGi` | `1` | Memory limits (GiB). |
| `dagProcessorCpuCores` | `0.75` | DAG processor CPU limit. |

Platform values read from `global.okdp`: `ingress.suffix`, `ingress.className`,
`certificateIssuers.selfSigned.name`, `oidc.*` (`enabled`, `issuerUri`,
`authUrl`, `tokenUrl`, `scope`, `insecureSkipVerify`, `clientProvisioning`,
`dcr.registrationUrl`, `dcr.authMethod: anonymous`), `proxy.*` (git-sync).
The OAuth client comes from Secret `creds-<release>-oauth2` (existing mode) or
`<release>-<namespace>-dcr` (dcr mode), keys `client_id`/`client_secret`; the
CA bundle from Secret `certs-bundle`.

## Generated secrets

`<release>-internal` (ESO, generated once): `api-secret-key` (32),
`jwt-secret` (64) and `fernet-key`, the base64 of 32 characters (the format the
upstream chart minted with `randAlphaNum` in a pre-install hook; that template
is now disabled through `fernetKeySecretName`). See `okdp-guard-allow.yaml`
for the upstream random functions kept disabled. The Secret, its ExternalSecret
and generators are kept on uninstall (`helm.sh/resource-policy: keep`, Argo
`Delete=false`) and adopted again by the next install: the connections and
variables in the database are encrypted with `fernet-key`.

## Database migrations

`migrateDatabaseJob` stays a plain Job (`useHelmHooks: false`): as a
post-install hook it would wait, under Flux `--wait` and Argo PostSync, for
pods that wait for the migrations. Under Argo it is a `Sync` hook
(`argocd.argoproj.io/hook: Sync`, `BeforeHookCreation`), otherwise the Job
deleted by `ttlSecondsAfterFinished` would leave the application out of sync
and be recreated forever. Helm and Flux ignore these annotations. Migrations
are idempotent.

Argo order (`argocd.argoproj.io/sync-wave`, ignored by Helm and Flux):

| Wave | Objects |
| --- | --- |
| `-1` | `<release>-internal` ExternalSecret and its generators, read by the Job |
| `0` | the migration Job (Sync hook) and the configuration objects |
| `1` | the Deployments and StatefulSets, whose pods wait for the migrations |

An ExternalSecret apply refused by the ESO webhook (not serving yet) fails the
operation before the hook exists, and the Argo retry converges. The Job is
bounded by `activeDeadlineSeconds: 600` and `backoffLimit: 6` (set by the
wrapper, the upstream chart has no value for them): a run that cannot start
(another Secret missing) fails, which fails the operation since no workload of
its wave is left unhealthy, and the retry recreates it. Under Flux the Job is a
plain Job that waits for its Secrets as before; the deadline is above the
default release timeout.

## Upstream values

Any value of the vendored `airflow` chart can be set per instance under
`upstream.airflow`, merged over the values computed from the parameters
(okdp-lib-chart `okdp.vendor.render`, option `upstream`):

```yaml
upstream:
  airflow:
    images: {airflow: {repository: mirror.example.org/apache/airflow}}
    nodeSelector: {node-role.kubernetes.io/data: ""}
    env: [{name: AIRFLOW__CORE__PARALLELISM, value: "64"}]
    volumes: [{name: plugins, configMap: {name: airflow-plugins}}]  # appended to the CA bundle
    volumeMounts: [{name: plugins, mountPath: /opt/airflow/plugins}]
    config: {scheduler: {dag_dir_list_interval: "60"}}
```

The paths the platform relies on are refused, and the lists carrying the
chart's CA bundle and proxy variables are appended to rather than replaced: see
`okdp-airflow.upstream.airflow` in `templates/_values.tpl` (also listed in the
schema description). `extraEnv` is refused (a templated string carrying the
OIDC client and S3 credentials): add variables with `env`, `secret` or
`extraEnvFrom`. An upstream value wins over the parameter it overlaps
(`apiServer.resources.limits.memory` over `webserverMemoryGi`). No key or value
may contain `{{` (the schema and okdp-lib-chart both refuse it). `oidc-dcr`
takes no upstream values.

## Changes from the KuboCD package

- `<release>-internal` (was `creds-<release>-internal`), now also holding the
  Fernet key.
- Ingress TLS Secret `<release>-airflow-tls` (was `airflow-tls`).
- Resource names drop the KuboCD module suffix (`<release>-scheduler`, ...).
- The upstream `broker-url` pre-install hook Secret (unused with the
  KubernetesExecutor) is still rendered, as before.

## Tests

```sh
scripts/vendor-charts.sh charts/services/airflow   # download vendor/ (not committed)
helm dependency build charts/services/airflow
for f in charts/services/airflow/ci/*-values.yaml; do
  helm lint charts/services/airflow -f "$f"
  helm template demo-airflow charts/services/airflow -n demo -f "$f" >/dev/null
done
```
