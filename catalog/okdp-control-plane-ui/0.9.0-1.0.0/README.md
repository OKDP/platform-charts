# okdp-control-plane-ui

OKDP package of the console, the web UI for basic users. The same ingress
serves the single-page app and routes `/api` to the control-plane server
Service, so the browser stays same-origin and the API has no host of its own.

A package in the okdp-compiler format, with no upstream chart: `Chart.yaml`
has no dependency and there is no values file. The console's Deployment,
Service and Ingress are OKDP's own objects, written whole in the `objects`
of `okdp.yaml`; the compiled umbrella renders them (`okdp.objects.yaml`).
They follow `chart/` of the okdp-control-plane-ui repository (the
environment its `docker-entrypoint.sh` writes into `config.js`) and read
`global.okdp`. What the instance publishes (its URL and usage) is
`okdp.info.yaml`.

The package takes no upstream values (no `upstream.<chart>`): every object is
computed from the parameters below (`config.schema.json`).

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `host` | `okdp-ui.<ingress suffix>` | Console host. |
| `oidcAuthority` | `global.okdp.oidc.issuerUri` | Issuer the console redirects to (`OIDC_AUTHORITY`). |
| `oidcClientId` | `global.okdp.oidc.clientId`, else `okdp-ui` | `OIDC_CLIENT_ID`. |
| `rolesClaim` | `groups` | ID token claim carrying the roles (`OIDC_ROLES_CLAIM`). |
| `adminRole` | `platform_admin` | Role opening the administration screens (`OIDC_ADMIN_ROLE`). |
| `backendService` | derived | Service `/api` goes to. Empty: this release name with its trailing `okdp-control-plane-ui` replaced by `okdp-control-plane-server` (the server package names its Service after its release: components `okdp-control-plane-ui` and `okdp-control-plane-server` of project `okdp-system` give `okdp-system-okdp-control-plane-server`), else `okdp-control-plane-server`. |
| `backendPort` | `8093` | |
| `imageRepository` / `imageTag` | `quay.io/okdp/images/okdp-control-plane-ui` / `0.9.0` | An empty `imageTag` is the upstream half of the package version. |
| `resources` | `{}` | |

Platform values read from `global.okdp`: `ingress.suffix`,
`ingress.className`, `certificateIssuers.selfSigned.name` (the last two
required, `okdp.yaml` `require`), `oidc.issuerUri`, `oidc.clientId`, `proxy`.

## Security context

The pod meets Pod Security `restricted`: it runs as 1001 (the image user,
`runAsNonRoot`), with `seccompProfile: RuntimeDefault`, no privilege
escalation and every capability dropped. The root filesystem stays writable:
the entrypoint writes `config.js` and nginx its cache and pid file.

## Changes

- From the okdp-objects chart: the objects are the package's `objects`,
  rendered by the umbrella; their labels no longer carry `helm.sh/chart` and
  `app.kubernetes.io/version`.
- From the KuboCD package: `backendService` no longer defaults to
  `okdp-control-plane-server-main` (KuboCD named a Service
  `<release>-<module>`), it follows the server release name;
  `oidcAuthority` defaults to the platform issuer; the TLS Secret is
  `<release>-tls` (was `okdp-ui-tls`).

## Tests

```sh
scripts/compile-charts.sh catalog/okdp-control-plane-ui/0.9.0-1.0.0   # compile, check and render ci/*-values.yaml
```
