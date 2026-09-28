# okdp-control-plane-ui

OKDP chart of the console, the web UI for basic users. The same ingress
serves the single-page app and routes `/api` to the control-plane server
Service, so the browser stays same-origin and the API has no host of its own.

The templates are this chart's own (Deployment, Service, Ingress): they
follow `chart/` of the okdp-control-plane-ui repository (the environment its
`docker-entrypoint.sh` writes into `config.js`) and read `global.okdp`.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `host` | `okdp-ui.<ingress suffix>` | Console host. |
| `oidcAuthority` | `global.okdp.oidc.issuerUri` | Issuer the console redirects to (`OIDC_AUTHORITY`). |
| `oidcClientId` | `global.okdp.oidc.clientId`, else `okdp-ui` | `OIDC_CLIENT_ID`. |
| `rolesClaim` | `groups` | ID token claim carrying the roles (`OIDC_ROLES_CLAIM`). |
| `adminRole` | `platform_admin` | Role opening the administration screens (`OIDC_ADMIN_ROLE`). |
| `backendService` | derived | Service `/api` goes to. Empty: this release name with its trailing `okdp-control-plane-ui` replaced by `okdp-control-plane-server` (the server chart names its Service after its release: components `okdp-control-plane-ui` and `okdp-control-plane-server` of project `okdp-system` give `okdp-system-okdp-control-plane-server`), else `okdp-control-plane-server`. |
| `backendPort` | `8093` | |
| `imageRepository` / `imageTag` | `quay.io/okdp/images/okdp-control-plane-ui` / `0.9.0` | |
| `resources` | `{}` | |

Platform values read from `global.okdp`: `ingress.suffix`,
`ingress.className`, `certificateIssuers.selfSigned.name`,
`oidc.issuerUri`, `oidc.clientId`, `proxy`.

## Security context

The pod meets Pod Security `restricted`: it runs as 1001 (the image user,
`runAsNonRoot`), with `seccompProfile: RuntimeDefault`, no privilege
escalation and every capability dropped. The root filesystem stays writable:
the entrypoint writes `config.js` and nginx its cache and pid file.

## Changes from the KuboCD package

- `backendService` no longer defaults to `okdp-control-plane-server-main`
  (KuboCD named a Service `<release>-<module>`): it follows the server
  release name.
- `oidcAuthority` is no longer required: it defaults to the platform issuer.
- The TLS Secret is `<release>-tls` (was `okdp-ui-tls`).

## Tests

```sh
helm dependency build charts/system/okdp-control-plane-ui
for f in charts/system/okdp-control-plane-ui/ci/*-values.yaml; do
  helm lint charts/system/okdp-control-plane-ui -f "$f"
  helm template okdp-system-okdp-control-plane-ui charts/system/okdp-control-plane-ui -n okdp-system -f "$f" >/dev/null
done
```
