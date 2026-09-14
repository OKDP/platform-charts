{{/*
Values of the vendored spark-rbac chart (the former KuboCD module "main"):
the flat console parameters mapped onto the upstream keys.
*/}}
{{- define "okdp-spark-rbac.values" -}}
rbac:
  create: {{ .Values.rbacCreate }}
serviceAccount:
  create: {{ .Values.serviceAccountCreate }}
  name: {{ .Values.serviceAccountName | quote }}
  automount: {{ .Values.automountServiceAccountToken }}
{{- end -}}
