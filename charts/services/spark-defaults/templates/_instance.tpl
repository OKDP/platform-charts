{{/* Descriptor hooks (okdp-lib): no UI, no output. */}}
{{- define "okdp.instance.usage" -}}
Spark default properties for the Spark jobs of namespace `{{ .Release.Namespace }}`:
ConfigMap `spark-defaults`, key `spark-defaults.conf`.
{{- end -}}
