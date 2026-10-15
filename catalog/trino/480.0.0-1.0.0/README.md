# trino

OKDP package of [Trino](https://trino.io): distributed SQL over the project's
Hive and Iceberg catalogs, OAuth2 sign-in against the platform OIDC provider,
optional OPA authorization. It **consumes** `hive`, `iceberg-catalog` and `s3`
connections and **provides** a `trino` connection.

A package in the okdp-compiler format: the former KuboCD modules are the
upstream charts of `Chart.yaml` (its dependencies), whose values
`values.cel.yaml` computes from the parameters (`config.schema.json`), over
OKDP's defaults (`<chart>.defaults.yaml`). `okdp.yaml` holds the platform
values required, what an instance may override, the catalogs computed once
(`vars`), the rules of the instance, the OAuth client, OKDP's own objects and
what the instance publishes:

| Former module | Now | Compiled when |
|---|---|---|
| `main` | chart `trino` (trinodb/charts 1.42.2) | always |
| `internal-secrets` | OKDP objects: ESO Password generator + ExternalSecret `<release>-internal` | always |
| `opa` | chart `opa-kube-mgmt` 11.0.12 | `enableOPA` |
| `opal-secrets` | OKDP objects: the opal-secrets Job (idempotent pre-install/pre-upgrade hook) | `enableOPA` and `enableOPAL` |
| `opal` | chart `opal` 0.0.30 | `enableOPA` and `enableOPAL` |
| `oidc-dcr` | `oidcClients` of `okdp.yaml`: the compiler adds the chart `oidc-dcr` (the platform's oidc-dcr chart, 0.5.0 by default): Job `<release>-oidc-dcr` (pre-install/pre-upgrade hook) | `global.okdp.oidc.clientProvisioning: dcr` |

OKDP's objects are rendered by the instance's umbrella chart
(`okdp.objects.yaml`), with the upstream charts.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `hiveCatalogs[]` | `[]` | `{name, metastore (hive connection), storage (s3 connection), s3SecretRef?}` |
| `icebergCatalogs[]` | `[]` | `{name, catalog (iceberg-catalog connection), storage (s3 connection), warehouse?, oidcSecretRef?, oauth2Scope?, s3SecretRef?}` |
| `s3SecretRef` | `""` | Default S3 identity (Secret with `accessKey`/`secretKey`) of the catalogs. |
| `numWorkers` | `1` | Workers. |
| `workerCpu` / `workerMemoryGi` | `0.5` / `2` | Worker requests; limits are twice the requests. |
| `coordinatorMemoryGi` | `8` | Coordinator memory limit (request 1 GiB). |
| `enableOPA` | `true` | OPA access control (`opaPolicyPath`, `enableOPADebugLogs`: OPA decision logs and Trino's `opa.log-requests`/`opa.log-responses`, off by default). |
| `enableOPAL` | `false` | Feed OPA from a policy repository (`policyRepoUrl`, `policyRepoMainBranch`, `OPAL_POLICY_SUBSCRIPTION_DIRS`, `OPAL_POLICY_REPO_MANIFEST_PATH`); off, kube-mgmt loads policies from labelled ConfigMaps. |

A connection reference is either a connection (`connections.<name>` of the
platform, the project or the instance) or, for `hive` and `iceberg-catalog`,
the release name of a hive-metastore or polaris instance in the same
namespace (e.g. `demo-hive`). `s3` references are always connections.

Free-text parameters (connection references, secret names, `warehouse`,
`oauth2Scope`, the OPA/OPAL settings) may not contain `{{`, `}}` or line
breaks: they end up in catalog properties that the upstream chart passes
through `tpl`.

S3 credentials of a catalog: its `s3SecretRef`, else the release
`s3SecretRef`, else the `secretRef` of its s3 connection. The OAuth client of
an Iceberg catalog: its `oidcSecretRef`, else `creds-<release>-oauth2`.
An Iceberg catalog on an internal Polaris must set `warehouse` (the realm is a
Polaris parameter, not derivable from the release name). A catalog without
S3 credentials or warehouse, or named twice (`tpch` and `tpcds` are built
in), fails the compile (`errors` of `okdp.yaml`).

Platform values read (`global.okdp`): `ingress.suffix`, `ingress.className`,
`certificateIssuers.selfSigned.name`, `oidc.{issuerUri,authUrl,tokenUrl,jwksUri,scope,clientProvisioning,dcr}`, `proxy`.

Secrets expected in the namespace: `creds-<release>-oauth2`
(`client_id`/`client_secret`, when `clientProvisioning` is `existing`; with `dcr`
the oidc-dcr Job `<release>-oidc-dcr` writes `<release>-<namespace>-dcr`, same keys), the S3
identities, and `certs-bundle` (`bundle.p12`, the CA trust store).

## Upstream values

Any value of the `trino` and `opa-kube-mgmt` charts can be set per instance,
under `upstream.<chart>`, merged over the values computed from the parameters
(`upstream` in `okdp.yaml`):

```yaml
upstream:
  trino:
    image: {repository: mirror.example.org/trinodb/trino}
    worker: {tolerations: [{key: dedicated, operator: Exists, effect: NoSchedule}]}
    env: [{name: EXTRA_FLAG, value: "1"}]          # appended to the computed env
    catalogs: {memory: "connector.name=memory\n"}  # added to the generated catalogs
  opa-kube-mgmt:
    resources: {limits: {memory: 256Mi}}
```

The paths the platform relies on are refused, and the lists carrying the
chart's Secrets are appended to rather than replaced: see `protect` and
`append` in `okdp.yaml` (also listed in the schema descriptions). The
switches of opa-kube-mgmt that would make Flux and Argo CD render different
objects (`admissionController`: genCA and genSignedCert; `prometheus`,
`serviceMonitor`: `.Capabilities`) are protected and stay off. An upstream
value wins over the parameter it overlaps (`server.workers` over
`numWorkers`). No key or value may contain `{{` (the schema and okdp-compile
both refuse it). `opal` and `oidc-dcr` take no upstream values.

## Provided connection

`<release>` (contract `trino`), in `okdp.instance.yaml`:

```yaml
url: https://trino-<namespace>.<suffix>
uri: trino://trino@trino-<namespace>.<suffix>:443
internalUri: trino://trino@<release>-trino.<namespace>.svc:8080
catalogs: [tpch, tpcds, <catalog names>]
```

## Changes from the KuboCD package

- Resources are named `<release>-trino-*` (was `<release>-main-trino-*`); the
  OPA service is `<release>-opa`, the OPAL secrets `<release>-opal-*` (were
  shared `opal-*-secret` names).
- The internal shared secret is `<release>-internal`, generated by ESO (was
  `creds-<release>-internal` from kubernetes-secret-generator).
- Connection references name a connection or a release (were
  `kcd-<release>-<output>` Connection objects).

## Known gaps

What the okdp-lib-chart chart did to the rendered objects and values cannot
express:

- the opa-kube-mgmt objects carry no `app.kubernetes.io/instance` label (the
  chart has no label value).

## Tests

```sh
scripts/compile-charts.sh catalog/trino/480.0.0-1.0.0   # compile, check and render ci/*-values.yaml
```

`ci/catalog-errors-values.yaml` must fail with the messages of the errors
section.

## Access guide

This document provides instructions on how to authenticate and interact with the TrinoDB service using the Command Line Interface (CLI) and the HTTP API.

### Authentication with Authorization Flow for Human User

Trino is configured with OAuth2 authentication. Before performing any operations, you must obtain a valid access token.

#### Retrieving the Access Token

1. **Log in** to the Trino web interface.
2. **Retrieve the token** from your browser cookies:
   - Open Developer Tools.
   - Look for the cookie named `__Secure-Trino-Oauth2-Token`.
   - Copy the token value.

3. **Export the token** as an environment variable for use in commands:

   ```bash
   export TOKEN="<PASTE_YOUR_OAUTH2_TOKEN_HERE>"
   ```

   > **Note**: The token is a long JWT string. Ensure you copy the entire value.

### Connection Methods

#### 1. Trino CLI

You can use the native `trino` CLI to run interactive queries. The following command connects to the Trino server securely using the exported token.

**Command:**

```bash
trino \
  --server=https://localhost:8443 \
  --user=usera \
  --access-token=$TOKEN \
  --insecure
```

**Parameters:**
- `--server`: The URL of the Trino coordinator. Use `localhost` if properly forwarded or running locally.
- `--user`: The username to identify as (e.g., `usera`).
- `--access-token`: The OAuth2 bearer token.
- `--insecure`: Skips SSL certificate validation (useful for self-signed certificates in sandbox environments).

---

#### 2. HTTP API (cURL)

You can interact with Trino programmatically using `cURL`. This is useful for testing connectivity or automating queries.

**Example: Show Catalogs**

```bash
curl -sk \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Trino-User: usera" \
  --data-binary 'SHOW CATALOGS' \
  https://trino-<TRINO_SUFFIX>.okdp.sandbox/v1/statement
```

**Header Details:**
- `X-Trino-User`: Specifies the effective user for the transaction.
- `Authorization`: Passes the Bearer token for authentication.

### Authentication with Client Credentials Flow for Service Account

#### Keycloak Side Configuration

You must create a specific "Client" for your application or automated script.

- **Client ID**: `trino-m2m-app` (for example).
- **Access Type**: `confidential`.
- **Service Accounts Enabled**: `ON` (This is the crucial option for M2M).
- **Standard Flow Enabled**: `OFF` (No need for browser redirection).
- **Mappers**: If needed, ensure you add a "Protocol Mapper" to include a `preferred_username` or `sub` field in the token, as Trino uses it to identify the user executing the query.

> In the **Service Account Roles** tab of the client, you can assign specific roles to this application to manage its permissions in Trino via RBAC.

#### Verification Example

To test the applicative user (M2M), follow these steps:

1. **Obtain the Access Token**:

   ```bash
   export SECRET="<YOUR_CLIENT_SECRET>"
   export CLIENT_ID="trino-m2m-app"
   
   # Adjust the Keycloak URL if needed
   curl -ks -X POST "https://keycloak.okdp.sandbox/realms/master/protocol/openid-connect/token" \
    -d "grant_type=client_credentials" \
    -d "scope=openid" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${SECRET}" | jq
   ```

2. **Export the Token**:

   ```bash
   export TOKEN="<ACCESS_TOKEN_FROM_RESPONSE>"

3. **Test with cURL**:

   ```bash
   # Adjust the Trino URL if needed
   curl -skL -X POST https://trino-<TRINO_SUFFIX>.okdp.sandbox/v1/statement \
     -H "Authorization: Bearer $TOKEN" \
     --data 'SHOW CATALOGS' | jq
   ```

4. **Test with Trino CLI**:

   ```bash
   # Ensure you have port-forwarded Trino to localhost:8443
   trino \
     --server=https://localhost:8443 \
     --user=service-account-${CLIENT_ID} \
     --access-token=$TOKEN \
     --insecure
   ```
