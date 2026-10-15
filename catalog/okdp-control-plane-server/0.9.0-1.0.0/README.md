# okdp-control-plane-server

OKDP package of the control-plane API server. The server is a **Git writer**
for the desired state (instances, connections, projects, catalog in the
deployments repositories) and a **cluster reader** for the observed state
(workloads, HelmReleases or Applications). No database; its local clone (an
emptyDir) is only a cache.

A package in the okdp-compiler format, with no upstream chart: `Chart.yaml`
has no dependency and there is no values file. The server's ConfigMap,
Deployment, Service, ServiceAccount, ClusterRole and ClusterRoleBinding are
OKDP's own objects, written whole in the `objects` of `okdp.yaml`; the
compiled umbrella renders them (`okdp.objects.yaml`). They follow `chart/` of
the okdp-control-plane-server repository (the environment of
`internal/config/config.go`) and read `global.okdp`. What the instance
publishes (its usage) is `okdp.info.yaml`.

The package takes no upstream values (no `upstream.<chart>`): every object is
computed from the parameters below (`config.schema.json`).

## Parameters

| Parameter | Default | Environment | Description |
|---|---|---|---|
| `gitops.repoURL` | `""` | `GITOPS_REPO_URL` | The deployments repository (`https://`, `ssh://`, `git@host:path`) holding `platform/`, `projects/` and the compiled output. Required unless `gitops.topology` is set. |
| `gitops.branch` | `main` | `GITOPS_BRANCH` | |
| `gitops.path` | `""` | `GITOPS_PATH` | Directory of the layout, empty for the root. |
| `gitops.topology` | `{}` | `GITOPS_CONFIG` (mount) | The topology of the deployments repositories: `platform`, `projects` and `output`, each `{url, branch, path}` (the projects' `url` and `path` may hold `{project}`), and `forgejo` (`url`, `owner`), where the server creates a new project's repository in the split topology. Written to the ConfigMap `<release>-gitops`, mounted at `/etc/okdp/gitops/topology.yaml`; the package sets `forgejo.tokenFile` to `/etc/okdp/forgejo/token`. Empty: `repoURL`, `branch` and `path` hold everything (mono). |
| `gitops.forgejoTokenSecret` | `""` | (mount) | Secret of the release namespace whose key `token` is the Forgejo API token, mounted at `/etc/okdp/forgejo/token`. Required with `gitops.topology.forgejo`. |
| `gitops.chartCacheDir` | `/var/cache/okdp/charts` | `GITOPS_CHART_CACHE_DIR` | Where the server pulls the upstream charts it checks the compiled values against, an emptyDir. Empty: the server's default, under its clone. |
| `gitops.engine` | `flux` | `GITOPS_ENGINE` | `flux` or `argocd`; also selects the engine objects the ClusterRole reads. |
| `gitops.releasesNamespace` | `okdp-releases` | `GITOPS_RELEASES_NAMESPACE` | Flux HelmReleases/values ConfigMaps, `okdp-platform-values`. |
| `gitops.argocdNamespace` | `argocd` | `ARGOCD_NAMESPACE` | Argo CD Applications. |
| `gitops.credentialsSecret` | `""` | `GITOPS_CREDENTIALS_DIR` (mount) | Secret with write access, Flux GitRepository keys (`username`/`password`, `bearerToken`, `identity`/`known_hosts`). Mounted `0440` with the pod `fsGroup: 65534` (the image user), so the non-root server can read it; prefer it to credentials in `repoURL`. |
| `gitops.sshInsecureIgnoreHostKey` | `false` | `GITOPS_SSH_INSECURE_IGNORE_HOST_KEY` | Sandboxes only. |
| `gitops.author.name` / `.email` | `OKDP control plane` / `okdp-control-plane@okdp.io` | `GITOPS_AUTHOR_NAME` / `_EMAIL` | Commit author. |
| `consoleHost` | `okdp-ui.<ingress suffix>` | `ALLOWED_ORIGINS` (`https://<host>`) | Single allowed origin. |
| `logLevel` | `info` | `LOG_LEVEL` | |
| `insecureOciRegistries` | `""` | `INSECURE_OCI_REGISTRIES` | Plain-HTTP registries, sandboxes only. |
| `keycloak.credentialsSecret.name` | `""` | `KEYCLOAK_CLIENT_ID` / `KEYCLOAK_CLIENT_SECRET` (`secretKeyRef`) | Secret with the Keycloak service-account client credentials. Empty: user and group management is off, no env rendered. |
| `keycloak.credentialsSecret.clientIdKey` / `.clientSecretKey` | `client_id` / `client_secret` | | Keys of that Secret; the defaults match `global.okdp.identity.provisioning.keycloak.credentialsSecret`, so the same Secret can be reused. |
| `keycloak.url` / `keycloak.realm` | `""` | `KEYCLOAK_URL` / `KEYCLOAK_REALM` | Keycloak base URL (no `/realms/...`) and realm. Empty: derived by the server from the platform OIDC issuer `<url>/realms/<realm>`. |
| `keycloak.tlsInsecure` | `false` | `KEYCLOAK_TLS_INSECURE` | Skip the Keycloak certificate check. Sandboxes only (`global.okdp.oidc.insecureSkipVerify` also applies when the URL comes from the issuer). |
| `imageRepository` / `imageTag` | `quay.io/okdp/images/okdp-control-plane-server` / `0.9.0` | | An empty `imageTag` is the upstream half of the package version. |
| `resources` | `{}` | | |

Fixed: `PORT` 8093, `PLATFORM_NAMESPACE` = the release namespace,
`GITOPS_CLONE_DIR` (emptyDir). Platform values read from `global.okdp`:
`ingress.suffix` (default console host), `proxy` (`HTTP(S)_PROXY`,
`NO_PROXY`, both cases). The server reads the rest of the platform values
(OIDC...) itself from ConfigMap `<releasesNamespace>/okdp-platform-values`.

The Service `<release>` (port 8093) is what the console routes `/api` to.

## Topology

```yaml
gitops:
  topology:
    platform: {url: http://forgejo-http.forgejo.svc.cluster.local:3000/okdp/okdp-platform.git, branch: main}
    projects: {url: "http://forgejo-http.forgejo.svc.cluster.local:3000/okdp/okdp-project-{project}.git"}
    output: {url: http://forgejo-http.forgejo.svc.cluster.local:3000/okdp/okdp-output.git}
    forgejo: {url: http://forgejo-http.forgejo.svc.cluster.local:3000, owner: okdp}
  forgejoTokenSecret: okdp-forgejo-token
  credentialsSecret: okdp-gitops-credentials
```

The file the server reads, `/etc/okdp/gitops/topology.yaml`, is the
`topology` with `forgejo.tokenFile: /etc/okdp/forgejo/token`. A change of the
topology or of the environment restarts the pod (`checksum/config`). The
compile fails when neither `repoURL` nor `topology` is set, when the
topology lacks one of `platform`, `projects` and `output`, and when
`topology.forgejo` is set without `forgejoTokenSecret`.

## User and group management

The console's Identity pages (`/api/v1/identity`) manage users and groups of
the platform Keycloak realm through its Admin REST API. The client whose
credentials `keycloak.credentialsSecret` holds must be confidential, with
service accounts enabled, and its service account must hold the
`realm-management` client roles `view-users`, `query-users`, `manage-users`
and `query-groups` (no `manage-clients`: the server registers no client).
Without `keycloak.credentialsSecret.name` the identity routes answer `501`
and `/api/capabilities` reports `identity.userManagement: false`.

The `comment` and `uid` of a user are Keycloak user attributes: on Keycloak
24+ the realm user profile must allow them (unmanaged attributes enabled, or
both attributes declared), otherwise Keycloak silently drops them.

No RBAC change: Keycloak is reached over HTTPS, not through cluster objects.

## RBAC

ClusterRole, since project namespaces are created at run time.
Read-only: ConfigMaps (`okdp-platform-values`), workloads (`apps`,
`batch`), events, HelmReleases (`flux`) or Applications (`argocd`), pod
metrics, CRDs. Written by the server itself: namespaces (projects), Secrets
(connection credentials), pods/PVCs deletion (instance cleanup), ESO
SecretStores/ExternalSecrets, SparkApplications.

## Security context

The pod meets Pod Security `restricted`: it runs as 65534:65534 (the image
user, `runAsNonRoot`, `fsGroup: 65534`), with `seccompProfile: RuntimeDefault`,
no privilege escalation, every capability dropped and a read-only root
filesystem. The server writes only its clone, its chart cache (emptyDirs)
and `HOME=/tmp` (emptyDir `tmp`).

## Changes

- From the okdp-objects chart: the objects are the package's `objects`,
  rendered by the umbrella; their labels no longer carry `helm.sh/chart` and
  `app.kubernetes.io/version`. `checksum/config` hashes the environment and
  the topology.
- New parameters: `gitops.topology`, `gitops.forgejoTokenSecret`,
  `gitops.chartCacheDir`. `gitops.repoURL` is required only without a
  topology; an unknown `gitops.engine` is refused by the schema.
- From the KuboCD package: removed parameters `kubocdNamespace`,
  `releaseInterval`, `releaseTimeout`; no identity-management rules (users,
  groups and OIDC clients live in Keycloak); default image `0.9.0` (the
  Git-backed server).

## Tests

```sh
scripts/compile-charts.sh catalog/okdp-control-plane-server/0.9.0-1.0.0   # compile, check and render ci/*-values.yaml
```
