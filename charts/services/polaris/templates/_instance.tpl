{{/* Descriptor hooks (okdp-lib): the console UI, one iceberg-catalog output. */}}
{{- define "okdp.instance.url" -}}
{{- include "okdp.url" (dict "ctx" . "name" "polaris-console") -}}
{{- end -}}

{{- define "okdp.instance.usage" -}}
Apache Polaris is an open-source, fully-featured catalog for Apache Iceberg™.
Access the UI at {{ include "okdp.url" (dict "ctx" . "name" "polaris-console") }}
Realm {{ .Values.realm }}, root credentials in Secret {{ include "okdp-polaris.rootSecret" . }} (keys client_id and client_secret)
{{- end -}}

{{- define "okdp.instance.outputs" -}}
{{ include "okdp.contract.iceberg-catalog.provide" (dict "ctx" . "values" (dict
     "uri" (printf "%s/api/catalog" (include "okdp.url" (dict "ctx" . "name" "polaris")))
     "internalUri" (printf "%s/api/catalog" (include "okdp-polaris.internalUrl" .))
     "realm" .Values.realm)) }}
{{- end -}}
