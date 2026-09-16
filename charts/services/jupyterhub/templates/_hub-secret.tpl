{{/*
okdp-jupyterhub.hubSecret.external: the hub Secret of the jupyterhub chart,
made by ESO. Takes {ctx, rendered}: the rendered chart, whose own hub Secret
provides the non-secret keys (values.yaml, the extraFiles) as they are. The
three generated keys come from ESO Password generators, once
(refreshInterval "0"):

  hub.config.ConfigurableHTTPProxy.auth_token  proxy API token (64 characters)
  hub.config.JupyterHub.cookie_secret          64 hex characters (32 bytes)
  hub.config.CryptKeeper.keys                  64 hex characters (32 bytes)

Static keys go through the ESO template engine: they are written as Go
string literals ({{ "..." }}) so that any "{{" they carry stays literal.
Generator names use short suffixes: okdp.generatedSecret derives them from
the key, and three long keys truncated to 63 characters would collide.
*/}}
{{- define "okdp-jupyterhub.hubSecret.external" -}}
{{- $ctx := .ctx -}}
{{- $name := include "okdp-jupyterhub.hubSecret" $ctx -}}
{{- $upstream := include "okdp.vendor.object" (dict "rendered" .rendered "kind" "Secret" "name" $name) | fromYaml -}}
{{- if not $upstream -}}
  {{- fail (printf "jupyterhub: the vendored chart rendered no Secret %s to replace: check vendor/jupyterhub after an upgrade" $name) -}}
{{- end -}}
{{- $generated := dict
      "hub.config.ConfigurableHTTPProxy.auth_token" (dict "suffix" "hub-proxy" "transform" "")
      "hub.config.JupyterHub.cookie_secret" (dict "suffix" "hub-cookie" "transform" "sha256")
      "hub.config.CryptKeeper.keys" (dict "suffix" "hub-crypt" "transform" "sha256") -}}
{{- $data := dict -}}
{{- range $k, $v := $upstream.data | default dict -}}
  {{- if not (hasKey $generated $k) -}}
    {{- $_ := set $data $k (printf "{{ %s }}" (b64dec $v | toJson)) -}}
  {{- end -}}
{{- end -}}
{{- range $k, $v := $upstream.stringData | default dict -}}
  {{- $_ := set $data $k (printf "{{ %s }}" (toString $v | toJson)) -}}
{{- end -}}
{{- $dataFrom := list -}}
{{- range $k := keys $generated | sortAlpha -}}
  {{- $g := index $generated $k -}}
  {{- $gen := include "okdp.fullname" (dict "ctx" $ctx "suffix" $g.suffix) -}}
  {{- $alias := printf "okdp_%s" (replace "-" "_" $g.suffix) -}}
  {{- if $g.transform -}}
    {{- $_ := set $data $k (printf "{{ index . %q | sha256sum }}" $alias) -}}
  {{- else -}}
    {{- $_ := set $data $k (printf "{{ index . %q }}" $alias) -}}
  {{- end -}}
  {{- $dataFrom = append $dataFrom (dict "sourceRef" (dict "generatorRef" (dict "apiVersion" "generators.external-secrets.io/v1alpha1" "kind" "Password" "name" $gen)) "rewrite" (list (dict "regexp" (dict "source" "^password$" "target" $alias)))) }}
---
apiVersion: generators.external-secrets.io/v1alpha1
kind: Password
metadata:
  name: {{ $gen }}
  namespace: {{ $ctx.Release.Namespace }}
  labels:
    {{- include "okdp.labels" $ctx | nindent 4 }}
spec:
  length: 64
  digits: 10
  symbols: 0
  noUpper: false
  allowRepeat: true
{{- end }}
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ $name }}
  namespace: {{ $ctx.Release.Namespace }}
  labels:
    {{- include "okdp.labels" $ctx | nindent 4 }}
spec:
  refreshInterval: "0"
  target:
    name: {{ $name }}
    creationPolicy: Owner
    template:
      engineVersion: v2
      type: Opaque
      metadata:
        labels:
          {{- toYaml $upstream.metadata.labels | nindent 10 }}
      data:
        {{- toYaml $data | nindent 8 }}
  dataFrom:
    {{- toYaml $dataFrom | nindent 4 }}
{{- end -}}
