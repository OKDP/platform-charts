{{/*
Values of the vendored spark-operator chart (the former KuboCD module
"noname"), with .Parameters -> .Values.
*/}}
{{- define "okdp-spark-operator.values" -}}
# CRDs are rendered by templates/crds.yaml, not by an upgrade hook.
hook:
  upgradeCrd: false
prometheus:
  metrics:
    enable: {{ .Values.metricsEnabled }}
  podMonitor:
    create: {{ .Values.podMonitorEnabled }}
controller:
  replicas: {{ .Values.controllerReplicas }}
  logLevel: {{ .Values.controllerLogLevel | quote }}
  workers: {{ .Values.controllerWorkers }}
  rbac:
    create: true
  # The KuboCD values deleted fsGroup (null), leaving no pod securityContext.
  # okdp.vendor.render merges maps, so null the whole map for the same output.
  podSecurityContext: null
webhook:
  enable: {{ .Values.webhookEnabled }}
  # The KuboCD values deleted fsGroup (null), leaving no pod securityContext.
  # okdp.vendor.render merges maps, so null the whole map for the same output.
  podSecurityContext: null
spark:
  # Namespaces where Spark jobs run; "" allows all. They must exist.
  jobNamespaces: {{ .Values.jobNamespaces | default list | toJson }}
  # The ServiceAccount and RBAC of the jobs come from the spark-rbac chart.
  serviceAccount:
    create: false
  rbac:
    create: false
# Never enabled: its templates check .Capabilities (see okdp-guard-allow.yaml).
certManager:
  enable: false
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
