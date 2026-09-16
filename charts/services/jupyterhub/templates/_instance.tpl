{{/* Descriptor hooks (okdp-lib): a UI, no output. */}}
{{- define "okdp.instance.url" -}}
{{- include "okdp.url" . -}}
{{- end -}}

{{- define "okdp.instance.usage" -}}
JupyterHub provides multi-user Jupyter notebook environment with OAuth authentication.
Access the hub at {{ include "okdp.url" . }}
{{- end -}}
