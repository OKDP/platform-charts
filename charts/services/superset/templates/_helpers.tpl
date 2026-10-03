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

{{/* Generated secret of the local admin (key password), only without OIDC: <release>-admin. */}}
{{- define "okdp-superset-wrapper.adminSecret" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "admin") -}}
{{- end -}}

{{/* The Valkey cache and Celery broker (templates/valkey.yaml), named redis as the env it is read from. */}}
{{- define "okdp-superset-wrapper.redis" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "redis") -}}
{{- end -}}

{{- define "okdp-superset-wrapper.trinoOauthSecret" -}}
{{- printf "creds-%s-oauth2-trino" .Release.Name -}}
{{- end -}}

{{/* An env Secret of templates/env-secrets.yaml: <release>-<suffix>. Takes {ctx, suffix}. */}}
{{- define "okdp-superset-wrapper.envSecret" -}}
{{- include "okdp.fullname" (dict "ctx" .ctx "suffix" .suffix) -}}
{{- end -}}
