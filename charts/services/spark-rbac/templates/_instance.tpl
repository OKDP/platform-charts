{{/* Descriptor hooks (okdp-lib-chart): no UI, no output. */}}
{{- define "okdp.instance.usage" -}}
Kubernetes ServiceAccount and RBAC resources (Role and RoleBinding) required to run Apache Spark on Kubernetes.

Spark jobs of namespace `{{ .Release.Namespace }}` run as ServiceAccount `{{ .Values.serviceAccountName }}`.
{{- end -}}
