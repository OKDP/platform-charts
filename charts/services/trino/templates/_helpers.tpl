{{/*
Wrapper helpers. Prefixed okdp-trino. so they never collide with the partials
of the vendored trino chart (trino.*).
*/}}

{{/* Name of the Trino coordinator Service: <release>-trino (trino contract convention). */}}
{{- define "okdp-trino.fullname" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "trino") -}}
{{- end -}}

{{/* Public host: trino-<namespace>.<ingress suffix>. */}}
{{- define "okdp-trino.host" -}}
{{- include "okdp.ingressHost" (dict "ctx" . "name" "trino") -}}
{{- end -}}

{{/* Secret of the OAuth client Trino signs users in with, when the platform does not register it (existing mode). */}}
{{- define "okdp-trino.oauthSecret" -}}
{{- printf "creds-%s-oauth2" .Release.Name -}}
{{- end -}}

{{/* OPA server of this instance. */}}
{{- define "okdp-trino.opaName" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "opa") -}}
{{- end -}}

{{/* Generated secret holding the internal-communication shared secret. */}}
{{- define "okdp-trino.internalSecret" -}}
{{- include "okdp.fullname" (dict "ctx" . "suffix" "internal") -}}
{{- end -}}

{{/* Secrets of the OPAL tokens and keys (opal-secrets hook). */}}
{{- define "okdp-trino.opalSecrets" -}}
ssh: {{ include "okdp.fullname" (dict "ctx" . "suffix" "opal-ssh") }}
master: {{ include "okdp.fullname" (dict "ctx" . "suffix" "opal-master-token") }}
client: {{ include "okdp.fullname" (dict "ctx" . "suffix" "opal-client-token") }}
{{- end -}}

{{/*
kubectl of the opal-secrets hook: the Kubernetes project image (distroless:
kubectl and kube-log-runner, no shell), pinned by digest.
*/}}
{{- define "okdp-trino.kubectlImage" -}}
registry.k8s.io/kubectl:v1.36.5@sha256:0667e3f3e6ef435d7cd4c16684244703ebd67314c17511c2a9f87ea44f6cdf6b
{{- end -}}

{{/*
okdp-trino.catalogs: hiveCatalogs and icebergCatalogs resolved, as a YAML list
of {name, envPrefix, properties, s3Secret, oidcSecret (iceberg only)}.
Connections are resolved with okdp.connection; credentials stay in Secrets
and reach the catalog files through ${ENV:...}.
*/}}
{{- define "okdp-trino.catalogs" -}}
{{- $defaultS3Secret := .Values.s3SecretRef | default "" -}}
{{- $seen := dict "tpch" "the built-in tpch catalog" "tpcds" "the built-in tpcds catalog" -}}
{{- $out := list -}}
{{- range $i, $c := .Values.hiveCatalogs | default list -}}
  {{- $where := printf "hiveCatalogs[%d]" $i -}}
  {{- if not $c.name }}{{ fail (printf "trino: %s: name is required" $where) }}{{ end -}}
  {{- if hasKey $seen $c.name }}{{ fail (printf "trino: %s: catalog name %q is already used by %s" $where $c.name (index $seen $c.name)) }}{{ end -}}
  {{- $_ := set $seen $c.name $where -}}
  {{- $hive := include "okdp.connection" (dict "ctx" $ "ref" $c.metastore "contract" "hive" "field" (printf "%s.metastore" $where)) | fromYaml -}}
  {{- $s3 := include "okdp.connection" (dict "ctx" $ "ref" $c.storage "contract" "s3" "field" (printf "%s.storage" $where)) | fromYaml -}}
  {{- $s3Secret := $c.s3SecretRef | default $defaultS3Secret | default (($s3.secretRef | default dict).name) -}}
  {{- if not $s3Secret }}{{ fail (printf "trino: catalog %q: no S3 credentials, set s3SecretRef on the catalog or on the release, or a secretRef on connection %q" $c.name $c.storage) }}{{ end -}}
  {{- $env := upper (replace "-" "_" $c.name) -}}
  {{- $props := list
      "connector.name=hive"
      (printf "hive.metastore.uri=%s" $hive.thriftUri)
      "fs.native-s3.enabled=true"
      (printf "s3.endpoint=%s" $s3.apiUrl)
      (printf "s3.path-style-access=%v" $s3.pathStyle)
      (printf "s3.region=%s" $s3.region)
      (printf "s3.aws-access-key=${ENV:S3_ACCESS_KEY_%s}" $env)
      (printf "s3.aws-secret-key=${ENV:S3_SECRET_ACCESS_%s}" $env) -}}
  {{- $out = append $out (dict "name" $c.name "envPrefix" $env "properties" (join "\n" $props) "s3Secret" $s3Secret) -}}
{{- end -}}
{{- range $i, $c := .Values.icebergCatalogs | default list -}}
  {{- $where := printf "icebergCatalogs[%d]" $i -}}
  {{- if not $c.name }}{{ fail (printf "trino: %s: name is required" $where) }}{{ end -}}
  {{- if hasKey $seen $c.name }}{{ fail (printf "trino: %s: catalog name %q is already used by %s" $where $c.name (index $seen $c.name)) }}{{ end -}}
  {{- $_ := set $seen $c.name $where -}}
  {{- $cat := include "okdp.connection" (dict "ctx" $ "ref" $c.catalog "contract" "iceberg-catalog" "field" (printf "%s.catalog" $where)) | fromYaml -}}
  {{- $s3 := include "okdp.connection" (dict "ctx" $ "ref" $c.storage "contract" "s3" "field" (printf "%s.storage" $where)) | fromYaml -}}
  {{- $s3Secret := $c.s3SecretRef | default $defaultS3Secret | default (($s3.secretRef | default dict).name) -}}
  {{- if not $s3Secret }}{{ fail (printf "trino: catalog %q: no S3 credentials, set s3SecretRef on the catalog or on the release, or a secretRef on connection %q" $c.name $c.storage) }}{{ end -}}
  {{- $warehouse := $c.warehouse | default $cat.realm -}}
  {{- if not $warehouse }}{{ fail (printf "trino: catalog %q: no warehouse, and connection %q publishes no realm: set warehouse" $c.name $c.catalog) }}{{ end -}}
  {{- $uri := $cat.internalUri | default $cat.uri -}}
  {{- $env := upper (replace "-" "_" $c.name) -}}
  {{- $props := list
      "connector.name=iceberg"
      "iceberg.catalog.type=rest"
      (printf "iceberg.rest-catalog.uri=%s" $uri)
      (printf "iceberg.rest-catalog.warehouse=%s" $warehouse)
      "iceberg.rest-catalog.security=OAUTH2"
      (printf "iceberg.rest-catalog.oauth2.credential=${ENV:ICEBERG_OAUTH_%s}" $env)
      (printf "iceberg.rest-catalog.oauth2.scope=%s" ($c.oauth2Scope | default "PRINCIPAL_ROLE:ALL"))
      (printf "iceberg.rest-catalog.oauth2.server-uri=%s/v1/oauth/tokens" $uri)
      "iceberg.rest-catalog.vended-credentials-enabled=false"
      "fs.native-s3.enabled=true"
      (printf "s3.endpoint=%s" $s3.apiUrl)
      (printf "s3.path-style-access=%v" $s3.pathStyle)
      (printf "s3.region=%s" $s3.region)
      (printf "s3.aws-access-key=${ENV:S3_ACCESS_KEY_%s}" $env)
      (printf "s3.aws-secret-key=${ENV:S3_SECRET_ACCESS_%s}" $env) -}}
  {{- $out = append $out (dict "name" $c.name "envPrefix" $env "properties" (join "\n" $props) "s3Secret" $s3Secret "oidcSecret" ($c.oidcSecretRef | default (include "okdp-trino.oauthSecret" $))) -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}
