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
  AUTH_OAUTH_SSL_CERTIFICATE_VERIFY: "false"
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

{{- define "okdp-superset-wrapper.authRegistration" -}}
AUTH_USER_REGISTRATION = True
AUTH_ROLE_PUBLIC = "Public"
AUTH_USER_REGISTRATION_ROLE = "Public"
AUTH_ROLES_SYNC_AT_LOGIN = True
{{ end -}}

{{- define "okdp-superset-wrapper.rolesMapping" -}}
AUTH_ROLES_MAPPING = {
{{- range $oidcRole, $supersetRoles := .Values.oidcRoleMapping | default dict }}
  {{ $oidcRole | quote }}: {{ $supersetRoles | toJson }},
{{- end }}
}
{{ end -}}

{{- define "okdp-superset-wrapper.featureFlags" -}}
# https://github.com/apache/superset/blob/master/RESOURCES/FEATURE_FLAGS.md
FEATURE_FLAGS = {
  "DASHBOARD_RBAC": True,
  "EMBEDDED_SUPERSET": True,
  "EMBEDDABLE_CHARTS": True,
  "ENABLE_TEMPLATE_PROCESSING": True,
  "DASHBOARD_NATIVE_FILTERS": True,
  "DASHBOARD_CROSS_FILTERS": True,
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

{{/* Session cookie expiry (FLASK_APP_MUTATOR). Formerly in OKDP's wrapper chart. */}}
{{- define "okdp-superset-wrapper.sessionConfig" -}}
# https://superset.apache.org/docs/configuration/configuring-superset/

from flask import session
from flask import Flask

def make_session_permanent():
    '''
    Enable maxAge for the cookie 'session'
    '''
    session.permanent = True

def FLASK_APP_MUTATOR(app: Flask) -> None:
    app.before_request_funcs.setdefault(None, []).append(make_session_permanent)
{{ end -}}

{{/* OAuth2 sign-in: the keycloak (and dex) providers, read from the <release>-oauth2-env Secret and the client credentials. Formerly in OKDP's wrapper chart. */}}
{{- define "okdp-superset-wrapper.oauthEnabled" -}}
import os

AUTH_OAUTH_ENABLED = eval(os.environ["AUTH_OAUTH_ENABLED"].title())
if AUTH_OAUTH_ENABLED:
  from flask_appbuilder.security.manager import AUTH_OAUTH

  oauth2_providers = [
      {   'name':'dex',
          'token_key':'access_token',
          'icon':'fa-address-card',
          'remote_app': {
              'client_id': os.environ["AUTH_OAUTH_CLIENT_ID"],
              'client_secret': os.environ["AUTH_OAUTH_CLIENT_SECRET"],
              'client_kwargs':{
                  'scope': os.environ["AUTH_OAUTH_SCOPE"],
                  'verify': eval(os.environ["AUTH_OAUTH_SSL_CERTIFICATE_VERIFY"].title()),
                  'code_challenge_method': os.environ["AUTH_OAUTH_USE_PKCE"]
              },
              'api_base_url': '%s/' % os.environ["AUTH_OAUTH_BASE_URL"],
              'access_token_url': '%s/token' % os.environ["AUTH_OAUTH_BASE_URL"],
              'authorize_url': '%s/auth' % os.environ["AUTH_OAUTH_BASE_URL"],
              'jwks_uri': '%s/keys' % os.environ["AUTH_OAUTH_BASE_URL"],
              'redirect_uri': 'https://%s/oauth-authorized/dex' % os.environ["SUPERSET_DOMAIN"],
          }
      },
      {   'name':'keycloak',
          'token_key':'access_token',
          'icon':'fa-key',
          'remote_app': {
              'client_id': os.environ["AUTH_OAUTH_CLIENT_ID"],
              'client_secret': os.environ["AUTH_OAUTH_CLIENT_SECRET"],
              'client_kwargs':{
                  'scope': os.environ["AUTH_OAUTH_SCOPE"],
                  'verify': eval(os.environ["AUTH_OAUTH_SSL_CERTIFICATE_VERIFY"].title()),
                  'code_challenge_method': os.environ["AUTH_OAUTH_USE_PKCE"]
              },
              'api_base_url': '%s/' % os.environ["AUTH_OAUTH_BASE_URL"],
              'access_token_url': '%s/token' % os.environ["AUTH_OAUTH_BASE_URL"],
              'authorize_url': '%s/auth' % os.environ["AUTH_OAUTH_BASE_URL"],
              'jwks_uri': '%s/certs' % os.environ["AUTH_OAUTH_BASE_URL"],
              'redirect_uri': 'https://%s/oauth-authorized/keycloak' % os.environ["SUPERSET_DOMAIN"],
          }
      }
  ]
  AUTH_OAUTH_PROVIDER = os.environ["AUTH_OAUTH_PROVIDER"]
  OAUTH_PROVIDERS = list(filter(lambda e: e['name'] == AUTH_OAUTH_PROVIDER, oauth2_providers))
  AUTH_TYPE = AUTH_OAUTH
{{ end -}}

{{/* OAuth2 of the Trino datasources (<release>-trino-oauth2-env). Formerly in OKDP's wrapper chart. */}}
{{- define "okdp-superset-wrapper.trinoOauthEnabled" -}}
import os

TRINO_OAUTH_ENABLED = eval(os.environ["TRINO_OAUTH_ENABLED"].title())
if TRINO_OAUTH_ENABLED:
  superset_domain = os.environ["SUPERSET_DOMAIN"].strip().strip("/")
  redirect_uri = f"https://{superset_domain}/api/v1/database/oauth2/"

  DATABASE_OAUTH2_REDIRECT_URI = redirect_uri
  DATABASE_OAUTH2_CLIENTS = {
    "Trino": {
        "id": os.environ["TRINO_OAUTH_CLIENT_ID"],
        "secret": os.environ["TRINO_OAUTH_CLIENT_SECRET"],
        "scope": os.getenv("TRINO_OAUTH_SCOPE", "openid profile email groups"),
        "authorization_request_uri": f'{os.environ["TRINO_AUTH_OAUTH_BASE_URL"].rstrip("/")}/auth',
        "token_request_uri": f'{os.environ["TRINO_AUTH_OAUTH_BASE_URL"].rstrip("/")}/token',
    }
  }
{{ end -}}

{{/* User info and role keys of the keycloak and dex providers. Formerly in OKDP's wrapper chart. */}}
{{- define "okdp-superset-wrapper.securityManager" -}}
# https://superset.apache.org/docs/configuration/configuring-superset/#custom-oauth2-configuration
import logging as log
from superset.security import SupersetSecurityManager

class CustomSsoSecurityManager(SupersetSecurityManager):

    def oauth_user_info(self, provider, response=None):
        log.info("Oauth2 provider: {0}.".format(provider))
        if provider == 'dex':
            # As example, this line request a GET to base_url + '/' + userDetails with Bearer  Authentication,
            # and expects that authorization server checks the token, and response with user details
            me = self.appbuilder.sm.oauth_remotes[provider].get('userinfo').json()
            log.info("Received userinfo {0} from oidc provider {1}".format(me, provider))
            userinfo = {
                  'username': me.get('preferred_username', me.get('email', me.get('name', ''))),
                  'first_name': me.get('given_name', ''),
                  'last_name': me.get('family_name', ''),
                  'name': me.get('name', ''),
                  'email': me.get('email', ''),
                  'sub': me.get('sub', ''),
                  'groups': me.get('groups', []),
                  'role_keys': me.get('groups', []),
            }
            log.info("Effective role mapping: {0}".format(userinfo))
            return userinfo
        elif provider == 'keycloak':
            # As example, this line request a GET to base_url + '/' + userDetails with Bearer  Authentication,
            # and expects that authorization server checks the token, and response with user details
            me = self.appbuilder.sm.oauth_remotes[provider].get('userinfo').json()
            log.info("Received userinfo {0} from oidc provider {1}".format(me, provider))
            userinfo = {
                'username' : me.get('preferred_username', ''),
                'first_name': me.get('given_name', ''),
                'last_name': me.get('family_name', ''),
                'name': me.get('name', ''),
                'email' : me.get('email', ''),
                'sub' : me.get('sub', ''),
                'groups': me.get('groups', []),
                'role_keys': me.get('roles', []) + me.get('groups', [])
            }
            log.info("Effective role mapping: {0}".format(userinfo))
            return userinfo
        else:
            return {}

CUSTOM_SECURITY_MANAGER = CustomSsoSecurityManager
{{ end -}}

{{/* Examples database (SQLALCHEMY_EXAMPLES_URI of <release>-superset-env). Formerly in OKDP's wrapper chart. */}}
{{- define "okdp-superset-wrapper.loadExamples" -}}
import os
sqlalchemy_examples_uri = os.path.expandvars(os.getenv('SQLALCHEMY_EXAMPLES_URI', ''))
if sqlalchemy_examples_uri:
  SQLALCHEMY_EXAMPLES_URI = sqlalchemy_examples_uri
{{ end -}}

{{/*
The Valkey password of the async queries backends: the Apache chart writes
the value of cache.password there, the password is only in the environment.
*/}}
{{- define "okdp-superset-wrapper.valkeyPassword" -}}
GLOBAL_ASYNC_QUERIES_CACHE_BACKEND["CACHE_REDIS_PASSWORD"] = env("REDIS_PASSWORD", "")
GLOBAL_ASYNC_QUERIES_RESULTS_BACKEND["password"] = env("REDIS_PASSWORD", "")
{{ end -}}

{{/*
A wait init container of the Superset pods: the Apache default, reading the
database (and cache) host and port from the env Secrets.
Takes {ctx, name, redis}.
*/}}
{{- define "okdp-superset-wrapper.waitContainer" -}}
{{- $ctx := .ctx -}}
name: {{ .name }}
image: "{{ "{{" }} .Values.image.repository {{ "}}" }}:{{ "{{" }} .Values.image.tag | default .Chart.AppVersion {{ "}}" }}"
imagePullPolicy: "{{ "{{" }} .Values.image.pullPolicy {{ "}}" }}"
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
{{- $oauthSecret := include "okdp-superset-wrapper.oauthSecret" . -}}
{{- $trinoOauthSecret := include "okdp-superset-wrapper.trinoOauthSecret" . -}}
{{- if $oidc.dcr.enabled -}}
  {{- $oauthSecret = include "okdp-superset-wrapper.dcrSecret" . -}}
  {{- $trinoOauthSecret = $oauthSecret -}}
{{- end -}}
{{- $meta := $in.metadataDb -}}
{{- $ex := $in.examplesDb -}}
{{- $okdp := .Values.global.okdp -}}
fullnameOverride: {{ $fullname }}
image:
  repository: quay.io/okdp/superset
  tag: 6.0.0
  pullPolicy: IfNotPresent
supersetWebsockets:
  image:
    repository: quay.io/okdp/superset
    tag: 6.0.0-websocket
    pullPolicy: IfNotPresent

# The env Secrets of templates/env-secrets.yaml. The chart's own
# <release>-env Secret (database and cache settings from values) is not used.
secretEnv:
  create: false
envFromSecret: {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" . "suffix" "superset-env") }}
envFromSecrets:
  - {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" . "suffix" "db-env") }}
  - {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" . "suffix" "oauth2-env") }}
  - {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" . "suffix" "redis-env") }}
  - {{ include "okdp-superset-wrapper.envSecret" (dict "ctx" . "suffix" "trino-oauth2-env") }}

# Appended to superset_config.py, sorted by key.
configOverrides:
  auth_registration: {{ include "okdp-superset-wrapper.authRegistration" . | quote }}
  oauth_to_superset_roles_mapping: {{ include "okdp-superset-wrapper.rolesMapping" . | quote }}
  extra_config: {{ include "okdp-superset-wrapper.extraConfig" . | quote }}
  feature_flags: {{ include "okdp-superset-wrapper.featureFlags" . | quote }}
  session_config: {{ include "okdp-superset-wrapper.sessionConfig" . | quote }}
  oauth_enabled: {{ include "okdp-superset-wrapper.oauthEnabled" . | quote }}
  trino_oauth_enabled: {{ include "okdp-superset-wrapper.trinoOauthEnabled" . | quote }}
  custom_sso_security_manager: {{ include "okdp-superset-wrapper.securityManager" . | quote }}
  load_examples: {{ include "okdp-superset-wrapper.loadExamples" . | quote }}
  valkey_password: {{ include "okdp-superset-wrapper.valkeyPassword" . | quote }}

# The cache and Celery broker of templates/valkey.yaml. Its password is read
# from REDIS_PASSWORD at runtime (never a value): the URLs are built from the
# environment; RESULTS_BACKEND is given as code, and valkey_password above
# completes the async queries backends.
cache:
  host: {{ include "okdp-superset-wrapper.redis" . | quote }}
  port: 6379
  cacheDb: 1
  celeryDb: 0
  defaultTimeout: 300
config:
  resultsBackend: "RedisCache(host=env('REDIS_HOST'), password=env('REDIS_PASSWORD'), port=int(env('REDIS_PORT', '6379')), key_prefix='superset_results')"

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
              "verify": false
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
postgresql:
  # An external database (metadataDb).
  enabled: false
redis:
  # templates/valkey.yaml replaces the bundled bitnami redis.
  enabled: false
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
  createAdmin: false
  loadExamples: {{ .Values.load_examples }}
  {{- if not $oidc.enabled }}
  command:
    - /bin/sh
    - -c
    - |
      . {{ "{{" }} .Values.configMountPath {{ "}}" }}/superset_bootstrap.sh
      . {{ "{{" }} .Values.configMountPath {{ "}}" }}/superset_init.sh
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

# forceReload stamps the pods with randAlphaNum: never set (okdp-guard-allow.yaml).
# The wait init containers read the host and port of the database and the
# cache from the env Secrets (the Apache defaults read envFromSecret).
supersetWorker:
  forceReload: false
  initContainers:
    - {{ include "okdp-superset-wrapper.waitContainer" (dict "ctx" . "name" "wait-for-postgres-redis" "redis" true) | nindent 6 }}
supersetCeleryBeat:
  forceReload: false
supersetMcp:
  forceReload: false

supersetNode:
  forceReload: false
  initContainers:
    - {{ include "okdp-superset-wrapper.waitContainer" (dict "ctx" . "name" "wait-for-postgres" "redis" false) | nindent 6 }}
  resources:
    limits:
      memory: {{ printf "%vGi" .Values.memoryGi | quote }}
      cpu: {{ .Values.cpu | quote }}

ingress:
  enabled: true
  ingressClassName: {{ $okdp.ingress.className }}
  annotations:
    kubernetes.io/ingress.class: {{ $okdp.ingress.className }}
    {{- include "okdp.ingressAnnotations" . | nindent 4 }}
    acme.cert-manager.io/http01-edit-in-place: "true"
    ## Extend timeout to allow long running queries.
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "128k"
  path: /
  pathType: ImplementationSpecific
  hosts:
    - {{ $in.host }}
  tls:
    - hosts:
        - {{ $in.host }}
      secretName: {{ printf "%s-tls-secret" $release }}

extraVolumes:
  - name: cacerts
    secret:
      secretName: certs-bundle

extraVolumeMounts:
  - name: cacerts
    mountPath: /cacerts
{{- end -}}

{{/* Module oidc-dcr: registers the OAuth client (clientProvisioning: dcr). */}}
{{- define "okdp-superset-wrapper.values.dcr" -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- if ne ($oidc.dcr.authMethod | default "") "anonymous" -}}
  {{- fail (printf "superset: global.okdp.oidc.dcr.authMethod %q is not supported: this chart registers anonymously" ($oidc.dcr.authMethod | default "")) -}}
{{- end -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "oidc.dcr.registrationUrl")) -}}
{{- $host := include "okdp.ingressHost" . -}}
ttl_seconds: 30
registration_url: {{ $oidc.dcr.registrationUrl | quote }}
request:
  application_type: web
  client_name: {{ printf "%s-%s" .Release.Name .Release.Namespace | quote }}
  redirect_uris:
    # Sign-in (AUTH_OAUTH_PROVIDER) and the OAuth2 of the Trino datasources.
    - {{ printf "https://%s/oauth-authorized/%s" $host ($oidc.displayName | default "keycloak") | quote }}
    - {{ printf "https://%s/api/v1/database/oauth2/" $host | quote }}
  grant_types:
    - authorization_code
    - refresh_token
  # openid is not a Keycloak client scope: Keycloak refuses it here.
  scope: {{ without (splitList " " $oidc.scope) "openid" | join " " | quote }}
tls:
  insecure: false
  certificate: certs-bundle
secret: {{ include "okdp-superset-wrapper.dcrSecret" . }}
mapping:
  use_default: false
  key_mapping:
    client_id: ".client_id"
    client_secret: ".client_secret"
{{- end -}}
