# airflow

OKDP package of [Apache Airflow](https://airflow.apache.org/) 3.2.1 with the
KubernetesExecutor, OIDC login (Flask AppBuilder) and DAGs from git-sync. It
**consumes** a `database-server` and an `s3` connection and provides none.

A package in the okdp-compiler format: the former KuboCD modules are the
upstream chart of `Chart.yaml`, whose values `values.cel.yaml` computes from
the parameters below (`config.schema.json`), over OKDP's defaults
(`airflow.defaults.yaml`), the OAuth client of `okdp.yaml` (`oidcClients`)
and OKDP's own objects (`objects` of `okdp.yaml`, rendered by the umbrella):

| Former module | Now | Compiled when |
|---|---|---|
| `oidc-dcr` | `oidcClients`: the compiler adds chart `oidc-dcr` (the platform's oidc-dcr chart, `oci://quay.io/adaltas/oidc-dcr` 0.5.0 by default): Job `<release>-oidc-dcr` (pre-install/pre-upgrade hook) | only with `global.okdp.oidc.clientProvisioning: dcr` |
| `internal-secrets` | `objects`: ESO `Password` generators + `ExternalSecret` `<release>-internal` | always |
| `main` | chart `airflow` 1.22.0 (`https://airflow.apache.org`), rendered as published, its bundled `postgresql` subchart disabled (`postgresql.enabled: false`, protected): `<release>-*`, ingress `airflow-<namespace>.<suffix>` | always |

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `db` | (required) | `database-server` connection of the metadata database. Checked only (its contract; Airflow reads `metadataSecret`). |
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
is now disabled through `fernetKeySecretName`). The chart's other random
templates are kept off by protected switches (`okdp.yaml`: the `*SecretName`
keys, `airflowVersion`, `redis.enabled`, `executor`). The Secret, its ExternalSecret
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

The waves of the workloads are the chart's `apiServer`, `scheduler`,
`dagProcessor` and `triggerer` `annotations` values (`values.cel.yaml`); a
component an instance enables through upstream values (statsd, pgbouncer...)
stays in wave `0`, its pods do not wait for the migrations. An ExternalSecret
apply refused by the ESO webhook (not serving yet) fails the operation before
the hook exists, and the Argo retry converges. A failed Job fails the
operation since no workload of its wave is left unhealthy, and the retry
recreates it. The upstream chart has no value for the Job's
`activeDeadlineSeconds` and `backoffLimit`: see Known gaps. Under Flux the Job
is a plain Job that waits for its Secrets as before.

## Upstream values

Any value of the `airflow` chart can be set per instance, under
`upstream.airflow`, merged over the values computed from the parameters
(`upstream` in `okdp.yaml`):

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
`protect` and `append` in `okdp.yaml` (also listed in the schema
description). `extraEnv` is refused (a templated string carrying the
OIDC client and S3 credentials): add variables with `env`, `secret` or
`extraEnvFrom`. An upstream value wins over the parameter it overlaps
(`apiServer.resources.limits.memory` over `webserverMemoryGi`). No key or value
may contain `{{` (the schema and okdp-compile both refuse it). `oidc-dcr`
takes no upstream values.

## Changes from the KuboCD package

- `<release>-internal` (was `creds-<release>-internal`), now also holding the
  Fernet key.
- Ingress TLS Secret `<release>-airflow-tls` (was `airflow-tls`).
- Resource names drop the KuboCD module suffix (`<release>-scheduler`, ...).
- The upstream `broker-url` pre-install hook Secret (unused with the
  KubernetesExecutor) is still rendered, as before.

## Known gaps

What the former packages did to the rendered objects and the format cannot
express (okdp-compiler gap list):

- the migration Job no longer gets `activeDeadlineSeconds: 600` and
  `backoffLimit: 6` (the chart has no value for them): under Argo a run that
  cannot start (a Secret it reads is missing) keeps the operation waiting
  instead of failing it after 10 minutes; the Kubernetes default backoff
  limit is 6 anyway;
- `app.kubernetes.io/instance` now comes from the airflow chart's `labels`
  value: the chart also puts it on the KubernetesExecutor task pods
  (`pod_template_file`), and the content checksums of the configuration
  ConfigMaps (`checksum/airflow-config`, `checksum/api-server-config`)
  change with it (one rollout when moving to this format).

## Tests

```sh
scripts/compile-charts.sh catalog/airflow/3.2.1-1.0.0   # compile, check and render ci/*-values.yaml
```
