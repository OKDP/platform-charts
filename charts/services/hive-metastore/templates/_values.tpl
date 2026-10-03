{{/*
Values of the vendored hive-metastore chart (the former KuboCD module "main").
*/}}
{{- define "hive-metastore.upstream.values" -}}
{{- $db := include "okdp.connection" (dict "ctx" . "ref" .Values.db "contract" "database-server" "field" "db") | fromYaml -}}
{{- $s3 := include "okdp.connection" (dict "ctx" . "ref" .Values.storage "contract" "s3" "field" "storage") | fromYaml -}}
{{- if not $db.secretRef -}}
  {{- fail (printf "hive-metastore: db: connection %q has no secretRef: the metastore needs a Secret with the keys username and password" .Values.db) -}}
{{- end -}}
{{- if not .Values.s3SecretRef -}}
  {{- fail "hive-metastore: s3SecretRef is required: a Secret with the keys accessKey and secretKey, this metastore's own S3 identity" -}}
{{- end -}}
# The Service name is the one the hive contract promises to internal
# references: <release>-hive-metastore.
fullNameOverride: {{ include "okdp.fullname" (dict "ctx" . "suffix" "hive-metastore") }}
replicaCount: 1
image:
  repository: quay.io/okdp/hive-metastore
  tag: 4.0.1
  pullPolicy: IfNotPresent
logLevel: INFO
db:
  driverRef: {{ $db.driver }}
  driverName: {{ $db.engine }}
  host: {{ $db.host }}
  port: {{ $db.port }}
  databaseName: {{ $db.dbName }}
  user:
    password:
      secretName: {{ $db.secretRef.name }}
      propertyName: password
extraEnvRaw:
  - name: HIVEMS_USER
    valueFrom:
      secretKeyRef:
        name: {{ $db.secretRef.name }}
        key: username
  - name: THRIFT_LISTENING_PORT
    value: "9083"
cloud_storage: s3
s3:
  url: {{ $s3.apiUrl }}
  # The upstream chart names it a directory, it is a bucket (no prefix).
  warehouseDirectory: {{ .Values.warehouseBucket }}
  accessKey:
    secretName: {{ .Values.s3SecretRef }}
    propertyName: accessKey
  secretKey:
    secretName: {{ .Values.s3SecretRef }}
    propertyName: secretKey
gcs:
  enabled: false
resources:
  requests:
    cpu: {{ .Values.cpu | quote }}
    memory: {{ printf "%vGi" .Values.memoryGi | quote }}
  limits:
    cpu: {{ mulf (float64 .Values.cpu) 2 | quote }}
    memory: {{ printf "%vGi" (mulf (float64 .Values.memoryGi) 2) | quote }}
{{- end -}}

{{/*
Instance-level upstream values (okdp.vendor.render option `upstream`): an
instance sets any value of the vendored chart under upstream.hive-metastore in
its values.yaml, over the values computed above, except the protected paths.
Protected: the Service name and port the hive contract publishes
(thrift://<release>-hive-metastore:9083), the database and S3 credentials
wired from the db/storage connections and s3SecretRef, the storage backend the
s3 connection implies, and the schema init Job's hook annotations (hooks are
limited to pre/post-install/upgrade). Appended: extraEnvRaw, which carries the
database user Secret and the Thrift port, so an instance adds to it.
*/}}
{{- define "hive-metastore.upstream" -}}
protect:
  - fullNameOverride
  - serviceName
  - servicePort
  - db
  - s3.url
  - s3.accessKey
  - s3.secretKey
  - cloud_storage
  - initJob.annotations
append:
  - extraEnvRaw
{{- end -}}
