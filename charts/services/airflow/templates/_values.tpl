{{/*
Values of the vendored charts: the former KuboCD module `values:` templates,
with .Context -> .Values.global.okdp, .Parameters -> .Values and the
connections resolved by okdp.connection.
*/}}

{{/* Module main: the airflow chart. */}}
{{- define "okdp-airflow.values.airflow" -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "ingress.className")) -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- if $oidc.enabled -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "oidc.issuerUri" "oidc.authUrl" "oidc.tokenUrl")) -}}
{{- end -}}
{{- /* The db connection only gates the deployment: Airflow reads metadataSecret. */ -}}
{{- $_ := include "okdp.connection" (dict "ctx" . "ref" .Values.db "contract" "database-server" "field" "db") -}}
{{- $s3 := include "okdp.connection" (dict "ctx" . "ref" .Values.storage "contract" "s3" "field" "storage") | fromYaml -}}
{{- if not .Values.metadataSecret -}}
  {{- fail "airflow: metadataSecret is required: a Secret with the key connection holding the SQLAlchemy connection string" -}}
{{- end -}}
{{- if not .Values.s3SecretRef -}}
  {{- fail "airflow: s3SecretRef is required: a Secret with the keys accessKey and secretKey" -}}
{{- end -}}
{{- $host := include "okdp-airflow.host" . -}}
{{- $gitSync := deepCopy (.Values.dagsGitSync | default dict) -}}
{{- $gitSyncValues := omit $gitSync "credentialsSecret" -}}
{{- /* git-sync v4 lets the deprecated GIT_SYNC_BRANCH, fed by the chart
       default, override GITSYNC_REF. Mirroring ref onto branch keeps the
       modern key in charge. Done even when the caller set both, since
       leaving them to disagree silently serves the wrong revision. */ -}}
{{- if $gitSyncValues.ref -}}
{{- $_ := set $gitSyncValues "branch" $gitSyncValues.ref -}}
{{- end -}}
{{- with $gitSync.credentialsSecret -}}
{{- $_ := set $gitSyncValues "credentialsSecret" (required "airflow: dagsGitSync.credentialsSecret.name is required" .name) -}}
{{- end -}}
{{- $proxyEnv := include "okdp.proxy.envList" . | fromYamlArray -}}
{{- if $proxyEnv -}}
{{- $_ := set $gitSyncValues "env" $proxyEnv -}}
{{- end -}}
{{- /* In dcr mode the registration job writes the credentials, under the same keys. */ -}}
{{- $oauthSecret := include "okdp-airflow.oauthSecret" . -}}
{{- if $oidc.dcr.enabled -}}{{- $oauthSecret = include "okdp-airflow.dcrSecret" . -}}{{- end -}}
executor: KubernetesExecutor
defaultAirflowTag: "3.2.1"
airflowVersion: "3.2.1"
extraEnv: |
{{- if $oidc.enabled }}
  - name: AIRFLOW_OIDC_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: {{ $oauthSecret }}
        key: client_id
  - name: AIRFLOW_OIDC_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: {{ $oauthSecret }}
        key: client_secret
  - name: AIRFLOW_OIDC_API_BASE_URL
    value: {{ printf "%s/protocol/openid-connect" $oidc.issuerUri | quote }}
  - name: AIRFLOW_OIDC_ACCESS_TOKEN_URL
    value: {{ $oidc.tokenUrl | quote }}
  - name: AIRFLOW_OIDC_AUTHORIZE_URL
    value: {{ $oidc.authUrl | quote }}
  - name: AIRFLOW_OIDC_SERVER_METADATA_URL
    value: {{ printf "%s/.well-known/openid-configuration" $oidc.issuerUri | quote }}
  - name: AIRFLOW_OIDC_SCOPE
    value: {{ include "okdp-airflow.scope" . | replace " " "+" | quote }}
{{- end }}
  - name: AWS_ENDPOINT_URL_S3
    value: {{ $s3.internalUrl | default $s3.apiUrl | quote }}
  - name: AWS_REGION
    value: {{ $s3.region | quote }}
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: {{ .Values.s3SecretRef | quote }}
        key: accessKey
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: {{ .Values.s3SecretRef | quote }}
        key: secretKey
  - name: INSECURE_VERIFY_TLS
    value: {{ if $oidc.insecureSkipVerify }}"false"{{ else }}"true"{{ end }}
  - name: REQUESTS_CA_BUNDLE
    value: "/cacerts/ca.crt"
  - name: SSL_CERT_FILE
    value: "/cacerts/ca.crt"
  - name: CURL_CA_BUNDLE
    value: "/cacerts/ca.crt"
# The CA bundle the variables above point at, mounted in every Airflow
# container: a component without it fails any HTTPS call, and the CLI
# itself talks to the API server over HTTPS.
volumes:
  - name: cacerts
    secret:
      secretName: certs-bundle
volumeMounts:
  - name: cacerts
    mountPath: /cacerts
apiServer:
  resources:
    requests:
      memory: 384Mi
      cpu: 200m
    limits:
      memory: {{ printf "%vGi" .Values.webserverMemoryGi | quote }}
      cpu: 1000m
  startupProbe:
    failureThreshold: 24
    timeoutSeconds: 30
  {{- if $oidc.enabled }}
  apiServerConfig: |
    import os

    from flask_appbuilder.security.manager import AUTH_OAUTH

    verify_tls = os.environ.get("INSECURE_VERIFY_TLS", "true").lower() == "true"
    oauth_verify = os.environ.get("REQUESTS_CA_BUNDLE") if verify_tls else False

    AUTH_TYPE = AUTH_OAUTH
    AUTH_USER_REGISTRATION = True
    AUTH_USER_REGISTRATION_ROLE = "Viewer"
    # Sync Airflow roles from OIDC groups at every login
    AUTH_ROLES_SYNC_AT_LOGIN = True
    # Map OIDC groups to Airflow roles
    AUTH_ROLES_MAPPING = {
    {{- range $oidcRole, $airflowRoles := .Values.oidcRoleMapping | default dict }}
        {{ $oidcRole | quote }}: {{ $airflowRoles | toJson }},
    {{- end }}
    }

    OAUTH_PROVIDERS = [
        {
            "name": "oidc",
            "icon": "fa-circle-o",
            "token_key": "access_token",
            "remote_app": {
                "client_id": os.environ["AIRFLOW_OIDC_CLIENT_ID"],
                "client_secret": os.environ["AIRFLOW_OIDC_CLIENT_SECRET"],
                "api_base_url": os.environ["AIRFLOW_OIDC_API_BASE_URL"],
                "access_token_url": os.environ["AIRFLOW_OIDC_ACCESS_TOKEN_URL"],
                "authorize_url": os.environ["AIRFLOW_OIDC_AUTHORIZE_URL"],
                "server_metadata_url": os.environ["AIRFLOW_OIDC_SERVER_METADATA_URL"],
                "client_kwargs": {
                    "scope": os.environ.get("AIRFLOW_OIDC_SCOPE", "openid profile email").replace("+", " "),
                    "verify": oauth_verify,
                },
            },
        },
    ]
  {{- end }}
scheduler:
  resources:
    requests:
      memory: 384Mi
      cpu: 200m
    limits:
      memory: {{ printf "%vGi" .Values.schedulerMemoryGi | quote }}
      cpu: 1000m
  startupProbe:
    failureThreshold: 12
    timeoutSeconds: 60
triggerer:
  enabled: true
  # The default 20s probe times out on small nodes and kills a healthy triggerer.
  livenessProbe:
    timeoutSeconds: 60
  resources:
    requests:
      memory: 128Mi
      cpu: 50m
    limits:
      memory: 512Mi
      cpu: 300m
ingress:
  apiServer:
    enabled: true
    ingressClassName: {{ .Values.global.okdp.ingress.className }}
    annotations:
      kubernetes.io/ingress.class: {{ .Values.global.okdp.ingress.className }}
      {{- include "okdp.ingressAnnotations" . | nindent 6 }}
      nginx.ingress.kubernetes.io/proxy-body-size: "0"
    hosts:
      - name: {{ $host }}
        tls:
          enabled: true
          secretName: {{ include "okdp.fullname" (dict "ctx" . "suffix" "airflow-tls") }}
# The pre-provisioned Secret holding the full SQLAlchemy connection string:
# the chart does not generate its own airflow-metadata secret, so credentials
# never appear in the values.
data:
  metadataSecretName: {{ .Values.metadataSecret }}
dags:
  mountPath: /opt/airflow/dags
  persistence:
    enabled: false
  gitSync:
    {{- toYaml $gitSyncValues | nindent 4 }}
dagProcessor:
  enabled: true
  resources:
    requests:
      memory: 256Mi
      cpu: 200m
    limits:
      memory: {{ printf "%vGi" .Values.dagProcessorMemoryGi | quote }}
      cpu: {{ .Values.dagProcessorCpuCores | quote }}
flower:
  enabled: false
pgbouncer:
  enabled: false
statsd:
  enabled: false
# Off: its password secret template calls randAlphaNum (okdp-guard-allow.yaml).
redis:
  enabled: false
workers:
  replicas: 0
postgresql:
  enabled: false
webserver:
  enabled: false
createUserJob:
  enabled: false
  useHelmHooks: false
migrateDatabaseJob:
  enabled: true
  # Not a Helm hook: under Flux (--wait) and Argo (PostSync after healthy) a
  # post-install hook would wait for pods that wait for the migrations.
  useHelmHooks: false
  # A plain Job with ttlSecondsAfterFinished disappears after it succeeds:
  # Argo would see the release out of sync and recreate it forever. Argo runs
  # it as a Sync hook instead (recreated on every sync, migrations are
  # idempotent); Helm and Flux ignore these annotations.
  jobAnnotations:
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
  resources:
    requests:
      memory: 64Mi
      cpu: 25m
    limits:
      memory: 256Mi
      cpu: 200m
config:
  core:
    load_examples: 'False'
    auth_manager: "airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager"
  fab:
    enable_proxy_fix: "True"
    cookie_secure: "True"
    cookie_samesite: "Lax"
# Generated once by ESO (templates/internal-secret.yaml): the chart's own
# templates would mint them with randAlphaNum on every render.
fernetKeySecretName: {{ include "okdp-airflow.internalSecret" . }}
apiSecretKeySecretName: {{ include "okdp-airflow.internalSecret" . }}
jwtSecretName: {{ include "okdp-airflow.internalSecret" . }}
{{- end -}}

{{/* Module oidc-dcr: registers the OAuth client (clientProvisioning: dcr). */}}
{{- define "okdp-airflow.values.dcr" -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- if ne ($oidc.dcr.authMethod | default "") "anonymous" -}}
  {{- fail (printf "airflow: global.okdp.oidc.dcr.authMethod %q is not supported: this chart registers anonymously" ($oidc.dcr.authMethod | default "")) -}}
{{- end -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "oidc.dcr.registrationUrl")) -}}
ttl_seconds: 30
registration_url: {{ $oidc.dcr.registrationUrl | quote }}
request:
  application_type: web
  client_name: {{ printf "%s-%s" .Release.Name .Release.Namespace | quote }}
  redirect_uris:
    - {{ printf "https://%s/auth/oauth-authorized/oidc" (include "okdp-airflow.host" .) | quote }}
  grant_types:
    - authorization_code
    - refresh_token
    - client_credentials
  # openid is rejected by Keycloak here; offline_access must match the login scope.
  scope: {{ without (splitList " " (include "okdp-airflow.scope" .)) "openid" | join " " | quote }}
tls:
  insecure: false
  certificate: certs-bundle
secret: {{ include "okdp-airflow.dcrSecret" . }}
mapping:
  use_default: false
  key_mapping:
    client_id: ".client_id"
    client_secret: ".client_secret"
{{- end -}}

{{/*
Instance-level upstream values (okdp.vendor.render option `upstream`): an
instance sets any value of the vendored chart under upstream.airflow in its
values.yaml, over the values computed above, except the protected paths.
Protected: what the platform relies on. Names (okdp-airflow.argoOrder finds
the migration Job by name, the descriptor and internal Secret derive from the
release). OIDC sign-in (extraEnv carries the client Secret and S3 credentials
as a templated string, which cannot be appended to: an instance adds variables
with env, secret or extraEnvFrom instead), the ingress host registered with
the identity provider, the metadata database and generated secrets (data,
the *SecretName keys, never a literal key in the values). The switches
okdp-guard-allow.yaml relies on (airflowVersion, redis.enabled, executor:
the Celery executors need the Redis whose password is random), postgresql
(dropped from vendor/), the migration Job run as an Argo Sync hook, and the
create-user Job (a local admin with a password in the values). Appended:
the CA bundle volume and mount, and the proxy variables of git-sync.
*/}}
{{- define "okdp-airflow.upstream.airflow" -}}
protect:
  - fullnameOverride
  - nameOverride
  - useStandardNaming
  - airflowVersion
  - executor
  - extraEnv
  - apiServer.apiServerConfig
  - apiServer.apiServerConfigConfigMapName
  - config.core.auth_manager
  - ingress.enabled
  - ingress.apiServer.enabled
  - ingress.apiServer.ingressClassName
  - ingress.apiServer.host
  - ingress.apiServer.hosts
  - ingress.apiServer.tls
  - data
  - fernetKey
  - fernetKeySecretName
  - apiSecretKey
  - apiSecretKeySecretName
  - jwtSecret
  - jwtSecretName
  - webserverSecretKey
  - webserverSecretKeySecretName
  - redis.enabled
  - postgresql.enabled
  - migrateDatabaseJob.enabled
  - migrateDatabaseJob.useHelmHooks
  - migrateDatabaseJob.jobAnnotations
  - createUserJob.enabled
append:
  - volumes
  - volumeMounts
  - dags.gitSync.env
{{- end -}}
