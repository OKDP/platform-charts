{{/*
Values of the vendored Apache Superset chart: the former KuboCD module
`values:` template, with .Context -> .Values.global.okdp, .Parameters ->
.Values and the connections resolved by okdp.connection.

The former module rendered OKDP's superset chart
(quay.io/okdp/charts/superset 0.15.2-2.0), a wrapper around the Apache chart
with its own env Secrets and Python config overrides. That wrapper is folded
in here: its defaults are part of okdp-superset-wrapper.values.superset, its
env Secrets are templates/env-secrets.yaml (same names and keys, read by the
Python config and the init containers).
*/}}

{{/* Resolved inputs, as YAML. */}}
{{- define "okdp-superset-wrapper.inputs" -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "ingress.suffix" "ingress.className" "certificateIssuers.selfSigned.name" "oidc.issuerUri")) -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- $meta := include "okdp.connection" (dict "ctx" . "ref" .Values.metadataDb "contract" "database-server" "field" "metadataDb") | fromYaml -}}
{{- if not $meta.secretRef -}}
  {{- fail (printf "superset: metadataDb: connection %q has no secretRef: Superset needs a Secret with the keys username and password" .Values.metadataDb) -}}
{{- end -}}
{{- $examples := dict -}}
{{- if .Values.load_examples -}}
  {{- $examples = include "okdp.connection" (dict "ctx" . "ref" .Values.examplesDb "contract" "database-server" "field" "examplesDb") | fromYaml -}}
  {{- if not $examples.secretRef -}}
    {{- fail (printf "superset: examplesDb: connection %q has no secretRef: the examples loader needs a Secret with the keys username and password" .Values.examplesDb) -}}
  {{- end -}}
{{- end -}}
{{- $datasources := list -}}
{{- range $i, $d := .Values.datasources | default list -}}
  {{- $trino := include "okdp.connection" (dict "ctx" $ "ref" $d.trino "contract" "trino" "field" (printf "datasources[%d].trino" $i)) | fromYaml -}}
  {{- $datasources = append $datasources (dict "name" $d.name "uri" $trino.uri "catalog" $d.catalog) -}}
{{- end -}}
oidc: {{ toYaml $oidc | nindent 2 }}
oidcBaseUrl: {{ printf "%s/protocol/openid-connect" $oidc.issuerUri | quote }}
host: {{ include "okdp.ingressHost" . | quote }}
metadataDb: {{ toYaml $meta | nindent 2 }}
examplesDb: {{ toYaml $examples | nindent 2 }}
datasources: {{ toYaml $datasources | nindent 2 }}
{{- end -}}

{{/*
Data of the env Secrets (templates/env-secrets.yaml), formerly rendered by
OKDP's wrapper chart from its `okdp:` values, as YAML: one map per Secret
suffix. Credentials are not in them: they come from secretKeyRefs
(extraEnvRaw).
*/}}
{{- define "okdp-superset-wrapper.envSecrets" -}}
{{- $in := include "okdp-superset-wrapper.inputs" . | fromYaml -}}
{{- $oidc := $in.oidc -}}
{{- $meta := $in.metadataDb -}}
{{- $ex := $in.examplesDb -}}
db-env:
  DB_HOST: {{ $meta.host | quote }}
  DB_PORT: {{ $meta.port | quote }}
  DB_NAME: {{ $meta.dbName | quote }}
oauth2-env:
  AUTH_OAUTH_ENABLED: {{ $oidc.enabled | quote }}
  {{- if $oidc.enabled }}
  AUTH_OAUTH_BASE_URL: {{ $in.oidcBaseUrl | quote }}
  AUTH_OAUTH_PROVIDER: {{ $oidc.displayName | default "keycloak" | quote }}
  {{- with $oidc.scope }}
  AUTH_OAUTH_SCOPE: {{ . | quote }}
  {{- end }}
  {{- /* Verified against REQUESTS_CA_BUNDLE (certs-bundle, mounted at /cacerts). */}}
  AUTH_OAUTH_SSL_CERTIFICATE_VERIFY: {{ if $oidc.insecureSkipVerify }}"false"{{ else }}"true"{{ end }}
  AUTH_OAUTH_USE_PKCE: {{ if (hasKey $oidc "usePKCE" | ternary $oidc.usePKCE true) }}"S256"{{ else }}"None"{{ end }}
  SUPERSET_DOMAIN: {{ $in.host | quote }}
  {{- end }}
redis-env:
  REDIS_HOST: {{ include "okdp-superset-wrapper.redis" . | quote }}
  REDIS_PORT: "6379"
  REDIS_PROTO: "redis"
  REDIS_DB: "1"
  REDIS_CELERY_DB: "0"
superset-env:
  SUPERSET_LOAD_EXAMPLES: {{ .Values.load_examples | quote }}
  {{- if .Values.load_examples }}
  {{- /* The examples loader is postgresql specific (psycopg2 dialect, main search_path) */}}
  SQLALCHEMY_EXAMPLES_URI: {{ printf "postgresql+psycopg2://$DB_EXAMPLES_USER:$DB_EXAMPLES_PASS@%s:%v/%s?options=-csearch_path%%3Dmain" $ex.host $ex.port $ex.dbName | quote }}
  {{- end }}
trino-oauth2-env:
  TRINO_OAUTH_ENABLED: {{ $oidc.enabled | quote }}
  {{- if $oidc.enabled }}
  TRINO_AUTH_OAUTH_BASE_URL: {{ $in.oidcBaseUrl | quote }}
  {{- with $oidc.scope }}
  TRINO_OAUTH_SCOPE: {{ . | quote }}
  {{- end }}
  SUPERSET_DOMAIN: {{ $in.host | quote }}
  {{- end }}
{{- end -}}

{{- define "okdp-superset-wrapper.rolesMapping" -}}
AUTH_ROLES_MAPPING = {
{{- range $oidcRole, $supersetRoles := .Values.oidcRoleMapping | default dict }}
  {{ $oidcRole | quote }}: {{ $supersetRoles | toJson }},
{{- end }}
}
{{ end -}}

{{- define "okdp-superset-wrapper.extraConfig" -}}
from datetime import timedelta
# Set up max age of session to 8 hours
PERMANENT_SESSION_LIFETIME = timedelta(hours=8)
# This will make sure the redirect_uri is properly computed, even with SSL offloading
ENABLE_PROXY_FIX = True
PROXY_FIX_CONFIG = {
  "x_for": 1,
  "x_proto": 1,
  "x_host": 1,
  "x_port": 1,
  "x_prefix": 1,
}
# Chart number and date formats. The locale tables are read from CLDR through
# Babel, a Superset dependency, so that none has to be maintained in this package
import base64
import json

D3_LOCALE = {{ .Values.locale | default "" | quote }}
D3_CURRENCY = {{ .Values.currency | default "" | quote }}
D3_FORMAT = {}
D3_TIME_FORMAT = {}

if D3_LOCALE:
    import logging
    import re
    from babel import Locale
    from babel.numbers import get_currency_symbol, get_territory_currencies

    # CLDR short patterns carry a two digit year, unreadable on a chart axis
    _LDML_TO_STRFTIME = [
        ("yyyy", "%Y"), ("yy", "%Y"), ("y", "%Y"), ("MMMM", "%B"), ("MMM", "%b"),
        ("MM", "%m"), ("M", "%-m"), ("dd", "%d"), ("d", "%-d"), ("EEEE", "%A"),
        ("EEE", "%a"), ("HH", "%H"), ("H", "%-H"), ("hh", "%I"), ("h", "%-I"),
        ("mm", "%M"), ("ss", "%S"), ("a", "%p"),
    ]

    def _strftime(pattern):
        out, index = "", 0
        while index < len(pattern):
            for ldml, directive in _LDML_TO_STRFTIME:
                if pattern.startswith(ldml, index):
                    out, index = out + directive, index + len(ldml)
                    break
            else:
                out, index = out + pattern[index], index + 1
        return out

    try:
        _locale = Locale.parse(D3_LOCALE, sep="-")
        _symbols = _locale.number_symbols["latn"]
        D3_FORMAT = {
            "decimal": _symbols["decimal"],
            "thousands": _symbols["group"],
            "grouping": [3],
        }
        _currency = D3_CURRENCY or (
            get_territory_currencies(_locale.territory)[0] if _locale.territory else ""
        )
        if _currency:
            _symbol = get_currency_symbol(_currency, locale=_locale)
            _affixes = re.split(
                r"[#0][#0,.]*", _locale.currency_formats["standard"].pattern
            )
            D3_FORMAT["currency"] = [
                _affixes[0].replace("¤", _symbol),
                _affixes[-1].replace("¤", _symbol),
            ]
        # d3 has no spacing rule of its own, the percent sign carries it
        _spacing = re.search(r"0(\D*?)%", _locale.percent_formats[None].pattern)
        if _spacing and _spacing.group(1):
            D3_FORMAT["percent"] = _spacing.group(1) + "%"
        _date = _strftime(_locale.date_formats["short"].pattern)
        _time = _strftime(_locale.time_formats["medium"].pattern)
        _periods = _locale.day_periods["format"]["wide"]
        _days, _months = _locale.days["format"], _locale.months["format"]
        D3_TIME_FORMAT = {
            "dateTime": "%s, %s" % (_date, _time),
            "date": _date,
            "time": _time,
            "periods": [_periods.get("am", "AM"), _periods.get("pm", "PM")],
            "days": [_days["wide"][(i + 6) % 7] for i in range(7)],
            "shortDays": [_days["abbreviated"][(i + 6) % 7] for i in range(7)],
            "months": [_months["wide"][i] for i in range(1, 13)],
            "shortMonths": [_months["abbreviated"][i] for i in range(1, 13)],
        }
    except Exception:
        # A formatting detail must never keep the instance from starting
        logging.getLogger(__name__).exception(
            "Falling back to the default formats, unusable locale %s", D3_LOCALE
        )
        D3_FORMAT, D3_TIME_FORMAT = {}, {}

# The overrides are data, never code: base64 of their JSON, so no value can
# end the Python string (or reach the chart's tpl as a template).
D3_FORMAT.update(json.loads(base64.b64decode("{{ .Values.d3Format | default dict | toJson | b64enc }}").decode("utf-8")))
D3_TIME_FORMAT.update(json.loads(base64.b64decode("{{ .Values.d3TimeFormat | default dict | toJson | b64enc }}").decode("utf-8")))
{{ end -}}

{{/*
A wait init container of the Superset pods: the Apache default, reading the
database (and cache) host and port from the env Secrets.
Takes {ctx, name, redis}.
*/}}
{{- define "okdp-superset-wrapper.waitContainer" -}}
{{- $ctx := .ctx -}}
{{- /* Template code for the upstream chart, which passes initContainers to tpl: the Superset image. */ -}}
{{- $image := "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}" -}}
{{- $pullPolicy := "{{ .Values.image.pullPolicy }}" -}}
name: {{ .name }}
image: {{ $image | quote }}
imagePullPolicy: {{ $pullPolicy | quote }}
envFrom:
  - secretRef:
      name: {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" $ctx "suffix" "db-env") }}
  {{- if .redis }}
  - secretRef:
      name: {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" $ctx "suffix" "redis-env") }}
  {{- end }}
command:
  - /bin/bash
  - -c
  - |
    SECONDS=0
    wait_for() {
      local host=$1 port=$2 name=$3
      until (exec 3<>/dev/tcp/"$host"/"$port") 2>/dev/null; do
        if [ "$SECONDS" -ge 120 ]; then
          echo "timeout waiting for $name at $host:$port after 120s" >&2
          exit 1
        fi
        echo "waiting for $name at $host:$port (elapsed ${SECONDS}s)"
        sleep 2
      done
      echo "$name at $host:$port is up"
    }
    wait_for "$DB_HOST" "$DB_PORT" postgres
    {{- if .redis }}
    wait_for "$REDIS_HOST" "$REDIS_PORT" redis
    {{- end }}
resources:
  limits:
    memory: "256Mi"
  requests:
    cpu: "250m"
    memory: "128Mi"
{{- end -}}

{{/*
Module main: the values of the Apache Superset chart (vendor/superset), OKDP's
former wrapper defaults included. Keys left out keep the Apache defaults
(vendor/superset/values.yaml).
*/}}
{{- define "okdp-superset-wrapper.values.superset" -}}
{{- $in := include "okdp-superset-wrapper.inputs" . | fromYaml -}}
{{- $oidc := $in.oidc -}}
{{- $release := .Release.Name -}}
{{- $fullname := include "okdp-superset-wrapper.fullname" . -}}
{{- $internal := include "okdp-superset-wrapper.internalSecret" . -}}
{{- $oauthSecret := include "okdp.oidc.clientSecret" . -}}
{{- /* dcr mode: one client for the sign-in and the Trino datasources (both redirect URIs). */ -}}
{{- $trinoOauthSecret := ternary $oauthSecret (include "okdp-superset-wrapper.trinoOauthSecret" .) $oidc.dcr.enabled -}}
{{- $meta := $in.metadataDb -}}
{{- $ex := $in.examplesDb -}}
{{- $okdp := .Values.global.okdp -}}
fullnameOverride: {{ $fullname }}
# The env Secrets of templates/env-secrets.yaml.
envFromSecret: {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" . "suffix" "superset-env") }}
envFromSecrets:
  - {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" . "suffix" "db-env") }}
  - {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" . "suffix" "oauth2-env") }}
  - {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" . "suffix" "redis-env") }}
  - {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" . "suffix" "trino-oauth2-env") }}

# Computed blocks of superset_config.py (the fixed ones: vendor-values/superset.yaml).
configOverrides:
  oauth_to_superset_roles_mapping: {{ include "okdp-superset-wrapper.rolesMapping" . | quote }}
  extra_config: {{ include "okdp-superset-wrapper.extraConfig" . | quote }}
cache:
  host: {{ include "okdp-superset-wrapper.redis" . | quote }}

extraConfigs:
  import_datasources.yaml: |
    databases:
    {{- range $in.datasources }}
      - database_name: {{ .name | quote }}
        sqlalchemy_uri: {{ printf "%s/%s" .uri .catalog | quote }}
        impersonate_user: true
        extra: |
          {
            "engine_params": {},
            "metadata_params": {},
            "connect_args": {
              "http_scheme": "https",
              "verify": {{ not $oidc.insecureSkipVerify | toJson }}
            },
            "metadata_cache_timeout": {},
            "schemas_allowed_for_file_upload": []
          }
        allow_run_async: true
        allow_dml: true
        allow_ctas: true
        allow_cvas: true
        expose_in_sqllab: true
        tables: []
    {{- end }}
extraEnvRaw:
  # Superset secret key
  - name: SUPERSET_SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: {{ $internal }}
        key: superset_secret_key
  # Superset/DB credentials
  - name: DB_USER
    valueFrom:
      secretKeyRef:
        name: {{ $meta.secretRef.name }}
        key: username
  - name: DB_PASS
    valueFrom:
      secretKeyRef:
        name: {{ $meta.secretRef.name }}
        key: password
  # Superset/Redis credentials
  - name: REDIS_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ $internal }}
        key: redis-password
  {{- if $oidc.enabled }}
  # OIDC credentials
  - name: AUTH_OAUTH_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: {{ $oauthSecret }}
        key: client_id
  - name: AUTH_OAUTH_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: {{ $oauthSecret }}
        key: client_secret
  # OIDC Trino credentials
  - name: TRINO_OAUTH_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: {{ $trinoOauthSecret }}
        key: client_id
  - name: TRINO_OAUTH_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: {{ $trinoOauthSecret }}
        key: client_secret
  {{- else }}
  # Password of the local admin (no OIDC): the init Job creates it.
  - name: SUPERSET_ADMIN_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ include "okdp-superset-wrapper.adminSecret" . }}
        key: password
  {{- end }}
  # CA
  - name: REQUESTS_CA_BUNDLE
    value: /cacerts/ca.crt
  {{- with include "okdp.proxy.envList" . | fromYamlArray }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
  {{- if .Values.load_examples }}
  # Examples
  - name: DB_EXAMPLES_HOST
    value: {{ $ex.host | quote }}
  - name: DB_EXAMPLES_PORT
    value: {{ $ex.port | quote }}
  - name: DB_EXAMPLES_NAME
    value: {{ $ex.dbName | quote }}
  - name: DB_EXAMPLES_USER
    valueFrom:
      secretKeyRef:
        name: {{ $ex.secretRef.name }}
        key: username
  - name: DB_EXAMPLES_PASS
    valueFrom:
      secretKeyRef:
        name: {{ $ex.secretRef.name }}
        key: password
  {{- end }}

# The chart waits on the server TCP port, which says nothing about the
# databases existing: the schema upgrade then fails on a database not
# created yet, and the job burns its retries.
init:
  # Without OIDC there is no other way in, so a local admin is created, with a
  # password generated per instance (Secret <release>-admin, admin-secret.yaml).
  # The chart can only write init.adminUser.password into its script, so its
  # own admin creation is off and the command below creates the admin from
  # SUPERSET_ADMIN_PASSWORD (extraEnvRaw), if it does not exist yet.
  loadExamples: {{ .Values.load_examples }}
  {{- if not $oidc.enabled }}
  {{- /* Template code for the upstream chart, which passes init.command to tpl. */}}
  {{- $configMountPath := "{{ .Values.configMountPath }}" }}
  command:
    - /bin/sh
    - -c
    - |
      . {{ $configMountPath }}/superset_bootstrap.sh
      . {{ $configMountPath }}/superset_init.sh
      if superset fab list-users 2>/dev/null | grep -qF 'username:admin'; then
        echo "Admin user already exists, skipping."
      else
        echo "Creating admin user..."
        superset fab create-admin --username admin --firstname Superset \
          --lastname Admin --email admin@superset.com --password "$SUPERSET_ADMIN_PASSWORD"
      fi
  {{- end }}
  initContainers:
    - name: wait-for-databases
      image: postgres:16-alpine
      env:
        # Connection fields through the environment: the script expands
        # nothing that comes from the values.
        - name: META_HOST
          value: {{ $meta.host | quote }}
        - name: META_PORT
          value: {{ $meta.port | quote }}
        - name: META_DB
          value: {{ $meta.dbName | quote }}
        - name: META_PW
          valueFrom:
            secretKeyRef:
              name: {{ $meta.secretRef.name }}
              key: password
        - name: META_USER
          valueFrom:
            secretKeyRef:
              name: {{ $meta.secretRef.name }}
              key: username
        {{- if .Values.load_examples }}
        - name: EX_HOST
          value: {{ $ex.host | quote }}
        - name: EX_PORT
          value: {{ $ex.port | quote }}
        - name: EX_DB
          value: {{ $ex.dbName | quote }}
        - name: EX_PW
          valueFrom:
            secretKeyRef:
              name: {{ $ex.secretRef.name }}
              key: password
        - name: EX_USER
          valueFrom:
            secretKeyRef:
              name: {{ $ex.secretRef.name }}
              key: username
        {{- end }}
      command:
        - /bin/sh
        - -c
        - |
          until PGPASSWORD="$META_PW" psql -h "$META_HOST" -p "$META_PORT" -U "$META_USER" -d "$META_DB" -c '\q' 2>/dev/null; do
            echo "waiting for database $META_DB"; sleep 3
          done
          {{- if .Values.load_examples }}
          until PGPASSWORD="$EX_PW" psql -h "$EX_HOST" -p "$EX_PORT" -U "$EX_USER" -d "$EX_DB" -c '\q' 2>/dev/null; do
            echo "waiting for database $EX_DB"; sleep 3
          done
          {{- end }}
          echo "databases reachable"

extraEnv:
  SERVER_WORKER_AMOUNT: {{ .Values.workers | quote }}

# The wait init containers read the host and port of the database and the
# cache from the env Secrets (the Apache defaults read envFromSecret).
supersetWorker:
  initContainers:
    - {{ include "okdp-superset-wrapper.waitContainer" (dict "ctx" . "name" "wait-for-postgres-redis" "redis" true) | nindent 6 }}
supersetNode:
  initContainers:
    - {{ include "okdp-superset-wrapper.waitContainer" (dict "ctx" . "name" "wait-for-postgres" "redis" false) | nindent 6 }}
  resources:
    limits:
      memory: {{ printf "%vGi" .Values.memoryGi | quote }}
      cpu: {{ .Values.cpu | quote }}

ingress:
  ingressClassName: {{ $okdp.ingress.className }}
  annotations:
    kubernetes.io/ingress.class: {{ $okdp.ingress.className }}
    {{- include "okdp.ingressAnnotations" . | nindent 4 }}
  hosts:
    - {{ $in.host }}
  tls:
    - hosts:
        - {{ $in.host }}
      secretName: {{ printf "%s-tls-secret" $release }}
{{- end -}}

{{/*
Instance-level upstream values (okdp.vendor.render option `upstream`): an
instance sets any value of the vendored chart under upstream.superset in its
values.yaml, over the values computed above, except the protected paths.
Protected: what the platform relies on: the names (fullnameOverride, the env
and config Secrets the pods read), the configOverrides blocks carrying OIDC
sign-in, the Trino OAuth2, the Valkey password, the examples and the proxy fix
the redirect_uri depends on, the metadata database (its URI is built from the
DB_* env of templates/env-secrets.yaml) and the cache connection to
templates/valkey.yaml (the bundled postgresql and redis charts are dropped),
the local admin creation (createAdmin writes the password into the init script;
the wrapper creates it from a Secret), forceReload (randAlphaNum, allowed by
okdp-guard-allow.yaml only while false), configOverridesFiles (their
.Files.Get paths would resolve in the wrapper, not in vendor/superset) and the
ingress host registered with the identity provider. configOverrides is Python
appended to superset_config.py: an instance may add blocks, which run after
the wrapper's and can redefine any setting; the protection keeps the
wrapper's blocks in place, it is no sandbox. extraConfigs.import_datasources.yaml
(a dotted key, which a path cannot name) follows `datasources` unless an
instance replaces it. Appended: the lists carrying the wrapper's env Secrets,
credentials, CA bundle and wait init containers, so an instance adds to them.
*/}}
{{- define "okdp-superset-wrapper.upstream.superset" -}}
protect:
  - fullnameOverride
  - envFromSecret
  - configFromSecret
  - configOverrides.auth_registration
  - configOverrides.oauth_enabled
  - configOverrides.trino_oauth_enabled
  - configOverrides.custom_sso_security_manager
  - configOverrides.extra_config
  - configOverrides.load_examples
  - configOverrides.valkey_password
  - configOverridesFiles
  - config.resultsBackend
  - database.uri
  - database.driver
  - cache.enabled
  - cache.host
  - cache.port
  - cache.user
  - cache.password
  - cache.cacheUrl
  - cache.celeryUrl
  - cache.cacheDb
  - cache.celeryDb
  - postgresql
  - redis
  - init.createAdmin
  - init.adminUser
  - init.command
  - supersetNode.forceReload
  - supersetWorker.forceReload
  - supersetCeleryBeat.forceReload
  - supersetMcp.forceReload
  - ingress.enabled
  - ingress.ingressClassName
  - ingress.hosts
  - ingress.tls
append:
  - envFromSecrets
  - extraEnvRaw
  - extraVolumes
  - extraVolumeMounts
  - init.initContainers
  - supersetNode.initContainers
  - supersetWorker.initContainers
{{- end -}}
