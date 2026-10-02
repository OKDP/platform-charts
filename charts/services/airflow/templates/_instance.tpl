{{/* Descriptor hooks (okdp-lib-chart): a UI, no output. */}}
{{- define "okdp.instance.url" -}}
{{- include "okdp.url" (dict "ctx" . "name" "airflow") -}}
{{- end -}}

{{- define "okdp.instance.usage" -}}
Apache Airflow release has been applied successfully.
Pods, ingress, and certificate provisioning may still take a few minutes.

Access the Airflow UI:
  URL: {{ include "okdp.url" (dict "ctx" . "name" "airflow") }}
  Authenticate via the configured OIDC provider.
{{- end -}}
