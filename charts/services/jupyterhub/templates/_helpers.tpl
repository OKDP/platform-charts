{{/*
Wrapper helpers. Prefixed okdp-jupyterhub. so they never collide with the
partials of the vendored charts (jupyterhub.*, spark-rbac.*).
*/}}

{{/* Public URL: https://jupyterhub-<namespace>.<ingress suffix>. */}}
{{- define "okdp-jupyterhub.url" -}}
{{- include "okdp.url" . -}}
{{- end -}}

{{/*
Secret with the OAuth client (client_id, client_secret, JUPYTERHUB_CRYPT_KEY):
the creds-<release>-oauth2 convention of the existing mode, the client being
created in Keycloak beforehand.
*/}}
{{- define "okdp-jupyterhub.oauthSecret" -}}
{{- printf "creds-%s-oauth2" .Release.Name -}}
{{- end -}}

{{/*
Secret the oidc-dcr job writes the registered client to (dcr mode), keys
client_id and client_secret; JUPYTERHUB_CRYPT_KEY then comes from the
generated hub passwords (hub.config.CryptKeeper.keys).
*/}}
{{- define "okdp-jupyterhub.dcrSecret" -}}
{{- printf "%s-%s-dcr" .Release.Name .Release.Namespace -}}
{{- end -}}

{{/* Scopes the hub requests at login (the oidc-dcr registration must grant them, openid aside). */}}
{{- define "okdp-jupyterhub.scope" -}}
openid profile email groups
{{- end -}}

{{/* The hub Secret of the jupyterhub chart: <fullname>-hub, fullname being the release name. */}}
{{- define "okdp-jupyterhub.hubSecret" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "hub") -}}
{{- end -}}

{{/* The ESO-generated hub passwords (templates/hub-generated.yaml). */}}
{{- define "okdp-jupyterhub.hubGeneratedSecret" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "hub-generated") -}}
{{- end -}}

{{/*
Values the jupyterhub chart would generate with lookup + randAlphaNum. The
chart is handed this placeholder so that it renders nothing random; the real
values are in the ESO-generated Secret, which the hub reads first
(hub.existingSecret) and the proxy token references are re-pointed to
(templates/jupyterhub.yaml). The hub pops these keys from hub.config.
*/}}
{{- define "okdp-jupyterhub.generatedPlaceholder" -}}
generated-by-external-secrets
{{- end -}}

{{/*
okdp-jupyterhub.placeholders: replaces the placeholders a free-text parameter
(welcomeNotebook, sparkDefaults) may carry, in their Helm and KuboCD forms.
Takes a dict {ctx, text}.
*/}}
{{- define "okdp-jupyterhub.placeholders" -}}
{{- $ctx := .ctx -}}
{{- $suffix := toString $ctx.Values.global.okdp.ingress.suffix -}}
{{- .text
    | replace "{{ .Values.global.okdp.ingress.suffix }}" $suffix
    | replace "{{ .Context.ingress.suffix }}" $suffix
    | replace "{{ .Release.Name }}" $ctx.Release.Name
    | replace "{{ .Release.metadata.name }}" $ctx.Release.Name
    | replace "{{ .Release.Namespace }}" $ctx.Release.Namespace
    | replace "{{ .Release.namespace }}" $ctx.Release.Namespace -}}
{{- end -}}
