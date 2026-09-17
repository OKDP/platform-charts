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
| `gitops.credentialsSecret` | `""` | `GITOPS_CREDENTIALS_DIR` (mount) | Secret with write access, Flux GitRepository keys (`username`/`password`, `bearerToken`, `identity`/`known_hosts`). |
| `gitops.sshInsecureIgnoreHostKey` | `false` | `GITOPS_SSH_INSECURE_IGNORE_HOST_KEY` | Sandboxes only. |
| `gitops.author.name` / `.email` | `OKDP control plane` / `okdp-control-plane@okdp.io` | `GITOPS_AUTHOR_NAME` / `_EMAIL` | Commit author. |
| `consoleHost` | `okdp-ui.<ingress suffix>` | `ALLOWED_ORIGINS` (`https://<host>`) | Single allowed origin. |
| `logLevel` | `info` | `LOG_LEVEL` | |
| `insecureOciRegistries` | `""` | `INSECURE_OCI_REGISTRIES` | Plain-HTTP registries, sandboxes only. |
| `imageRepository` / `imageTag` | `quay.io/okdp/images/okdp-control-plane-server` / `0.9.0` | | |
| `resources` | `{}` | | |

Fixed: `PORT` 8093, `PLATFORM_NAMESPACE` = the release namespace,
`GITOPS_CLONE_DIR` (emptyDir). Platform values read from `global.okdp`:
`ingress.suffix` (default console host), `proxy` (`HTTP(S)_PROXY`,
`NO_PROXY`, both cases). The server reads the rest of the platform values
(OIDC...) itself from ConfigMap `<releasesNamespace>/okdp-platform-values`.

The Service `<release>` (port 8093) is what the console routes `/api` to.

## RBAC

ClusterRole, since project namespaces are created at run time.
Read-only: ConfigMaps (descriptors, `okdp-platform-values`), workloads
(`apps`, `batch`), events, HelmReleases (`flux`) or Applications (`argocd`),
pod metrics, CRDs. Written by the server itself: namespaces (projects),
Secrets (connection credentials), pods/PVCs deletion (instance cleanup),
kubauth users/groups/OIDC clients, ESO SecretStores/ExternalSecrets,
SparkApplications. No `kubocd.kubotal.io` rule any more.

## Changes from the KuboCD package

- Removed parameters: `kubocdNamespace`, `releaseInterval`, `releaseTimeout`
  (the server has no KuboCD any more). New: `gitops.*`, `resources`.
- Default image `0.9.0` (the Git-backed server); the KuboCD one was 0.8.0.

## Tests

```sh
helm dependency build charts/system/okdp-control-plane-server
for f in charts/system/okdp-control-plane-server/ci/*-values.yaml; do
  helm lint charts/system/okdp-control-plane-server -f "$f"
  helm template okdp-system-okdp-control-plane-server charts/system/okdp-control-plane-server -n okdp-system -f "$f" >/dev/null
done
```
