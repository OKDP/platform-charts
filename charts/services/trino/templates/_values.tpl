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
{{- $clientSecret := dict "name" (include "okdp.oidc.clientSecret" .) "id" "client_id" "secret" "client_secret" -}}
fullnameOverride: {{ include "okdp-trino.fullname" . }}
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
    limits:
      memory: {{ printf "%vGi" .Values.coordinatorMemoryGi | quote }}
worker:
  resources:
    requests:
      cpu: {{ .Values.workerCpu | quote }}
      memory: {{ printf "%vGi" .Values.workerMemoryGi | quote }}
    limits:
      cpu: {{ mulf (float64 .Values.workerCpu) 2 | quote }}
      memory: {{ printf "%vGi" (mulf (float64 .Values.workerMemoryGi) 2) | quote }}
server:
  workers: {{ .Values.numWorkers }}
  # Keep ingress right after this block scalar: followed by a trimming action
  # instead, it would lose its final newline (and the coordinator config change).
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
ingress:
  className: {{ .Values.global.okdp.ingress.className }}
  annotations:
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
{{- if .Values.enableOPADebugLogs }}
extraArgs:
  - "--set=status.console=true"
  - "--set=decision_logs.console=true"
{{- end }}
mgmt:
  enabled: {{ not .Values.enableOPAL }}
rbac:
  create: {{ not .Values.enableOPAL }}
serviceAccount:
  create: {{ not .Values.enableOPAL }}
{{- end -}}

{{/* Module opal: the OPAL server and client feeding OPA from a policy repository. */}}
{{- define "okdp-trino.values.opal" -}}
{{- $secrets := include "okdp-trino.opalSecrets" . | fromYaml -}}
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

{{/*
Instance-level upstream values (okdp.vendor.render option `upstream`): an
instance sets any value of the vendored chart under upstream.<chart> in its
values.yaml, over the values computed above, except the protected paths.
Protected: what the platform relies on (names used by the trino contract and
the OPA URL, OIDC sign-in, the ingress host registered with the identity
provider, OPA access control). Appended: the lists carrying the wrapper's
Secrets, truststore and shared secret, so an instance adds to them.
*/}}
{{- define "okdp-trino.upstream.trino" -}}
protect:
  - fullnameOverride
  - server.config.authenticationType
  - server.config.https
  - server.coordinatorExtraConfig
  - auth
  - accessControl
  - ingress.enabled
  - ingress.className
  - ingress.hosts
  - ingress.tls
append:
  - env
  - additionalConfigProperties
  - coordinator.additionalVolumes
  - coordinator.additionalVolumeMounts
  - coordinator.additionalJVMConfig
  - worker.additionalVolumes
  - worker.additionalVolumeMounts
  - worker.additionalJVMConfig
{{- end -}}

{{/*
upstream.opa-kube-mgmt. Protected besides names and the port Trino calls:
admissionController (its template runs genCA/genSignedCert, accepted by
okdp-guard-allow.yaml only while disabled), prometheus and serviceMonitor
(.Capabilities.APIVersions, which differ between Flux and Argo CD), and the
switches enableOPAL drives.
*/}}
{{- define "okdp-trino.upstream.opa" -}}
protect:
  - fullnameOverride
  - authz
  - useHttps
  - port
  - admissionController
  - prometheus
  - serviceMonitor
  - mgmt.enabled
  - rbac.create
  - serviceAccount.create
append:
  - extraArgs
{{- end -}}
