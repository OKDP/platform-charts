{{/* Descriptor hooks (okdp-lib-chart): no UI, no output. */}}
{{- define "okdp.instance.usage" -}}
Spark default properties for the Spark jobs of namespace `{{ .Release.Namespace }}`:
ConfigMap `spark-defaults`, key `spark-defaults.conf`.
{{- end -}}
