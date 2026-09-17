{{/* Console host: host, else okdp-ui.<ingress suffix>. */}}
{{- define "okdp-cp-ui.host" -}}
{{- if .Values.host -}}
{{- .Values.host -}}
{{- else -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "ingress.suffix")) -}}
{{- printf "okdp-ui.%s" .Values.global.okdp.ingress.suffix -}}
{{- end -}}
{{- end -}}

{{/*
Service of the control-plane server: backendService, else this release name
with okdp-control-plane-ui replaced by okdp-control-plane-server (the server
chart names its Service after its release), else okdp-control-plane-server.
*/}}
{{- define "okdp-cp-ui.backendService" -}}
{{- if .Values.backendService -}}
{{- .Values.backendService -}}
{{- else if hasSuffix "okdp-control-plane-ui" .Release.Name -}}
{{- printf "%sokdp-control-plane-server" (trimSuffix "okdp-control-plane-ui" .Release.Name) -}}
{{- else -}}
okdp-control-plane-server
{{- end -}}
{{- end -}}

{{/* OIDC issuer and client of the console, defaulting to the platform ones. */}}
{{- define "okdp-cp-ui.oidcAuthority" -}}
{{- $v := .Values.oidcAuthority | default (dig "oidc" "issuerUri" "" (.Values.global.okdp | default dict)) -}}
{{- required "okdp-control-plane-ui: oidcAuthority is required (or global.okdp.oidc.issuerUri in platform/platform-values.yaml): the console has no issuer to authenticate against without it" $v -}}
{{- end -}}
{{- define "okdp-cp-ui.oidcClientId" -}}
{{- .Values.oidcClientId | default (dig "oidc" "clientId" "" (.Values.global.okdp | default dict)) | default "okdp-ui" -}}
{{- end -}}
