{{/* Descriptor hooks (okdp-lib-chart): the API has no host of its own. */}}
{{- define "okdp.instance.usage" -}}
The API is not exposed on its own host: the console routes /api to it, so
the browser stays same-origin. Reach it at
https://{{ include "okdp-cp-server.consoleHost" . }}/api
{{- end -}}
