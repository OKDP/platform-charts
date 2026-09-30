{{/*
Values of the vendored charts: the former KuboCD module `values:` templates,
with .Context -> .Values.global.okdp, .Parameters -> .Values and the storage
connection resolved by okdp.connection.
*/}}

{{/* Module main: the spark-history-server chart. */}}
{{- define "okdp-shs.values.history" -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- if $oidc.enabled -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "oidc.issuerUri")) -}}
{{- end -}}
{{- if not .Values.s3SecretRef -}}
  {{- fail "spark-history-server: s3SecretRef is required: a Secret with the keys accessKey and secretKey, this instance's own S3 identity" -}}
{{- end -}}
{{- $s3 := include "okdp.connection" (dict "ctx" . "ref" .Values.storage "contract" "s3" "field" "storage") | fromYaml -}}
{{- $roles := .Values.roleMapping | default dict -}}
{{- $oauthSecret := include "okdp-shs.oauthSecret" . -}}
{{- if $oidc.dcr.enabled }}{{ $oauthSecret = include "okdp-shs.dcrSecret" . }}{{ end -}}
image:
  repository: quay.io/okdp/spark
  pullPolicy: IfNotPresent
  tag: "spark-3.5.6-scala-2.12-java-17"
resources:
  limits:
    cpu: {{ .Values.cpu | quote }}
    memory: {{ printf "%vGi" .Values.memoryGi | quote }}
  requests:
    cpu: 250m
    memory: 512Mi
# The web proxy addresses the history server by this name.
fullnameOverride: {{ include "okdp-shs.historyName" . }}
config:
  spark.history.fs.logDirectory: s3a://spark-events/event-logs
  spark.hadoop.fs.s3a.endpoint: {{ $s3.internalUrl | default $s3.apiUrl }}
  spark.hadoop.fs.s3a.path.style.access: {{ $s3.pathStyle | default false }}
  spark.history.fs.cleaner.enabled: true
  spark.history.fs.eventLog.rolling.maxFilesToRetain: 5
{{- if $oidc.enabled }}
  spark.ui.filters: io.okdp.spark.authc.OidcAuthFilter
  spark.io.okdp.spark.authc.OidcAuthFilter.param.issuer-uri: {{ $oidc.issuerUri }}
  spark.io.okdp.spark.authc.OidcAuthFilter.param.redirect-uri: {{ include "okdp-shs.redirectUri" . }}
  spark.io.okdp.spark.authc.OidcAuthFilter.param.scope: {{ include "okdp-shs.scope" . | replace " " "+" }}
  spark.io.okdp.spark.authc.OidcAuthFilter.param.cookie-max-age-minutes: 480
  # cookie-cipher-secret-key: not a property, the filter falls back to the
  # AUTH_COOKIE_ENCRYPTION_KEY env, read from the generated Secret (cookie-secret.yaml).
  spark.io.okdp.spark.authc.OidcAuthFilter.param.cookie-is-secure: true
  spark.io.okdp.spark.authc.OidcAuthFilter.param.use-pkce: {{ if hasKey $oidc "usePKCE" }}{{ $oidc.usePKCE }}{{ else }}true{{ end }}
  spark.history.ui.acls.enable: true
  spark.user.groups.mapping: io.okdp.spark.authz.OidcGroupMappingServiceProvider
{{- end }}
{{- with $roles.admin_groups }}
  spark.admin.acls.groups: {{ join "," . | quote }}
{{- end }}
{{- with $roles.history_admin_groups }}
  spark.history.ui.admin.acls.groups: {{ join "," . | quote }}
{{- end }}
{{- with $roles.modify_groups }}
  spark.modify.acls.groups: {{ join "," . | quote }}
{{- end }}
{{- with $roles.view_groups }}
  spark.ui.view.acls.groups: {{ join "," . | quote }}
{{- end }}
extraEnvs:
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
  {{- if $oidc.insecureSkipVerify }}
  # S3 certificate checking off (global.okdp.oidc.insecureSkipVerify); otherwise
  # the endpoint is verified against the CA bundle of JAVA_TOOL_OPTIONS.
  - name: SPARK_HISTORY_OPTS
    value: "-Dcom.amazonaws.sdk.disableCertChecking=true"
  {{- end }}
  - name: JAVA_TOOL_OPTIONS
    value: "-Djavax.net.ssl.trustStore=/cacerts/bundle.p12 -Djavax.net.ssl.trustStorePassword="
{{- if $oidc.enabled }}
  - name: AUTH_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: {{ $oauthSecret }}
        key: client_id
  - name: AUTH_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: {{ $oauthSecret }}
        key: client_secret
  - name: AUTH_COOKIE_ENCRYPTION_KEY
    valueFrom:
      secretKeyRef:
        name: {{ include "okdp-shs.cookieSecret" . }}
        key: cookie-cipher-secret-key
{{- end }}
extraVolumes:
  - name: cacerts
    secret:
      secretName: certs-bundle
extraVolumeMounts:
  - name: cacerts
    mountPath: /cacerts
{{- end -}}

{{/* Module oidc-dcr: registers the OAuth client (clientProvisioning: dcr). */}}
{{- define "okdp-shs.values.dcr" -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- if ne ($oidc.dcr.authMethod | default "") "anonymous" -}}
  {{- fail (printf "spark-history-server: global.okdp.oidc.dcr.authMethod %q is not supported: this chart registers anonymously" ($oidc.dcr.authMethod | default "")) -}}
{{- end -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "oidc.dcr.registrationUrl")) -}}
ttl_seconds: 30
registration_url: {{ $oidc.dcr.registrationUrl | quote }}
request:
  application_type: web
  client_name: {{ printf "%s-%s" .Release.Name .Release.Namespace | quote }}
  redirect_uris:
    - {{ include "okdp-shs.redirectUri" . | quote }}
  grant_types:
    - authorization_code
    - refresh_token
  # openid is not a Keycloak client scope: Keycloak refuses it here.
  scope: {{ without (splitList " " (include "okdp-shs.scope" .)) "openid" | join " " | quote }}
tls:
  insecure: false
  certificate: certs-bundle
secret: {{ include "okdp-shs.dcrSecret" . }}
mapping:
  use_default: false
  key_mapping:
    client_id: ".client_id"
    client_secret: ".client_secret"
{{- end -}}

{{/* Module proxy: the spark-web-proxy chart, the UI entry point. */}}
{{- define "okdp-shs.values.proxy" -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "ingress.className")) -}}
{{- $host := include "okdp-shs.host" . -}}
fullnameOverride: {{ include "okdp-shs.proxyName" . }}
image:
  repository: quay.io/okdp/spark-web-proxy
  pullPolicy: IfNotPresent
  tag: "0.2.1"
configuration:
  spark:
    history:
      service: {{ printf "%s.%s.svc.cluster.local" (include "okdp-shs.historyName" .) .Release.Namespace }}
    ui:
      proxyBase: /sparkui
    jobNamespaces:
      - {{ .Release.Namespace }}
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
      secretName: {{ include "okdp.fullname" (dict "ctx" . "suffix" "proxy-tls") }}
{{- end -}}
