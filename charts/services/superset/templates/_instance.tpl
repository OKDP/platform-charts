{{/* Descriptor hooks (okdp-lib): a UI, no output. */}}
{{- define "okdp.instance.url" -}}
{{- include "okdp.url" . -}}
{{- end -}}

{{- define "okdp.instance.usage" -}}
Apache Superset provides modern data visualization and exploration capabilities.
Access the UI at {{ include "okdp.url" . }}
{{- end -}}
