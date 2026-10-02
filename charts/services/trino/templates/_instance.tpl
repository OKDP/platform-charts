{{/* Descriptor hooks (okdp-lib-chart). */}}
{{- define "okdp.instance.url" -}}
{{- include "okdp.url" (dict "ctx" . "name" "trino") -}}
{{- end -}}

{{- define "okdp.instance.usage" -}}
Apache Trino provides distributed SQL query engine designed for large-scale data processing.
Access the UI at {{ include "okdp.url" (dict "ctx" . "name" "trino") }}
{{- end -}}

{{- define "okdp.instance.outputs" -}}
{{- $host := include "okdp-trino.host" . -}}
{{- $catalogs := list "tpch" "tpcds" -}}
{{- range $c := .Values.hiveCatalogs | default list }}{{ $catalogs = append $catalogs $c.name }}{{ end -}}
{{- range $c := .Values.icebergCatalogs | default list }}{{ $catalogs = append $catalogs $c.name }}{{ end -}}
{{ include "okdp.contract.trino.provide" (dict "ctx" . "values" (dict
     "url" (printf "https://%s" $host)
     "uri" (printf "trino://trino@%s:443" $host)
     "internalUri" (printf "trino://trino@%s.%s.svc:8080" (include "okdp-trino.fullname" .) .Release.Namespace)
     "catalogs" $catalogs)) }}
{{- end -}}
