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
