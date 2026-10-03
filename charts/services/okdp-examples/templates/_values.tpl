{{/*
Values of the vendored okdp-examples chart: the former KuboCD module `values:`
template, with .Context -> .Values.global.okdp, .Parameters -> .Values and
the connections resolved by okdp.connection.
*/}}
{{- define "okdp-examples-wrapper.values" -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "oidc.issuerUri")) -}}
{{- range $p := list "s3SecretRef" "trinoOidcSecretRef" -}}
  {{- if not (index $.Values $p) -}}
    {{- fail (printf "okdp-examples: %s is required" $p) -}}
  {{- end -}}
{{- end -}}
{{- $s3 := include "okdp.connection" (dict "ctx" . "ref" .Values.storage "contract" "s3" "field" "storage") | fromYaml -}}
{{- $trino := include "okdp.connection" (dict "ctx" . "ref" .Values.trino "contract" "trino" "field" "trino") | fromYaml -}}
{{- $polaris := include "okdp.connection" (dict "ctx" . "ref" .Values.polaris "contract" "iceberg-catalog" "field" "polaris") | fromYaml -}}
{{- $storageApiUrl := $s3.internalUrl | default $s3.apiUrl -}}
{{- /* The connection publishes the Iceberg REST base; polaris-admin wants the server root. */ -}}
{{- $polarisEndpointUrl := trimSuffix "/api/catalog" ($polaris.internalUri | default $polaris.uri) -}}
{{- $realms := include "okdp-examples-wrapper.realms" . | fromYamlArray -}}
fullnameOverride: {{ .Release.Name | quote }}
extraEnvRaw:
  - name: MC_INSECURE
    value: "1"
  - name: S3_ENDPOINT
    value: {{ $storageApiUrl | quote }}

  # Bronze Layer
  - name: S3_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: {{ .Values.s3SecretRef }}
        key: accessKey
  - name: S3_SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: {{ .Values.s3SecretRef }}
        key: secretKey

  - name: BRONZE_BUCKET
    value: {{ .Values.bronzeBucket | quote }}
  - name: BRONZE_BUCKET_PREFIX
    value: {{ .Values.bronzePrefix | quote }}
  - name: BRONZE_DATA_URL
    value: {{ .Values.bronzeDataUrl | quote }}
  - name: SILVER_BUCKET
    value: {{ .Values.silverBucket | quote }}
  - name: GOLD_BUCKET
    value: {{ .Values.goldBucket | quote }}

  - name: TRINO_SERVER_URL
    value: {{ $trino.url | quote }}
  - name: TRINO_TERMINAL
    value: dumb
  - name: EXAMPLES_TRINO_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: {{ .Values.trinoOidcSecretRef }}
        key: client_id
  - name: EXAMPLES_TRINO_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: {{ .Values.trinoOidcSecretRef }}
        key: client_secret

  - name: SPARK_EVENT_LOG_DIRECTORY
    value: {{ .Values.sparkEventsLogDir | quote }}
  {{- with include "okdp.proxy.envList" . | fromYamlArray }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
  # Polaris
  - name: OIDC_ISSUER_URL
    value: {{ .Values.global.okdp.oidc.issuerUri | quote }}
  - name: POLARIS_URL
    value: {{ $polarisEndpointUrl | quote }}
  - name: CA_CERT_PATH
    value: /cacerts/ca.crt
  - name: CURL_CA_BUNDLE
    value: /cacerts/ca.crt
  - name: TRUSTSTORE_PASSWORD
    value: ""
  {{- range $r := $realms }}
  - name: {{ printf "%s_POLARIS_OIDC_CLIENT_ID" $r.prefix }}
    valueFrom:
      secretKeyRef:
        name: {{ $r.secret.name }}
        key: {{ $r.secret.clientIdKey }}
  - name: {{ printf "%s_POLARIS_OIDC_CLIENT_SECRET" $r.prefix }}
    valueFrom:
      secretKeyRef:
        name: {{ $r.secret.name }}
        key: {{ $r.secret.clientSecretKey }}
  {{- end }}

resources:
  requests:
    cpu: {{ .Values.cpu | quote }}
    memory: {{ printf "%vGi" .Values.memoryGi | quote }}
  limits:
    cpu: {{ mulf (float64 .Values.cpu) 2 | quote }}
    memory: {{ printf "%vGi" (mulf (float64 .Values.memoryGi) 2) | quote }}

extraVolumes:
  - name: cacerts
    secret:
      secretName: certs-bundle

extraVolumeMounts:
  - name: cacerts
    mountPath: /cacerts

extraFiles:
  polaris-catalogs:
    mountPath: /etc/polaris/catalogs.yaml
    stringData: {{ toYaml .Values.polarisRealms | quote }}

{{- end -}}

{{/*
okdp-examples-wrapper.realms: per Polaris realm, the principal holding the
catalog_admin role and its credentials Secret, as a YAML list of
{prefix, secret: {name, clientIdKey, clientSecretKey}}.
*/}}
{{- define "okdp-examples-wrapper.realms" -}}
{{- $out := list -}}
{{- range $realm := (.Values.polarisRealms | default dict).realms | default list -}}
  {{- $prefix := regexReplaceAll "_+" (regexReplaceAll "[^A-Za-z0-9]+" (upper $realm.name) "_") "_" | trimAll "_" -}}
  {{- $principal := dict -}}
  {{- range $p := $realm.principals | default list -}}
    {{- if and (not $principal) (has "catalog_admin" ($p.principalRoles | default list)) $p.credentialsSecret -}}
      {{- $principal = $p -}}
    {{- end -}}
  {{- end -}}
  {{- if not $principal -}}
    {{- fail (printf "okdp-examples: polarisRealms: no principal with role 'catalog_admin' and a credentialsSecret found in realm %q" $realm.name) -}}
  {{- end -}}
  {{- range $k := list "name" "clientIdKey" "clientSecretKey" -}}
    {{- if not (index $principal.credentialsSecret $k) -}}
      {{- fail (printf "okdp-examples: polarisRealms: principal %q in realm %q is missing credentialsSecret.%s" $principal.name $realm.name $k) -}}
    {{- end -}}
  {{- end -}}
  {{- $out = append $out (dict "prefix" $prefix "secret" $principal.credentialsSecret) -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}

{{/*
Instance-level upstream values (okdp.vendor.render option `upstream`): an
instance sets any value of the vendored chart under upstream.okdp-examples in
its values.yaml, over the values computed above, except the protected paths.
Protected: the object names, the seed Job's hook annotations (hooks are
limited to pre/post-install/upgrade) and the realms file the 03-polaris step
applies, generated from polarisRealms. Appended: the lists carrying the S3,
Trino and Polaris credentials and the CA bundle, so an instance adds to them.
*/}}
{{- define "okdp-examples-wrapper.upstream" -}}
protect:
  - fullnameOverride
  - job.annotations
  - extraFiles.polaris-catalogs
append:
  - extraEnvRaw
  - extraVolumes
  - extraVolumeMounts
{{- end -}}
