{{/* Descriptor hooks (okdp-lib-chart): no UI, one hive output. */}}
{{- define "okdp.instance.usage" -}}
Hive Metastore is a centralized metadata repository for data lakes and big data analytics.

Thrift endpoint: `{{ include "hive-metastore.thriftUri" . }}`
{{- end -}}

{{- define "okdp.instance.outputs" -}}
{{ include "okdp.contract.hive.provide" (dict "ctx" . "values" (dict "thriftUri" (include "hive-metastore.thriftUri" .))) }}
{{- end -}}

{{- define "hive-metastore.thriftUri" -}}
{{- printf "thrift://%s.%s.svc:9083" (include "okdp.fullname" (dict "ctx" . "suffix" "hive-metastore")) .Release.Namespace -}}
{{- end -}}
