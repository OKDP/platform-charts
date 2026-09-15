{{/*
Wrapper helpers. Prefixed okdp-polaris. so they never collide with the
partials of the vendored charts (polaris.*, polaris-admin.*, polaris-console.*).
*/}}

{{/* Polaris server Service: <release>-polaris (iceberg-catalog contract convention). */}}
{{- define "okdp-polaris.fullname" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "polaris") -}}
{{- end -}}

{{/* Public API host: polaris-<namespace>.<ingress suffix>. */}}
{{- define "okdp-polaris.host" -}}
{{- include "okdp.ingressHost" (dict "ctx" . "name" "polaris") -}}
{{- end -}}

{{/* Console host: polaris-console-<namespace>.<ingress suffix>. */}}
{{- define "okdp-polaris.consoleHost" -}}
{{- include "okdp.ingressHost" (dict "ctx" . "name" "polaris-console") -}}
{{- end -}}

{{/* In-cluster base URL of the Polaris API. */}}
{{- define "okdp-polaris.internalUrl" -}}
{{- printf "http://%s.%s.svc:8181" (include "okdp-polaris.fullname" .) .Release.Namespace -}}
{{- end -}}

{{/* Root credentials of the realm (keys client_id, client_secret): <release>-root. */}}
{{- define "okdp-polaris.rootSecret" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "root") -}}
{{- end -}}

{{/* Secret of the OAuth client (existing mode): creds-<release>-oauth2, the platform convention. */}}
{{- define "okdp-polaris.oauthSecret" -}}
{{- printf "creds-%s-oauth2" .Release.Name -}}
{{- end -}}

{{/*
dcr mode: the Secrets the oidc-dcr jobs write the registered clients to, same
keys as creds-<release>-oauth2: the server's (confidential, client_credentials)
and the console's (public, authorization code with PKCE; client_id only).
*/}}
{{- define "okdp-polaris.dcrSecret" -}}
{{- printf "%s-%s-dcr" .Release.Name .Release.Namespace -}}
{{- end -}}
{{- define "okdp-polaris.consoleDcrSecret" -}}
{{- printf "%s-%s-console-dcr" .Release.Name .Release.Namespace -}}
{{- end -}}

{{/* Login scope of the console (the oidc-dcr registration must grant it, openid aside). */}}
{{- define "okdp-polaris.consoleScope" -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- printf "%s roles offline_access" $oidc.scope -}}
{{- end -}}

{{/*
okdp-polaris.consoleClientIdFrom: the rendered polaris-console stream with the
VITE_OIDC_CLIENT_ID env of its Deployment read from Secret .secret (key
client_id) instead of a value: the chart's extraEnv takes values only. Only the
Deployment is re-serialised. Fails when the env is not found (the vendored
chart changed). Takes {rendered, secret}.
*/}}
{{- define "okdp-polaris.consoleClientIdFrom" -}}
{{- $count := 0 -}}
{{- $out := "" -}}
{{- range $doc := regexSplit "(?m)^---[ \\t]*$" .rendered -1 -}}
  {{- $obj := fromYaml $doc -}}
  {{- $changed := false -}}
  {{- if and $obj (not (hasKey $obj "Error")) (eq (toString $obj.kind) "Deployment") -}}
    {{- range $c := $obj.spec.template.spec.containers | default list -}}
      {{- range $e := $c.env | default list -}}
        {{- if eq (toString $e.name) "VITE_OIDC_CLIENT_ID" -}}
          {{- $_ := unset $e "value" -}}
          {{- $_ := set $e "valueFrom" (dict "secretKeyRef" (dict "name" $.secret "key" "client_id")) -}}
          {{- $changed = true -}}
          {{- $count = add1 $count -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- if $changed -}}
    {{- $out = print $out "\n---\n" (regexFind "# Source: [^\\n]*" $doc) "\n" (toYaml $obj) -}}
  {{- else if trim $doc -}}
    {{- $out = print $out "\n---" $doc -}}
  {{- end -}}
{{- end -}}
{{- if eq $count 0 -}}
  {{- fail "polaris: no VITE_OIDC_CLIENT_ID env in the rendered polaris-console Deployment (did the vendored chart change?)" -}}
{{- end -}}
{{- $out -}}
{{- end -}}

{{/* The db connection, resolved and checked (PostgreSQL only: the JDBC URL and the image driver). */}}
{{- define "okdp-polaris.db" -}}
{{- $db := include "okdp.connection" (dict "ctx" . "ref" .Values.db "contract" "database-server" "field" "db") | fromYaml -}}
{{- if ne (toString $db.engine) "postgresql" -}}
  {{- fail (printf "polaris: db: connection %q has engine %q, Polaris is deployed with PostgreSQL only" .Values.db (toString $db.engine)) -}}
{{- end -}}
{{- if not $db.secretRef -}}
  {{- fail (printf "polaris: db: connection %q has no secretRef: Polaris needs a Secret with the keys username and password" .Values.db) -}}
{{- end -}}
{{- toYaml $db -}}
{{- end -}}

{{/* realms value of the polaris-admin chart, shared by the bootstrap and principals phases. */}}
{{- define "okdp-polaris.adminRealms" -}}
- name: {{ .Values.realm | quote }}
  rootPrincipal:
    name: root
    credentialsSecret:
      name: {{ include "okdp-polaris.rootSecret" . | quote }}
      clientIdKey: client_id
      clientSecretKey: client_secret
  principals:
    {{- toYaml (.Values.principals | default list) | nindent 4 }}
{{- end -}}
