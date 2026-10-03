{{/*
Values of the vendored spark-operator chart (the former KuboCD module
"noname"), with .Parameters -> .Values.
*/}}
{{- define "okdp-spark-operator.values" -}}
prometheus:
  metrics:
    enable: {{ .Values.metricsEnabled }}
  podMonitor:
    create: {{ .Values.podMonitorEnabled }}
controller:
  replicas: {{ .Values.controllerReplicas }}
  logLevel: {{ .Values.controllerLogLevel | quote }}
  workers: {{ .Values.controllerWorkers }}
webhook:
  enable: {{ .Values.webhookEnabled }}
spark:
  # Namespaces where Spark jobs run; "" allows all. They must exist.
  jobNamespaces: {{ .Values.jobNamespaces | default list | toJson }}
{{- end -}}

{{/*
Instance-level upstream values (okdp.vendor.render option `upstream`): an
instance sets any value of the vendored chart under upstream.spark-operator in
its values.yaml, over the values computed above, except the protected paths.
Protected: names (derived from the release), hook (its upgrade Job would
apply the CRDs templates/crds.yaml owns), certManager (its templates check
.Capabilities, accepted by okdp-guard-allow.yaml only while disabled),
spark.jobNamespaces (the jobNamespaces parameter; the operator's per-namespace
RBAC derives from it), the job ServiceAccount and RBAC (owned by the
spark-rbac service) and the operator's own RBAC and ServiceAccounts. Appended:
the controller and webhook volumes and volumeMounts, whose vendored defaults
carry the controller's /tmp and the webhook's serving certificates directory.
*/}}
{{- define "okdp-spark-operator.upstream" -}}
protect:
  - fullnameOverride
  - nameOverride
  - hook
  - certManager
  - spark.jobNamespaces
  - spark.serviceAccount.create
  - spark.rbac.create
  - controller.rbac.create
  - controller.serviceAccount.create
  - webhook.rbac.create
  - webhook.serviceAccount.create
append:
  - controller.volumes
  - controller.volumeMounts
  - webhook.volumes
  - webhook.volumeMounts
{{- end -}}
