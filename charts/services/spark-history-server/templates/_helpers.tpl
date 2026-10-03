{{/*
Wrapper helpers. Prefixed okdp-shs. so they never collide with the partials of
the vendored charts (spark-history-server.*, spark-web-proxy.*).
*/}}

{{/* History server Service and Deployment: <release>-spark-history-server. */}}
{{- define "okdp-shs.historyName" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "spark-history-server") -}}
{{- end -}}

{{/* Web proxy (the UI entry point): <release>-spark-web-proxy. */}}
{{- define "okdp-shs.proxyName" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "spark-web-proxy") -}}
{{- end -}}

{{/* Public host: spark-web-proxy-<namespace>.<ingress suffix> (the KuboCD-era host). */}}
{{- define "okdp-shs.host" -}}
{{- include "okdp.ingressHost" (dict "ctx" . "name" "spark-web-proxy") -}}
{{- end -}}

{{/* Login scope, offline_access included (the oidc-dcr registration must grant it). */}}
{{- define "okdp-shs.scope" -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- printf "%s offline_access" $oidc.scope -}}
{{- end -}}

{{/* The OIDC filter's redirect URI: the web proxy's /home. */}}
{{- define "okdp-shs.redirectUri" -}}
{{- printf "%s/home" (include "okdp.url" (dict "ctx" . "name" "spark-web-proxy")) -}}
{{- end -}}

{{/*
Secret of the OIDC filter's cookie encryption key (key cookie-cipher-secret-key):
<release>-auth-cookie, generated once by ESO (cookie-secret.yaml).
*/}}
{{- define "okdp-shs.cookieSecret" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "auth-cookie") -}}
{{- end -}}
