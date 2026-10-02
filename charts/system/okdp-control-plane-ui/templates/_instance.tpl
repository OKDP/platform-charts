{{/* Descriptor hooks (okdp-lib-chart). */}}
{{- define "okdp.instance.url" -}}
https://{{ include "okdp-cp-ui.host" . }}
{{- end -}}

{{- define "okdp.instance.usage" -}}
Access the console at https://{{ include "okdp-cp-ui.host" . }}
The same ingress routes /api to the okdp-control-plane-server Service
(`{{ include "okdp-cp-ui.backendService" . }}`), so the browser never leaves
the origin and the API is never exposed on its own host.
{{- end -}}
