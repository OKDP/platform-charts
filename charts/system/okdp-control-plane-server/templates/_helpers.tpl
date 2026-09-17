{{/* Console host: consoleHost, else okdp-ui.<ingress suffix>. */}}
{{- define "okdp-cp-server.consoleHost" -}}
{{- if .Values.consoleHost -}}
{{- .Values.consoleHost -}}
{{- else -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "ingress.suffix")) -}}
{{- printf "okdp-ui.%s" .Values.global.okdp.ingress.suffix -}}
{{- end -}}
{{- end -}}

{{/* Where the pod mounts the Git credentials and keeps its clone (a cache). */}}
{{- define "okdp-cp-server.credentialsDir" -}}/etc/okdp/gitops-credentials{{- end -}}
{{- define "okdp-cp-server.cloneDir" -}}/var/cache/okdp/gitops{{- end -}}
