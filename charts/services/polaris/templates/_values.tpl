{{/*
Values of the vendored charts: the former KuboCD module `values:` templates,
with .Context -> .Values.global.okdp, .Parameters -> .Values and the
connections resolved by okdp.connection.
*/}}

{{/*
Modules bootstrap and principals: the polaris-admin chart, one phase each.
Both Jobs are post-install/post-upgrade hooks (Argo: PostSync), bootstrap
first (weight -5), then principals (weight 5): the root credentials come from
an ESO ExternalSecret, a regular object, so a pre-install hook would wait for
a Secret created after it. Polaris starts before its realm is bootstrapped
and serves it once the bootstrap Job is done; the principals Job waits for
Polaris to answer. Both Jobs are idempotent (already bootstrapped / 409).
*/}}
{{- define "okdp-polaris.values.bootstrap" -}}
{{- $db := include "okdp-polaris.db" . | fromYaml -}}
fullnameOverride: {{ include "okdp.fullname" . }}
phase: bootstrap
bootstrap:
  purge: false
  image:
    repository: apache/polaris-admin-tool
    tag: 1.3.0-incubating
    pullPolicy: IfNotPresent
  database:
    jdbcUrl: {{ printf "jdbc:postgresql://%v:%v/%v" $db.host $db.port $db.dbName | quote }}
    secret:
      name: {{ $db.secretRef.name }}
      usernameKey: username
      passwordKey: password
  annotations:
    helm.sh/hook: post-install,post-upgrade
    helm.sh/hook-weight: "-5"
    helm.sh/hook-delete-policy: before-hook-creation
realms:
  {{- include "okdp-polaris.adminRealms" . | nindent 2 }}
{{- end -}}

{{- define "okdp-polaris.values.principals" -}}
fullnameOverride: {{ include "okdp.fullname" . }}
phase: principals
principals:
  image:
    repository: curlimages/curl
    tag: 8.18.0
    pullPolicy: IfNotPresent
  polaris:
    url: {{ include "okdp-polaris.internalUrl" . }}
  # The chart defaults this to a bundle path, and curl refuses a --cacert
  # that does not exist. The in-cluster call is plain HTTP.
  caCertPath: ""
  annotations:
    helm.sh/hook: post-install,post-upgrade
    helm.sh/hook-weight: "5"
    helm.sh/hook-delete-policy: before-hook-creation
realms:
  {{- include "okdp-polaris.adminRealms" . | nindent 2 }}
{{- end -}}

{{/* Module main: the polaris chart. */}}
{{- define "okdp-polaris.values.polaris" -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "ingress.className" "oidc.issuerUri")) -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- $db := include "okdp-polaris.db" . | fromYaml -}}
{{- $s3 := include "okdp.connection" (dict "ctx" . "ref" .Values.storage "contract" "s3" "field" "storage") | fromYaml -}}
{{- if not .Values.s3SecretRef -}}
  {{- fail "polaris: s3SecretRef is required: a Secret with the keys accessKey and secretKey, this instance's own S3 identity" -}}
{{- end -}}
{{- $host := include "okdp-polaris.host" . -}}
{{- $oauthSecret := include "okdp-polaris.oauthSecret" . -}}
{{- if $oidc.dcr.enabled }}{{ $oauthSecret = include "okdp-polaris.dcrSecret" . }}{{ end -}}
# The Service name the iceberg-catalog contract promises internal references.
fullnameOverride: {{ include "okdp-polaris.fullname" . }}
image:
  repository: apache/polaris
  pullPolicy: IfNotPresent
  tag: "1.3.0-incubating"
resources:
  limits:
    memory: {{ printf "%vGi" .Values.memoryGi | quote }}
  requests:
    memory: 512Mi
extraEnv:
  # S3
  - name: AWS_REGION
    value: {{ $s3.region | quote }}
  - name: AWS_ENDPOINT_URL_S3
    value: {{ $s3.apiUrl | quote }}
  - name: AWS_ENDPOINT_URL_STS
    value: {{ $s3.apiUrl | quote }}
  # The Polaris S3 identity for STS
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: {{ .Values.s3SecretRef }}
        key: accessKey
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: {{ .Values.s3SecretRef }}
        key: secretKey
  # Polaris Database
  - name: QUARKUS_DATASOURCE_JDBC_URL
    value: {{ printf "jdbc:postgresql://%v:%v/%v" $db.host $db.port $db.dbName | quote }}
  - name: QUARKUS_DATASOURCE_USERNAME
    valueFrom:
      secretKeyRef:
        name: {{ $db.secretRef.name }}
        key: username
  - name: QUARKUS_DATASOURCE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ $db.secretRef.name }}
        key: password
  - name: QUARKUS_OIDC_TLS_CONFIGURATION_NAME
    value: "oidc"
  - name: QUARKUS_TLS__OIDC__TRUST_STORE_PEM_CERTS
    value: "/cacerts/ca.crt"
  # OIDC, Enable multi-tenancy (Multiple realms)
  - name: QUARKUS_OIDC_TENANT-ENABLED
    value: "true"
  - name: QUARKUS_OIDC_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: {{ $oauthSecret }}
        key: client_id
  # Trust The CA
  - name: JAVA_TOOL_OPTIONS
    value: >-
      -Djavax.net.ssl.trustStore=/cacerts/bundle.p12
      -Djavax.net.ssl.trustStoreType=PKCS12
      -Djavax.net.ssl.trustStorePassword=
persistence:
  type: relational-jdbc
features:
  DROP_WITH_PURGE_ENABLED: true
  SUPPORTED_CATALOG_STORAGE_TYPES:
    - S3
  realmOverrides: {}
realmContext:
  type: default
  realms:
    - {{ .Values.realm | quote }}
advancedConfig:
  polaris.realm-context.header-name: "Polaris-Realm"
  quarkus.http.cors.enabled: "true"
authentication:
  type: mixed
oidc:
  authServeUrl: {{ $oidc.issuerUri }}
  client:
    id: null
    secret:
      name: {{ $oauthSecret }}
      key: client_secret
  # Map polaris internal principal and roles with OIDC principal and roles
  principalMapper:
    type: default
    idClaimPath: null
    nameClaimPath: "preferred_username"
  # Mapped OIDC roles are visible, but they do not have the same effect as internal Polaris assignments.
  # Issue: https://github.com/apache/polaris/issues/2373
  # Active Polaris roles = (mapped external roles) ∩ (principal roles granted in Polaris)
  principalRolesMapper:
    type: default
    rolesClaimPath: realm_access/roles
    filter: "^(?!default-roles-.*|offline_access$|uma_authorization$).*$"
    mappings:
      # polaris_service_admin -> PRINCIPAL_ROLE:service_admin
      - regex: "^polaris_(.*)$"
        replacement: "PRINCIPAL_ROLE:$1"
      # Fallback for normal roles, but do NOT touch values already prefixed by Polaris.
      - regex: "^(?!PRINCIPAL_ROLE:)(?!polaris_)(.*)$"
        replacement: "PRINCIPAL_ROLE:$1"
logging:
  level: INFO
cors:
  allowedOrigins:
    - {{ include "okdp.url" (dict "ctx" . "name" "polaris-console") | quote }}
  allowedMethods: ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
  allowedHeaders: ["Content-Type", "Authorization", "Polaris-Realm", "X-Request-ID"]
  exposedHeaders: ["*"]
  accessControlMaxAge: "PT10M"
  accessControlAllowCredentials: true
ingress:
  enabled: true
  className: {{ .Values.global.okdp.ingress.className }}
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    {{- include "okdp.ingressAnnotations" . | nindent 4 }}
  hosts:
    - host: {{ $host }}
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - {{ $host }}
      secretName: {{ include "okdp.fullname" (dict "ctx" . "suffix" "tls") }}
extraVolumes:
  - name: cacerts
    secret:
      secretName: certs-bundle
extraVolumeMounts:
  - name: cacerts
    mountPath: /cacerts
{{- end -}}

{{/* Module console: the polaris-console chart. */}}
{{- define "okdp-polaris.values.console" -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "ingress.className" "oidc.issuerUri")) -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- $apiUrl := include "okdp.url" (dict "ctx" . "name" "polaris") -}}
{{- $consoleUrl := include "okdp.url" (dict "ctx" . "name" "polaris-console") -}}
{{- $host := include "okdp-polaris.consoleHost" . -}}
fullnameOverride: {{ include "okdp.fullname" (dict "ctx" . "suffix" "polaris-console") }}
image:
  repository: quay.io/okdp/polaris-console
  tag: v0.1.1
  pullPolicy: Always
env:
  polarisApiUrl: {{ $apiUrl | quote }}
  polarisRealm: {{ .Values.realm | quote }}
  oauthTokenUrl: {{ printf "%s/api/catalog/v1/oauth/tokens" $apiUrl | quote }}
extraEnv:
  VITE_OIDC_ISSUER_URL: {{ $oidc.issuerUri | quote }}
  # dcr mode: read from the console's DCR Secret instead (templates/polaris-console.yaml).
  VITE_OIDC_CLIENT_ID: "polaris-console"
  VITE_OIDC_REDIRECT_URI: {{ printf "%s/auth/callback" $consoleUrl | quote }}
  VITE_OIDC_SCOPE: {{ include "okdp-polaris.consoleScope" . | quote }}
ingress:
  enabled: true
  className: {{ .Values.global.okdp.ingress.className }}
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    {{- include "okdp.ingressAnnotations" . | nindent 4 }}
  hosts:
    - host: {{ $host }}
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: {{ include "okdp.fullname" (dict "ctx" . "suffix" "polaris-console-tls") }}
      hosts:
        - {{ $host }}
{{- end -}}

{{/*
Module oidc-dcr: registers the OAuth clients (clientProvisioning: dcr). The
server's, confidential: it validates the bearer tokens (no user login).
*/}}
{{- define "okdp-polaris.values.dcr" -}}
{{- $oidc := include "okdp-polaris.dcrCheck" . | fromYaml -}}
ttl_seconds: 30
registration_url: {{ $oidc.dcr.registrationUrl | quote }}
request:
  application_type: web
  client_name: {{ printf "%s-%s" .Release.Name .Release.Namespace | quote }}
  grant_types:
    - client_credentials
  # openid is not a Keycloak client scope: Keycloak refuses it here.
  scope: {{ without (splitList " " $oidc.scope) "openid" | join " " | quote }}
tls:
  insecure: false
  certificate: certs-bundle
secret: {{ include "okdp-polaris.dcrSecret" . }}
mapping:
  use_default: false
  key_mapping:
    client_id: ".client_id"
    client_secret: ".client_secret"
{{- end -}}

{{/* The console's, public (a browser application): authorization code with PKCE. */}}
{{- define "okdp-polaris.values.consoleDcr" -}}
{{- $oidc := include "okdp-polaris.dcrCheck" . | fromYaml -}}
ttl_seconds: 30
registration_url: {{ $oidc.dcr.registrationUrl | quote }}
request:
  application_type: web
  client_name: {{ printf "%s-%s-console" .Release.Name .Release.Namespace | quote }}
  token_endpoint_auth_method: none
  redirect_uris:
    - {{ printf "%s/auth/callback" (include "okdp.url" (dict "ctx" . "name" "polaris-console")) | quote }}
  grant_types:
    - authorization_code
    - refresh_token
  scope: {{ without (splitList " " (include "okdp-polaris.consoleScope" .)) "openid" | join " " | quote }}
tls:
  insecure: false
  certificate: certs-bundle
secret: {{ include "okdp-polaris.consoleDcrSecret" . }}
mapping:
  use_default: false
  key_mapping:
    client_id: ".client_id"
{{- end -}}

{{/* okdp.oidc, checked for the DCR modules (anonymous registration). */}}
{{- define "okdp-polaris.dcrCheck" -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- if ne ($oidc.dcr.authMethod | default "") "anonymous" -}}
  {{- fail (printf "polaris: global.okdp.oidc.dcr.authMethod %q is not supported: this chart registers anonymously" ($oidc.dcr.authMethod | default "")) -}}
{{- end -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "oidc.dcr.registrationUrl")) -}}
{{- toYaml $oidc -}}
{{- end -}}

{{/*
Instance-level upstream values (okdp.vendor.render option `upstream`): an
instance sets any value of the vendored chart under upstream.<chart> in its
values.yaml, over the values computed above, except the protected paths.
Protected: what the platform relies on (the Service name and port of the
iceberg-catalog contract, the metastore database, the S3 identity, the realm
the connection publishes and polaris-admin bootstraps, sign-in through the
identity provider and its role mapping, the published ingress host) and
serviceMonitor (.Capabilities.APIVersions, which differ between Flux and Argo
CD; okdp-guard-allow.yaml accepts it only while disabled). authentication.tokenBroker
and tokenService stay open (a key pair Secret shared by the replicas).
advancedConfig merges: its keys contain dots, so they cannot be protected one
by one. Appended: the lists carrying the wrapper's Secrets, CA bundle and the
console origin, so an instance adds to them.
*/}}
{{- define "okdp-polaris.upstream.polaris" -}}
protect:
  - fullnameOverride
  - service.ports
  - persistence
  - storage
  - realmContext
  - authentication.type
  - authentication.authenticator
  - authentication.realmOverrides
  - oidc
  - ingress.enabled
  - ingress.className
  - ingress.hosts
  - ingress.tls
  - serviceMonitor
append:
  - extraEnv
  - extraVolumes
  - extraVolumeMounts
  - cors.allowedOrigins
{{- end -}}

{{/*
upstream.polaris-console. Protected besides the name: what points it at this
Polaris and its realm, the OIDC sign-in (VITE_OIDC_CLIENT_ID is re-pointed to
the DCR Secret by templates/polaris-console.yaml) and the ingress host whose
callback URL is registered with the identity provider. extraEnv is a map: an
instance adds variables to it.
*/}}
{{- define "okdp-polaris.upstream.console" -}}
protect:
  - fullnameOverride
  - env.polarisApiUrl
  - env.polarisRealm
  - env.oauthTokenUrl
  - extraEnv.VITE_OIDC_ISSUER_URL
  - extraEnv.VITE_OIDC_CLIENT_ID
  - extraEnv.VITE_OIDC_REDIRECT_URI
  - extraEnv.VITE_OIDC_SCOPE
  - ingress.enabled
  - ingress.className
  - ingress.hosts
  - ingress.tls
{{- end -}}

{{/*
upstream.polaris-admin, applied to both renders (bootstrap and principals):
bootstrap.* is read in the bootstrap phase only, principals.* in the
principals phase only, the rest (image settings aside) by both. Protected:
the name and phase, the realms (root credentials Secret, the realm and the
principals parameters), the metastore database, the hook annotations that
order the two Jobs, the URL of this Polaris, and bootstrap.purge (it would
drop every realm's catalogs at each upgrade). The wrapper sets no list.
*/}}
{{- define "okdp-polaris.upstream.admin" -}}
protect:
  - fullnameOverride
  - phase
  - realms
  - bootstrap.purge
  - bootstrap.database
  - bootstrap.annotations
  - principals.polaris.url
  - principals.annotations
{{- end -}}
