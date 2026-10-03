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
image:
  repository: quay.io/okdp/okdp-examples
  tag: 1.2.0
  pullPolicy: Always

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

commands:
  01-prepare_env:
    01-create-spark-event-log-dir: |
      echo "👉 Connect into S3"
      mc alias set mystorage $S3_ENDPOINT "$S3_ACCESS_KEY" "$S3_SECRET_KEY"
      echo "👉 Storage alias configured successfully."
      echo "👉 Normalize the log directory $SPARK_EVENT_LOG_DIRECTORY"
      no_scheme="${SPARK_EVENT_LOG_DIRECTORY#s3a://}"
      no_scheme="${no_scheme%/}"
      bucket="${no_scheme%%/*}"
      prefix="${no_scheme#$bucket}"
      prefix="${prefix#/}"
      echo "👉 Bucket: $bucket, Prefix: $prefix"
      echo "👉 Create the bucket $bucket if not exist"
      mc mb mystorage/$bucket || true
      echo "👉 upload a zero-byte object to create the prefix: $bucket/$prefix/.keep"
      mc pipe "mystorage/$bucket/$prefix/.keep" < /dev/null
      echo "✅ Spark events log directory $SPARK_EVENT_LOG_DIRECTORY successfully created.";
    02-create-bronze-buckets: |
      echo "👉 Connect into S3"
      mc alias set mystorage $S3_ENDPOINT "$S3_ACCESS_KEY" "$S3_SECRET_KEY"

      echo "👉 Create the bucket $BRONZE_BUCKET if not exist"
      mc mb mystorage/${BRONZE_BUCKET#s3://} || true

      echo "👉 Create the bucket $SILVER_BUCKET if not exist"
      mc mb mystorage/${SILVER_BUCKET#s3://} || true

      echo "👉 Create the bucket $GOLD_BUCKET if not exist"
      mc mb mystorage/${GOLD_BUCKET#s3://} || true

  02-nyc_trip:
    # https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page
    01-download-nyc-tripdata: |
      mkdir -p /data/tripdata
      cd /data/tripdata;
      for dataset in yellow green fhv; do
        for month in 01 02 03; do
          file="{{ "$" }}{dataset}_tripdata_2025-{{ "$" }}{month}.parquet"
          url="$BRONZE_DATA_URL/$file";
          echo "→ $url";
          if curl -fsSLO "$url"; then
            echo "✅ Downloaded: $file";
          else
            echo "⚠️ Missing: $file";
          fi;
        done;
      done;
      ls -lh /data/tripdata
      echo "✅ All downloads complete.";

    02-upload-nyc-tripdata-into-s3: |

      for category in yellow green fhv; do
        echo "🚀 Processing category: $category"
        for file in /data/tripdata/{{ "$" }}{category}_*.parquet; do
          [ -e "$file" ] || continue  # skip if no files match
          month=$(basename "$file" | sed -E 's/.*_([0-9]{4}-[0-9]{2})\.parquet/\1/')
          echo "📦 Uploading $file → $BRONZE_BUCKET_PREFIX/$category/month=$month/"
          mc cp "$file" "mystorage/$BRONZE_BUCKET/$BRONZE_BUCKET_PREFIX/$category/month=$month/"
        done
      done

      echo "👉 Verify bucket structure"
      mc tree mystorage/$BRONZE_BUCKET
      mc ls --recursive mystorage/$BRONZE_BUCKET

    03-nyc-tripdata-trino-external-tables.sql: |
      ACCESS_TOKEN="$(
          curl -sS \
          -X POST "$OIDC_ISSUER_URL/protocol/openid-connect/token" \
          -H 'Content-Type: application/x-www-form-urlencoded' \
          --data-urlencode 'grant_type=client_credentials' \
          --data-urlencode "client_id=$EXAMPLES_TRINO_CLIENT_ID" \
          --data-urlencode "client_secret=$EXAMPLES_TRINO_CLIENT_SECRET" \
          | jq -r '.access_token'
      )"
      trino --server $TRINO_SERVER_URL \
            --access-token "$ACCESS_TOKEN" \
            --user "$EXAMPLES_TRINO_CLIENT_ID" \
            --truststore-path /cacerts/bundle.p12 \
            --truststore-type PKCS12 \
            --truststore-password "$TRUSTSTORE_PASSWORD" <<SQL
        CREATE SCHEMA IF NOT EXISTS bronze.nyc_tlc;

        CREATE TABLE IF NOT EXISTS bronze.nyc_tlc.yellow (
          vendorid INT,
          tpep_pickup_datetime TIMESTAMP,
          tpep_dropoff_datetime TIMESTAMP,
          passenger_count INT,
          trip_distance DOUBLE,
          ratecodeid INT,
          store_and_fwd_flag VARCHAR,
          pulocationid INT,
          dolocationid INT,
          payment_type INT,
          fare_amount DOUBLE,
          extra DOUBLE,
          mta_tax DOUBLE,
          tip_amount DOUBLE,
          tolls_amount DOUBLE,
          improvement_surcharge DOUBLE,
          total_amount DOUBLE,
          congestion_surcharge DOUBLE,
          airport_fee DOUBLE,
          cbd_congestion_fee DOUBLE,
          month VARCHAR
        )
        WITH (
          external_location = 's3a://$BRONZE_BUCKET/$BRONZE_BUCKET_PREFIX/yellow/',
          format = 'PARQUET',
          partitioned_by = ARRAY['month']
        );

        CREATE TABLE IF NOT EXISTS bronze.nyc_tlc.green (
          vendorid INT,
          lpep_pickup_datetime TIMESTAMP,
          lpep_dropoff_datetime TIMESTAMP,
          store_and_fwd_flag VARCHAR,
          ratecodeid INT,
          pulocationid INT,
          dolocationid INT,
          passenger_count INT,
          trip_distance DOUBLE,
          fare_amount DOUBLE,
          extra DOUBLE,
          mta_tax DOUBLE,
          tip_amount DOUBLE,
          tolls_amount DOUBLE,
          improvement_surcharge DOUBLE,
          total_amount DOUBLE,
          payment_type INT,
          trip_type INT,
          congestion_surcharge DOUBLE,
          cbd_congestion_fee DOUBLE,
          month VARCHAR
        )
        WITH (
          external_location = 's3a://$BRONZE_BUCKET/$BRONZE_BUCKET_PREFIX/green/',
          format = 'PARQUET',
          partitioned_by = ARRAY['month']
        );

        CREATE TABLE IF NOT EXISTS bronze.nyc_tlc.fhv (
          dispatching_base_num VARCHAR,
          pickup_datetime TIMESTAMP,
          dropoff_datetime TIMESTAMP,
          pulocationid INT,
          dolocationid INT,
          sr_flag INT,
          affiliated_base_number VARCHAR,
          month VARCHAR
        )
        WITH (
          external_location = 's3a://$BRONZE_BUCKET/$BRONZE_BUCKET_PREFIX/fhv/',
          format = 'PARQUET',
          partitioned_by = ARRAY['month']
        );
      SQL

    04-nyc-tripdata-trino-synchronize-partitions: |
      ACCESS_TOKEN="$(
          curl -sS \
          -X POST "$OIDC_ISSUER_URL/protocol/openid-connect/token" \
          -H 'Content-Type: application/x-www-form-urlencoded' \
          --data-urlencode 'grant_type=client_credentials' \
          --data-urlencode "client_id=$EXAMPLES_TRINO_CLIENT_ID" \
          --data-urlencode "client_secret=$EXAMPLES_TRINO_CLIENT_SECRET" \
          | jq -r '.access_token'
      )"
      trino --server $TRINO_SERVER_URL \
            --access-token "$ACCESS_TOKEN" \
            --user "$EXAMPLES_TRINO_CLIENT_ID" \
            --truststore-path /cacerts/bundle.p12 \
            --truststore-type PKCS12 \
            --truststore-password "$TRUSTSTORE_PASSWORD" <<SQL
        CALL bronze.system.sync_partition_metadata(
          schema_name => 'nyc_tlc',
          table_name => 'yellow',
          mode => 'ADD'
        );
        CALL bronze.system.sync_partition_metadata(
          schema_name => 'nyc_tlc',
          table_name => 'green',
          mode => 'ADD'
        );
        CALL bronze.system.sync_partition_metadata(
          schema_name => 'nyc_tlc',
          table_name => 'fhv',
          mode => 'ADD'
        );
      SQL

    05-nyc-tripdata-trino-validate: |
      ACCESS_TOKEN="$(
          curl -sS \
          -X POST "$OIDC_ISSUER_URL/protocol/openid-connect/token" \
          -H 'Content-Type: application/x-www-form-urlencoded' \
          --data-urlencode 'grant_type=client_credentials' \
          --data-urlencode "client_id=$EXAMPLES_TRINO_CLIENT_ID" \
          --data-urlencode "client_secret=$EXAMPLES_TRINO_CLIENT_SECRET" \
          | jq -r '.access_token'
      )"
      trino --server $TRINO_SERVER_URL \
            --access-token "$ACCESS_TOKEN" \
            --user "$EXAMPLES_TRINO_CLIENT_ID" \
            --truststore-path /cacerts/bundle.p12 \
            --truststore-type PKCS12 \
            --truststore-password "$TRUSTSTORE_PASSWORD" <<SQL
        SHOW SCHEMAS FROM bronze;

        SHOW TABLES FROM bronze.nyc_tlc;

        DESCRIBE bronze.nyc_tlc.yellow;
        DESCRIBE bronze.nyc_tlc.green;
        DESCRIBE bronze.nyc_tlc.fhv;

        SELECT *
        FROM bronze.nyc_tlc.yellow
        LIMIT 10;
      SQL
  03-polaris:
    01-polaris-apply-catalogs: |
      polaris-admin --catalog-file /etc/polaris/catalogs.yaml

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
