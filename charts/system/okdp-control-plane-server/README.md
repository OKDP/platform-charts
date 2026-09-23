# okdp-control-plane-server

OKDP chart of the control-plane API server. The server is a **Git writer**
for the desired state (instances, connections, projects, catalog in the
deployments repository) and a **cluster reader** for the observed state
(descriptor ConfigMaps, workloads, HelmReleases or Applications). No
database; its local clone (an emptyDir) is only a cache.

The templates are this chart's own (Deployment, Service, ConfigMap,
ServiceAccount, ClusterRole): they follow `chart/` of the
okdp-control-plane-server repository (the environment of
`internal/config/config.go`) and read `global.okdp`. The former KuboCD
module rendered the published `quay.io/okdp/charts/okdp-control-plane-server`
0.7.1, whose settings and RBAC are the KuboCD ones.

## Parameters

| Parameter | Default | Environment | Description |
|---|---|---|---|
| `gitops.repoURL` | (required) | `GITOPS_REPO_URL` | Deployments repository (`https://`, `ssh://`, `git@host:path`). |
| `gitops.branch` | `main` | `GITOPS_BRANCH` | |
| `gitops.path` | `""` | `GITOPS_PATH` | Directory of the layout, empty for the root. |
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
| `imageRepository` / `imageTag` | `quay.io/okdp/images/okdp-control-plane-server` / `0.9.0` | | |
| `resources` | `{}` | | |

Fixed: `PORT` 8093, `PLATFORM_NAMESPACE` = the release namespace,
`GITOPS_CLONE_DIR` (emptyDir). Platform values read from `global.okdp`:
`ingress.suffix` (default console host), `proxy` (`HTTP(S)_PROXY`,
`NO_PROXY`, both cases). The server reads the rest of the platform values
(OIDC...) itself from ConfigMap `<releasesNamespace>/okdp-platform-values`.

The Service `<release>` (port 8093) is what the console routes `/api` to.

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
Read-only: ConfigMaps (descriptors, `okdp-platform-values`), workloads
(`apps`, `batch`), events, HelmReleases (`flux`) or Applications (`argocd`),
pod metrics, CRDs. Written by the server itself: namespaces (projects),
Secrets (connection credentials), pods/PVCs deletion (instance cleanup),
ESO SecretStores/ExternalSecrets,
SparkApplications. No `kubocd.kubotal.io` rule any more.

## Changes from the KuboCD package

- Removed parameters: `kubocdNamespace`, `releaseInterval`, `releaseTimeout`
  (the server has no KuboCD any more). New: `gitops.*`, `keycloak.*`,
  `resources`.
- No identity-management rules: users, groups and OIDC clients live in
  Keycloak, not in cluster objects.
- Default image `0.9.0` (the Git-backed server); the KuboCD one was 0.8.0.

## Tests

```sh
helm dependency build charts/system/okdp-control-plane-server
for f in charts/system/okdp-control-plane-server/ci/*-values.yaml; do
  helm lint charts/system/okdp-control-plane-server -f "$f"
  helm template okdp-system-okdp-control-plane-server charts/system/okdp-control-plane-server -n okdp-system -f "$f" >/dev/null
done
```
