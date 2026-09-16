{{/*
Wrapper helpers. Prefixed okdp-superset-wrapper. so they never collide with
the partials of the vendored charts (superset.*, okdp.superset.*).
*/}}

{{/* Name prefix of every Superset object: the release name. */}}
{{- define "okdp-superset-wrapper.fullname" -}}
{{- include "okdp.fullname" . -}}
{{- end -}}

{{/* Generated secret: superset_secret_key and redis-password (the Valkey password). */}}
{{- define "okdp-superset-wrapper.internalSecret" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "internal") -}}
{{- end -}}

{{/* The Valkey cache and Celery broker (templates/valkey.yaml), named redis as the env it is read from. */}}
{{- define "okdp-superset-wrapper.redis" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "redis") -}}
{{- end -}}

{{/* OAuth clients of the existing mode: creds-<release>-oauth2 (sign-in) and creds-<release>-oauth2-trino (Trino datasources). */}}
{{- define "okdp-superset-wrapper.oauthSecret" -}}
{{- printf "creds-%s-oauth2" .Release.Name -}}
{{- end -}}
{{- define "okdp-superset-wrapper.trinoOauthSecret" -}}
{{- printf "creds-%s-oauth2-trino" .Release.Name -}}
{{- end -}}

{{/*
Secret the oidc-dcr job writes the registered client to (dcr mode), same keys:
one client for the sign-in and the Trino datasources (both redirect URIs).
*/}}
{{- define "okdp-superset-wrapper.dcrSecret" -}}
{{- printf "%s-%s-dcr" .Release.Name .Release.Namespace -}}
{{- end -}}

{{/* An env Secret of templates/env-secrets.yaml: <release>-<suffix>. Takes {ctx, suffix}. */}}
{{- define "okdp-superset-wrapper.envSecret" -}}
{{- include "okdp.fullname" (dict "ctx" .ctx "suffix" .suffix) -}}
{{- end -}}
