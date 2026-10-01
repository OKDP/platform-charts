# trino

OKDP chart of [Trino](https://trino.io): distributed SQL over the project's
Hive and Iceberg catalogs, OAuth2 sign-in against the platform OIDC provider,
optional OPA authorization. It **consumes** `hive`, `iceberg-catalog` and `s3`
connections and **provides** a `trino` connection.

The former KuboCD modules are vendored upstream charts (`vendor.yaml`,
`vendor/`) rendered by `okdp.vendor.render` with computed values
(`templates/_values.tpl`):

| Former module | Now | Rendered when |
|---|---|---|
| `main` | `vendor/trino` (trinodb/charts 1.42.2) | always |
| `internal-secrets` | `okdp.generatedSecret` `<release>-internal` (ESO Password) | always |
| `opa` | `vendor/opa-kube-mgmt` 11.0.12 | `enableOPA` |
| `opal-secrets` | `templates/opal-secrets.yaml` (idempotent pre-install/pre-upgrade hook) | `enableOPA` and `enableOPAL` |
| `opal` | `vendor/opal` 0.0.30 | `enableOPA` and `enableOPAL` |
| `oidc-dcr` | `vendor/oidc-dcr` 0.3.3 (pre-install/pre-upgrade hook) | `global.okdp.oidc.clientProvisioning: dcr` |

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

A connection reference is either a connection file of the project
(`connections.<name>`) or, for `hive` and `iceberg-catalog`, the release name
of a hive-metastore or polaris instance in the same namespace (e.g.
`demo-hive`). `s3` references are always connection files.

Free-text parameters (connection references, secret names, `warehouse`,
`oauth2Scope`, the OPA/OPAL settings) may not contain `{{`, `}}` or line
breaks: they end up in catalog properties that the upstream chart passes
through `tpl`.

S3 credentials of a catalog: its `s3SecretRef`, else the release
`s3SecretRef`, else the `secretRef` of its s3 connection. The OAuth client of
an Iceberg catalog: its `oidcSecretRef`, else `creds-<release>-oauth2`.
An Iceberg catalog on an internal Polaris must set `warehouse` (the realm is a
Polaris parameter, not derivable from the release name).

Platform values read (`global.okdp`): `ingress.suffix`, `ingress.className`,
`certificateIssuers.selfSigned.name`, `oidc.{issuerUri,authUrl,tokenUrl,jwksUri,scope,clientProvisioning,dcr}`, `proxy`.

Secrets expected in the namespace: `creds-<release>-oauth2`
(`client_id`/`client_secret`, when `clientProvisioning` is `existing`; with `dcr`
the oidc-dcr Job `<release>-oidc-dcr` writes `<release>-<namespace>-dcr`, same keys), the S3
identities, and `certs-bundle` (`bundle.p12`, the CA trust store).

## Upstream values

Any value of the vendored `trino` and `opa-kube-mgmt` charts can be set per
instance under `upstream.<chart>`, merged over the values computed from the
parameters (okdp-lib `okdp.vendor.render`, option `upstream`):

```yaml
upstream:
  trino:
    image: {repository: mirror.example.org/trinodb/trino}
    worker: {tolerations: [{key: dedicated, operator: Exists, effect: NoSchedule}]}
    env: [{name: EXTRA_FLAG, value: "1"}]          # appended to the chart's env
    catalogs: {memory: "connector.name=memory\n"}  # added to the generated catalogs
  opa-kube-mgmt:
    resources: {limits: {memory: 256Mi}}
```

The paths the platform relies on are refused, and the lists carrying the
chart's Secrets are appended to rather than replaced: see
`okdp-trino.upstream.trino` and `okdp-trino.upstream.opa` in
`templates/_values.tpl` (also listed in the schema descriptions). An upstream
value wins over the parameter it overlaps (`server.workers` over
`numWorkers`). No key or value may contain `{{` (the schema and okdp-lib both
refuse it). `opal` and `oidc-dcr` take no upstream values.

## Provided connection

`<release>` (contract `trino`):

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
- Connection references name a connection file or a release (were
  `kcd-<release>-<output>` Connection objects).

## Tests

```sh
scripts/vendor-charts.sh charts/services/trino   # download vendor/ (not committed)
helm dependency build charts/services/trino
for f in charts/services/trino/ci/*-values.yaml; do
  helm lint charts/services/trino -f "$f"
  helm template demo-trino charts/services/trino -n demo -f "$f" >/dev/null
done
```

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
