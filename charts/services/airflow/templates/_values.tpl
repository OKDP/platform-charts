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
{{- $oauthSecret := include "okdp.oidc.clientSecret" . -}}
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
apiServer:
  resources:
    limits:
      memory: {{ printf "%vGi" .Values.webserverMemoryGi | quote }}
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
    limits:
      memory: {{ printf "%vGi" .Values.schedulerMemoryGi | quote }}
ingress:
  apiServer:
    ingressClassName: {{ .Values.global.okdp.ingress.className }}
    annotations:
      kubernetes.io/ingress.class: {{ .Values.global.okdp.ingress.className }}
      {{- include "okdp.ingressAnnotations" . | nindent 6 }}
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
  gitSync:
    {{- toYaml $gitSyncValues | nindent 4 }}
dagProcessor:
  resources:
    limits:
      memory: {{ printf "%vGi" .Values.dagProcessorMemoryGi | quote }}
      cpu: {{ .Values.dagProcessorCpuCores | quote }}
# Generated once by ESO (templates/internal-secret.yaml): the chart's own
# templates would mint them with randAlphaNum on every render.
fernetKeySecretName: {{ include "okdp-airflow.internalSecret" . }}
apiSecretKeySecretName: {{ include "okdp-airflow.internalSecret" . }}
jwtSecretName: {{ include "okdp-airflow.internalSecret" . }}
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
