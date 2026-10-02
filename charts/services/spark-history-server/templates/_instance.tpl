{{/* Descriptor hooks (okdp-lib-chart): a UI (the web proxy), no output. */}}
{{- define "okdp.instance.url" -}}
{{- include "okdp.url" (dict "ctx" . "name" "spark-web-proxy") -}}
{{- end -}}

{{- define "okdp.instance.usage" -}}
Spark History Server provides a web UI for viewing completed Spark applications.
Access the UI at {{ include "okdp.url" (dict "ctx" . "name" "spark-web-proxy") }}
{{- end -}}
