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

{{/*
Instance-level upstream values (okdp.vendor.render option `upstream`): an
instance sets any value of the vendored chart under upstream.spark-rbac in its
values.yaml, over the values computed above, except the protected paths.
Protected: the ServiceAccount name, which the descriptor publishes and the
Spark jobs of the namespace are configured with (serviceAccountName). Nothing
is appended: the chart sets no list.
*/}}
{{- define "okdp-spark-rbac.upstream" -}}
protect:
  - serviceAccount.name
{{- end -}}
