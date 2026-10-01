{{/*
Values of the vendored charts: the former KuboCD module `values:` templates,
with .Context -> .Values.global.okdp, .Parameters -> .Values and the
connections resolved by okdp.connection.
*/}}

{{/* Module main: the trino chart. */}}
{{- define "okdp-trino.values.trino" -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "ingress.suffix" "ingress.className" "certificateIssuers.selfSigned.name" "oidc.issuerUri" "oidc.authUrl" "oidc.tokenUrl" "oidc.jwksUri")) -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- $host := include "okdp-trino.host" . -}}
{{- $catalogs := include "okdp-trino.catalogs" . | fromYamlArray -}}
{{- $oauthSecret := include "okdp-trino.oauthSecret" . -}}
{{- $clientSecret := dict "name" $oauthSecret "id" "client_id" "secret" "client_secret" -}}
{{- if $oidc.dcr.enabled -}}
  {{- $_ := set $clientSecret "name" (include "okdp-trino.dcrSecret" .) -}}
{{- end -}}
fullnameOverride: {{ include "okdp-trino.fullname" . }}
image:
  repository: trinodb/trino
  tag: "480"
{{- if $catalogs }}
catalogs:
  {{- range $c := $catalogs }}
  {{ $c.name }}: |
    {{- $c.properties | nindent 4 }}
  {{- end }}
{{- end }}
env:
  - name: TRINO_OAUTH_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: {{ $clientSecret.name }}
        key: {{ $clientSecret.id }}
  - name: TRINO_OAUTH_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: {{ $clientSecret.name }}
        key: {{ $clientSecret.secret }}
  {{- range $c := $catalogs }}
  {{- if $c.oidcSecret }}
  - name: ICEBERG_OAUTH_CLIENT_ID_{{ $c.envPrefix }}
    valueFrom:
      secretKeyRef:
        name: {{ $c.oidcSecret }}
        key: client_id
  - name: ICEBERG_OAUTH_CLIENT_SECRET_{{ $c.envPrefix }}
    valueFrom:
      secretKeyRef:
        name: {{ $c.oidcSecret }}
        key: client_secret
  # Kubernetes expands $(VAR) from variables declared earlier in this list.
  - name: ICEBERG_OAUTH_{{ $c.envPrefix }}
    value: "$(ICEBERG_OAUTH_CLIENT_ID_{{ $c.envPrefix }}):$(ICEBERG_OAUTH_CLIENT_SECRET_{{ $c.envPrefix }})"
  {{- end }}
  {{- end }}
  - name: TRINO_SHARED_SECRET
    valueFrom:
      secretKeyRef:
        name: {{ include "okdp-trino.internalSecret" . }}
        key: shared-secret
  - name: TRUSTSTORE_PASSWORD
    value: ""
  {{- range $c := $catalogs }}
  - name: S3_ACCESS_KEY_{{ $c.envPrefix }}
    valueFrom:
      secretKeyRef:
        name: {{ $c.s3Secret }}
        key: accessKey
  - name: S3_SECRET_ACCESS_{{ $c.envPrefix }}
    valueFrom:
      secretKeyRef:
        name: {{ $c.s3Secret }}
        key: secretKey
  {{- end }}
coordinator:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: "2"
      memory: {{ printf "%vGi" .Values.coordinatorMemoryGi | quote }}
  additionalVolumes:
    - name: cacerts
      secret:
        secretName: certs-bundle
  additionalVolumeMounts:
    - name: cacerts
      mountPath: /cacerts
      readOnly: true
  additionalJVMConfig:
    - "-Djavax.net.ssl.trustStore=/cacerts/bundle.p12"
    - "-Djavax.net.ssl.trustStorePassword=${ENV:TRUSTSTORE_PASSWORD}"
worker:
  resources:
    requests:
      cpu: {{ .Values.workerCpu | quote }}
      memory: {{ printf "%vGi" .Values.workerMemoryGi | quote }}
    limits:
      cpu: {{ mulf (float64 .Values.workerCpu) 2 | quote }}
      memory: {{ printf "%vGi" (mulf (float64 .Values.workerMemoryGi) 2) | quote }}
  additionalVolumes:
    - name: cacerts
      secret:
        secretName: certs-bundle
  additionalVolumeMounts:
    - name: cacerts
      mountPath: /cacerts
      readOnly: true
  additionalJVMConfig:
    - "-Djavax.net.ssl.trustStore=/cacerts/bundle.p12"
    - "-Djavax.net.ssl.trustStorePassword=${ENV:TRUSTSTORE_PASSWORD}"
ingress:
  enabled: true
  className: {{ .Values.global.okdp.ingress.className }}
  annotations:
    {{- include "okdp.ingressAnnotations" . | nindent 4 }}
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/use-regex: "true"
  hosts:
    - host: {{ $host }}
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - {{ $host }}
      secretName: {{ include "okdp.fullname" (dict "ctx" . "suffix" "tls") }}
server:
  workers: {{ .Values.numWorkers }}
  node:
    environment: sandbox
  config:
    authenticationType: oauth2
    coordinator: "true"
    node-scheduler.include-coordinator: "true"
    discovery-server.enabled: "true"
    path: /etc/trino
    https:
      enabled: false
  workerExtraConfig: ""
  coordinatorExtraConfig: |
    http-server.process-forwarded=true
    web-ui.authentication.type=oauth2
    # Enable two authentication flows on the coordinator:
    # - OAUTH2: interactive browser-based login for human users (UI/CLI with external authentication)
    # - JWT: non-interactive bearer token authentication for automation/service accounts
    #   such as scripts, jobs, or CI/CD using --access-token
    http-server.authentication.type=jwt,oauth2
    # In-cluster clients reach the coordinator on plain HTTP. Without this,
    # Trino answers 403 to any authenticated call that is not TLS.
    http-server.authentication.allow-insecure-over-http=true
    http-server.authentication.oauth2.issuer={{ $oidc.issuerUri }}
    http-server.authentication.oauth2.client-id=${ENV:TRINO_OAUTH_CLIENT_ID}
    http-server.authentication.oauth2.client-secret=${ENV:TRINO_OAUTH_CLIENT_SECRET}
    http-server.authentication.oauth2.auth-url={{ $oidc.authUrl }}
    http-server.authentication.oauth2.token-url={{ $oidc.tokenUrl }}
    http-server.authentication.oauth2.scopes={{ $oidc.scope | replace " " "," }}
    http-server.authentication.oauth2.principal-field=preferred_username

    http-server.authentication.jwt.key-file={{ $oidc.jwksUri }}
    http-server.authentication.jwt.required-issuer={{ $oidc.issuerUri }}
    http-server.authentication.jwt.required-audience=account
    http-server.authentication.jwt.principal-field=client_id
additionalConfigProperties:
  - internal-communication.shared-secret=${ENV:TRINO_SHARED_SECRET}
{{- if .Values.enableOPA }}
accessControl:
  type: properties
  properties: |
    access-control.name=opa
    opa.policy.uri=http://{{ include "okdp-trino.opaName" . }}.{{ .Release.Namespace }}:8181/{{ .Values.opaPolicyPath }}
    opa.log-responses={{ .Values.enableOPADebugLogs }}
    opa.log-requests={{ .Values.enableOPADebugLogs }}
{{- end }}
{{- end -}}

{{/*
Module opa: opa-kube-mgmt. Never set admissionController.enabled (nor expose it
in values.schema.json): upstream webhookconfiguration.yaml runs genCA and
genSignedCert, and okdp-guard-allow.yaml accepts that only because the
webhook stays disabled.
*/}}
{{- define "okdp-trino.values.opa" -}}
fullnameOverride: {{ include "okdp-trino.opaName" . }}
authz:
  enabled: false
image:
  repository: openpolicyagent/opa
  tag: 1.16.1
  pullPolicy: IfNotPresent
useHttps: false
port: 8181
{{- if .Values.enableOPADebugLogs }}
extraArgs:
  - "--set=status.console=true"
  - "--set=decision_logs.console=true"
{{- end }}
mgmt:
  enabled: {{ not .Values.enableOPAL }}
  startupProbe:
    failureThreshold: 5
    httpGet:
      path: /health
      port: 8181
      scheme: HTTP
    initialDelaySeconds: 20
    successThreshold: 1
    timeoutSeconds: 10
  data:
    enabled: true
  policies:
    enabled: true
rbac:
  create: {{ not .Values.enableOPAL }}
serviceAccount:
  create: {{ not .Values.enableOPAL }}
{{- end -}}

{{/* Module opal: the OPAL server and client feeding OPA from a policy repository. */}}
{{- define "okdp-trino.values.opal" -}}
{{- $secrets := include "okdp-trino.opalSecrets" . | fromYaml -}}
image:
  client:
    registry: docker.io
    repository: permitio/opal-client-standalone
    tag: 0.9.4
  server:
    registry: docker.io
    repository: permitio/opal-server
    tag: 0.9.4
client:
  extraEnv:
    OPAL_POLICY_STORE_URL: http://{{ include "okdp-trino.opaName" . }}.{{ .Release.Namespace }}:8181
    OPAL_POLICY_SUBSCRIPTION_DIRS: {{ .Values.OPAL_POLICY_SUBSCRIPTION_DIRS | quote }}
  secrets:
    - {{ $secrets.client }}
server:
  policyRepoUrl: {{ .Values.policyRepoUrl | quote }}
  policyRepoMainBranch: {{ .Values.policyRepoMainBranch | quote }}
  secrets:
    - {{ $secrets.ssh }}
    - {{ $secrets.master }}
  extraEnv:
    OPAL_POLICY_REPO_MANIFEST_PATH: {{ .Values.OPAL_POLICY_REPO_MANIFEST_PATH | quote }}
    {{- range $k, $v := include "okdp.proxy.env" . | fromYaml }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
{{- end -}}

{{/* Module oidc-dcr: registers the OAuth client (clientProvisioning: dcr). */}}
{{- define "okdp-trino.values.dcr" -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- if ne ($oidc.dcr.authMethod | default "") "anonymous" -}}
  {{- fail (printf "trino: global.okdp.oidc.dcr.authMethod %q is not supported: this chart registers anonymously" ($oidc.dcr.authMethod | default "")) -}}
{{- end -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "oidc.dcr.registrationUrl")) -}}
ttl_seconds: 30
registration_url: {{ $oidc.dcr.registrationUrl | quote }}
request:
  application_type: web
  client_name: {{ printf "%s-%s" .Release.Name .Release.Namespace | quote }}
  redirect_uris:
    - {{ printf "https://%s/oauth2/callback" (include "okdp-trino.host" .) | quote }}
  logo_uri: "https://landscape.cncf.io/logos/008125b82108f19aea6b0004ce5f255b72bab5b5e5c169a302d7bf845edb8e6b.svg"
  grant_types:
    - authorization_code
    - refresh_token
    - client_credentials
  # Keycloak realm client scopes granted to the registered client.
  scope: "web-origins acr roles profile groups basic email address phone organization offline_access microprofile-jwt"
tls:
  insecure: false
  certificate: certs-bundle
secret: {{ include "okdp-trino.dcrSecret" . }}
mapping:
  use_default: false
  key_mapping:
    client_id: ".client_id"
    client_secret: ".client_secret"
{{- end -}}
