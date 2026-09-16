{{/*
Wrapper helpers. Prefixed okdp-airflow. so they never collide with the
partials of the vendored charts (airflow.*, oidc-dcr.*).
*/}}

{{/* Public host: airflow-<namespace>.<ingress suffix>. */}}
{{- define "okdp-airflow.host" -}}
{{- include "okdp.ingressHost" (dict "ctx" . "name" "airflow") -}}
{{- end -}}

{{/* Generated internal secrets (api-secret-key, jwt-secret, fernet-key): <release>-internal. */}}
{{- define "okdp-airflow.internalSecret" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "internal") -}}
{{- end -}}

{{/* Secret of the OAuth client (existing mode): creds-<release>-oauth2, the platform convention. */}}
{{- define "okdp-airflow.oauthSecret" -}}
{{- printf "creds-%s-oauth2" .Release.Name -}}
{{- end -}}

{{/* Secret the oidc-dcr job writes the registered client to (dcr mode), same keys. */}}
{{- define "okdp-airflow.dcrSecret" -}}
{{- printf "%s-%s-dcr" .Release.Name .Release.Namespace -}}
{{- end -}}

{{/* Login scope, offline_access included (the oidc-dcr registration must grant it). */}}
{{- define "okdp-airflow.scope" -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- printf "%s offline_access" $oidc.scope -}}
{{- end -}}

{{/*
Orders the rendered airflow chart for Argo around the migration Job (a Sync
hook), with nothing the upstream chart offers a value for:
- the Job gets activeDeadlineSeconds: 600 and backoffLimit: 6 (the Kubernetes
  default, made explicit): a run that cannot start (a Secret it reads is
  missing) or keeps failing ends Failed instead of running forever;
- the Deployments and StatefulSets get argocd.argoproj.io/sync-wave: "1".
  Their pods wait for the migrations, and Argo waits for every resource of a
  wave to be healthy before it looks at a failed hook: in the Job's wave they
  kept the operation waiting forever. After it, a failed Job fails the
  operation and the Argo retry recreates it (BeforeHookCreation).
Its internal Secret is applied one wave before the Job (internal-secret.yaml).
Helm and Flux ignore the annotations; 600 s is well above a first migration
and above the Flux default release timeout (5 min), so Flux, which waits for
the Job, sees no change. Only the changed documents are re-serialised.
*/}}
{{- define "okdp-airflow.argoOrder" -}}
{{- $name := printf "%s-run-airflow-migrations" .ctx.Release.Name -}}
{{- $out := .rendered -}}
{{- $count := 0 -}}
{{- range $doc := regexSplit "(?m)^---[ \\t]*$" .rendered -1 -}}
  {{- $obj := fromYaml $doc -}}
  {{- if and $obj (not (hasKey $obj "Error")) (kindIs "map" $obj.metadata) -}}
    {{- $kind := toString $obj.kind -}}
    {{- $changed := false -}}
    {{- if and (eq $kind "Job") (eq (toString $obj.metadata.name) $name) -}}
      {{- $_ := set $obj.spec "activeDeadlineSeconds" 600 -}}
      {{- $_ := set $obj.spec "backoffLimit" 6 -}}
      {{- $count = add1 $count -}}
      {{- $changed = true -}}
    {{- else if has $kind (list "Deployment" "StatefulSet") -}}
      {{- $annotations := $obj.metadata.annotations | default dict -}}
      {{- $_ := set $annotations "argocd.argoproj.io/sync-wave" "1" -}}
      {{- $_ := set $obj.metadata "annotations" $annotations -}}
      {{- $changed = true -}}
    {{- end -}}
    {{- if $changed -}}
      {{- $out = replace $doc (print "\n" (regexFind "# Source: [^\\n]*" $doc) "\n" (toYaml $obj) "\n") $out -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if ne $count 1 -}}
  {{- fail (printf "airflow: no Job %s in the rendered chart (did the vendored chart change?)" $name) -}}
{{- end -}}
{{- $out -}}
{{- end -}}
