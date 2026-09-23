{{/*
Values of the vendored charts: the former KuboCD module `values:` templates,
with .Context -> .Values.global.okdp, .Parameters -> .Values and the storage
connection resolved by okdp.connection.
*/}}

{{/* Module spark-rbac: the spark ServiceAccount the notebooks run as. */}}
{{- define "okdp-jupyterhub.values.sparkRbac" -}}
rbac:
  create: true
serviceAccount:
  create: true
  name: spark
  automount: true
{{- end -}}

{{/*
Resolved PySpark connections, in the order of `pyspark`, as a YAML list of
{name, envPrefix, s3SecretRef, conf: [<spark conf line>]}. A name `pyspark`
lists without a matching sparkConnections item is skipped, as before.
*/}}
{{- define "okdp-jupyterhub.pyspark" -}}
{{- $s3 := include "okdp.connection" (dict "ctx" . "ref" .Values.storage "contract" "s3" "field" "storage") | fromYaml -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- $byName := dict -}}
{{- range $i, $c := .Values.sparkConnections | default list -}}
  {{- if not (and $c $c.name) -}}
    {{- fail (printf "jupyterhub: sparkConnections[%d]: name is required" $i) -}}
  {{- end -}}
  {{- $_ := set $byName $c.name $c -}}
{{- end -}}
{{- $out := list -}}
{{- range $name := .Values.pyspark | default list -}}
  {{- $c := index $byName $name -}}
  {{- if $c -}}
    {{- $prefix := upper (replace "." "_" (replace "-" "_" $name)) -}}
    {{- $secret := $c.s3SecretRef | default "" -}}
    {{- $props := include "okdp-jupyterhub.placeholders" (dict "ctx" $ "text" ($c.properties | default "")) -}}
    {{- $props = $props
          | replace "{{ connection.name }}" $name
          | replace "{{ storage.endpoints.api }}" (toString $s3.apiUrl)
          | replace "{{ storage.endpoints.apiUrl }}" (toString $s3.apiUrl)
          | replace "{{ storage.region }}" (toString $s3.region) -}}
    {{- if $secret -}}
      {{- $props = $props
            | replace "$(S3_ACCESS_KEY)" (printf "$(%s_S3_ACCESS_KEY)" $prefix)
            | replace "$(S3_SECRET_KEY)" (printf "$(%s_S3_SECRET_KEY)" $prefix) -}}
    {{- end -}}
    {{- $props = $props
          | replace "{{ idp.endpoints.token }}" (toString $oidc.tokenUrl)
          | replace "{{ idp.endpoints.tokenUrl }}" (toString $oidc.tokenUrl) -}}
    {{- $conf := list -}}
    {{- range $line := splitList "\n" $props -}}
      {{- if trim $line }}{{ $conf = append $conf (trim $line) }}{{ end -}}
    {{- end -}}
    {{- $out = append $out (dict "name" $name "envPrefix" $prefix "s3SecretRef" $secret "conf" $conf) -}}
  {{- end -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}

{{/* Module main: the jupyterhub chart. */}}
{{- define "okdp-jupyterhub.values.jupyterhub" -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "ingress.suffix" "ingress.className" "certificateIssuers.selfSigned.name" "storageClass.workspace" "oidc.authUrl" "oidc.tokenUrl" "oidc.userinfoUrl")) -}}
{{- if not .Values.s3SecretRef -}}
  {{- fail "jupyterhub: s3SecretRef is required: a Secret with the keys accessKey and secretKey, this instance's own S3 identity" -}}
{{- end -}}
{{- $okdp := .Values.global.okdp -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- $s3 := include "okdp.connection" (dict "ctx" . "ref" .Values.storage "contract" "s3" "field" "storage") | fromYaml -}}
{{- $namespace := .Release.Namespace -}}
{{- $release := .Release.Name -}}
{{- $url := include "okdp-jupyterhub.url" . -}}
{{- $host := include "okdp.ingressHost" . -}}
{{- $oauthSecret := include "okdp-jupyterhub.oauthSecret" . -}}
{{- $cryptKey := dict "name" $oauthSecret "key" "JUPYTERHUB_CRYPT_KEY" -}}
{{- if $oidc.dcr.enabled -}}
  {{- $oauthSecret = include "okdp-jupyterhub.dcrSecret" . -}}
  {{- $cryptKey = dict "name" (include "okdp-jupyterhub.hubGeneratedSecret" .) "key" "hub.config.CryptKeeper.keys" -}}
{{- end -}}
{{- $placeholder := include "okdp-jupyterhub.generatedPlaceholder" . -}}
{{- $pyspark := include "okdp-jupyterhub.pyspark" . | fromYamlArray -}}
{{- $welcome := include "okdp-jupyterhub.placeholders" (dict "ctx" . "text" (.Values.welcomeNotebook | default "")) -}}
{{- $welcome = $welcome | replace "{{ $jupyterUrl }}" $url | replace "{{ .Context.jupyterHub.endpoints.url }}" $url -}}
{{- $sparkDefaults := .Values.sparkDefaults | default dict -}}
{{- $generic := dict
      "login_service" ($oidc.displayName | default "keycloak")
      "oauth_callback_url" (printf "%s/hub/oauth_callback" $url)
      "authorize_url" $oidc.authUrl
      "token_url" $oidc.tokenUrl
      "userdata_url" $oidc.userinfoUrl
      "validate_server_cert" false
      "claim_groups_key" "groups"
      "manage_groups" true
      "userdata_params" (dict "state" "state")
      "username_key" "preferred_username"
      "scope" (splitList " " (include "okdp-jupyterhub.scope" .)) -}}
{{- $generic = mergeOverwrite $generic (deepCopy (.Values.oidcRoleMapping | default dict)) -}}
{{- $locations := list -}}
{{- range $l := .Values.fileBrowserLocations | default list -}}
  {{- if and $l.name $l.uri }}{{ $locations = append $locations (dict "name" $l.name "uri" $l.uri) }}{{ end -}}
{{- end -}}
# Resource names derive from the release name.
fullnameOverride: {{ $release | quote }}
nameOverride: {{ $release | quote }}

hub:
  resources:
    requests:
      cpu: "0.1"
      memory: "0.5Gi"
    limits:
      cpu: "1"
      memory: "1Gi"
  extraEnv:
    OAUTH_CLIENT_ID:
      valueFrom:
        secretKeyRef:
          name: {{ $oauthSecret }}
          key: client_id
    OAUTH_CLIENT_SECRET:
      valueFrom:
        secretKeyRef:
          name: {{ $oauthSecret }}
          key: client_secret
    JUPYTERHUB_CRYPT_KEY:
      valueFrom:
        secretKeyRef:
          name: {{ $cryptKey.name }}
          key: {{ $cryptKey.key }}
  config:
    # Placeholders: the chart would otherwise generate them with lookup +
    # randAlphaNum. The real values are in the ESO-generated Secret
    # (existingSecret below), and the hub pops these keys from hub.config.
    ConfigurableHTTPProxy:
      auth_token: {{ $placeholder }}
    CryptKeeper:
      keys:
        - {{ $placeholder }}
    # https://oauthenticator.readthedocs.io/en/latest/how-to/refresh.html
    JupyterHub:
      cookie_secret: {{ $placeholder }}
      hub_connect_url: {{ printf "http://%s-hub.%s.svc.cluster.local:8081" $release $namespace | quote }}
      authenticator_class: generic-oauth
      load_roles:
        - name: user
          scopes:
            - self
            - admin:auth_state!user
        - name: server
          scopes:
            - users:activity!user
            - access:servers!server
            - admin:auth_state!user
    Authenticator:
      auto_login: true
      enable_auth_state: true
      auth_refresh_age: 300
      refresh_pre_spawn: true
    GenericOAuthenticator:
      {{- toYaml $generic | nindent 6 }}
  # No JupyterHub service: their api tokens would be generated with lookup too.
  services: {}
  # The hub reads the generated cookie secret and auth-state keys from it
  # before its own Secret (z2jh get_secret_value).
  existingSecret: {{ include "okdp-jupyterhub.hubGeneratedSecret" . }}
  networkPolicy:
    enabled: false
  extraConfig:
    extraConfig01.py: |
      c.KubeSpawner.delete_grace_period = 120
      c.ServerApp.allow_root = True
  image:
    pullPolicy: Always
    pullSecrets: []
    name: quay.io/jupyterhub/k8s-hub
    tag: "4.4.2"
  db:
    type: sqlite-pvc
    pvc:
      storage: 1Gi
      storageClassName: {{ $okdp.storageClass.workspace | quote }}

rbac:
  create: true

cull:
  enabled: false

proxy:
  service:
    type: ClusterIP
  chp:
    resources:
      requests:
        cpu: "0.1"
        memory: "0.125Gi"
      limits:
        cpu: "1"
        memory: "0.5Gi"

ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    # Notebook saves ship their embedded outputs: the nginx 1m default
    # rejects them with a 413.
    nginx.ingress.kubernetes.io/proxy-body-size: "64m"
    {{- include "okdp.ingressAnnotations" . | nindent 4 }}
  ingressClassName: {{ $okdp.ingress.className }}
  hosts:
    - {{ $host }}
  tls:
    - secretName: {{ $release }}-tls
      hosts:
        - {{ $host }}

scheduling:
  userScheduler:
    enabled: false
  userPlaceholder:
    enabled: false

singleuser:
  # User pod names carry the release name: no conflict between instances.
  podNameTemplate: {{ printf "%s-{username}{servername}" $release | quote }}

  image:
    name: quay.io/okdp/jupyter/all-spark-notebook
    tag: "spark-3.5.6-python-3.11-java-17-scala-2.12"

  startTimeout: 600

  extraEnv:
    NB_USER: "$(JUPYTERHUB_USER)"
    NB_UID: "1001"
    NB_GID: "100"
    CHOWN_HOME: "yes"
    CHOWN_HOME_OPTS: "-R"
    JUPYTER_ENABLE_LAB: "yes"
    EDITOR: "vim"
    GIT_SSL_NO_VERIFY: "false"
    # Ignore InsecureRequestWarning warnings
    PYTHONWARNINGS: "ignore:Unverified HTTPS request"
    # The Spark images ship pyspark under SPARK_HOME rather than in
    # site-packages: overriding PYTHONPATH outright hides it, and the
    # PySpark kernel then fails on "No module named pyspark".
    PYTHONPATH: "/etc/jupyter/auth:/usr/local/spark/python:/usr/local/spark/python/lib/py4j-0.10.9.7-src.zip"
    AWS_CA_BUNDLE: /cacerts/ca.crt
    REQUESTS_CA_BUNDLE: /cacerts/ca.crt
    CURL_CA_BUNDLE: /cacerts/ca.crt
    SSL_CERT_FILE: /cacerts/ca.crt
    TRUSTSTORE_PASSWORD: ""

    # https://github.com/jpmorganchase/jupyter-fs
    FS_S3_ENDPOINT_URL: {{ $s3.apiUrl | quote }}
    FS_S3_ACCESS_KEY:
      valueFrom:
        secretKeyRef:
          name: {{ .Values.s3SecretRef | quote }}
          key: accessKey
    FS_S3_SECRET_KEY:
      valueFrom:
        secretKeyRef:
          name: {{ .Values.s3SecretRef | quote }}
          key: secretKey
    {{- range $c := $pyspark }}
    {{- if $c.s3SecretRef }}
    {{ $c.envPrefix }}_S3_ACCESS_KEY:
      valueFrom:
        secretKeyRef:
          name: {{ $c.s3SecretRef | quote }}
          key: accessKey
    {{ $c.envPrefix }}_S3_SECRET_KEY:
      valueFrom:
        secretKeyRef:
          name: {{ $c.s3SecretRef | quote }}
          key: secretKey
    {{- end }}
    {{- end }}

    # Notebook pod IP used by Spark driver (spark.driver.host) in client mode
    POD_IP:
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    {{- with include "okdp.proxy.env" . | fromYaml }}
    {{- toYaml . | nindent 4 }}
    {{- end }}

  {{- if $welcome }}
  lifecycleHooks:
    postStart:
      exec:
        command:
          - /bin/bash
          - -lc
          - |
            set -e
            HOME="/home/$JUPYTERHUB_USER"
            if [ ! -f "$HOME/Welcome.ipynb" ]; then
              cp /etc/jupyterhub/welcome/Welcome.ipynb "$HOME/Welcome.ipynb"
            fi

  defaultUrl: "/lab/tree/Welcome.ipynb"
  {{- end }}

  extraFiles:
    {{- if $welcome }}
    welcome-notebook:
      mountPath: /etc/jupyterhub/welcome/Welcome.ipynb
      stringData: {{ trim $welcome | quote }}
    {{- end }}

    jupyter_server_config_py:
      mountPath: /etc/jupyter/jupyter_server_config.py
      stringData: |
        c.ServerApp.contents_manager_class = "jupyterfs.MetaManager"
        c.ServerApp.jpserver_extensions = {"jupyterfs.extension": True}

        file_browser_locations = {{ $locations | toJson }}

        import os

        c.JupyterFs.resources = [{
          "name": loc["name"],
          "url": loc["uri"],
          "type": "fsspec",
          "defaultWritable": True,
          "use_listings_cache": False,
          "auth": "none",
          "kwargs": {
            "key": os.environ["FS_S3_ACCESS_KEY"],
            "secret": os.environ["FS_S3_SECRET_KEY"],
            "client_kwargs": {
              "endpoint_url": os.environ["FS_S3_ENDPOINT_URL"],
              "verify": os.environ["AWS_CA_BUNDLE"],
            },
          },
         }
         for loc in file_browser_locations
        ]

    notebook_oauth2:
      mountPath: /etc/jupyter/auth/sitecustomize.py
      stringData: |
        import builtins
        import os
        import requests

        def _fresh_access_token():
          hub_token = os.environ["JUPYTERHUB_API_TOKEN"]
          hub_api_url = os.environ["JUPYTERHUB_API_URL"]
          user = os.environ["JUPYTERHUB_USER"]

          r = requests.get(
            f"{hub_api_url}/users/{user}",
            headers={"Authorization": f"Bearer {hub_token}"},
            timeout=10,
          )
          r.raise_for_status()

          data = r.json()
          auth_state = data.get("auth_state")
          if auth_state is None:
            raise RuntimeError(f"auth_state is null for user {user}")
          token = auth_state.get("access_token")
          if not token:
            raise RuntimeError(f"No access_token in auth_state. Keys: {list(auth_state.keys())}")
          return token

        def _current_user():
          user = os.environ.get("JUPYTERHUB_USER")
          if not user:
            raise RuntimeError("JUPYTERHUB_USER is not set")
          return user

        builtins.access_token = _fresh_access_token
        builtins.me = _current_user

  cpu:
    limit: {{ mulf (float64 .Values.cpu) 2 }}
    guarantee: {{ .Values.cpu }}
  memory:
    limit: {{ printf "%vG" (mulf (float64 .Values.memoryGi) 2) | quote }}
    guarantee: {{ printf "%vG" .Values.memoryGi | quote }}

  profileList:
    - display_name: "📊 Scientific Python"
      description: "Includes Git, Pandas, NumPy, S3 browser, and Trino SQL support."
      kubespawner_override:
        image: quay.io/okdp/jupyter/scipy-notebook:python-3.12.12-hub-5.4.2-lab-4.5.0
        image_pull_policy: Always
    - display_name: "📊 Data Science"
      description: "Includes Git, Pandas, NumPy, S3 browser, and Trino SQL support, Matplotlib, R, and Julia"
      kubespawner_override:
        image: quay.io/okdp/jupyter/datascience-notebook:python-3.12.12-hub-5.4.2-lab-4.5.0
        image_pull_policy: Always
    - display_name: "🔥 PySpark"
      description: "Apache Spark big data processing"
      default: true
      kubespawner_override:
        image_pull_policy: Always
        environment:
          # Platform defaults every notebook job inherits. A job overrides
          # them in its own SparkSession builder.
          PYSPARK_SUBMIT_ARGS: {{ include "okdp-jupyterhub.pysparkSubmitArgs" (dict "ctx" . "pyspark" $pyspark "sparkDefaults" $sparkDefaults) | quote }}
      profile_options:
        image:
          display_name: "Select PySpark kernel version"
          choices:
            spark344:
              display_name: "PySpark 3.4.4 / Python 3.11"
              kubespawner_override:
                image: quay.io/okdp/jupyter/all-spark-notebook:spark-3.4.4-python-3.11-java-17-scala-2.12
                image_pull_policy: Always
                environment:
                  SPARK_EXECUTOR_IMAGE: quay.io/okdp/spark-py:spark-3.4.4-python-3.11-scala-2.12-java-17
            spark356:
              display_name: "PySpark 3.5.6 / Python 3.11"
              default: true
              kubespawner_override:
                image: quay.io/okdp/jupyter/all-spark-notebook:spark-3.5.6-python-3.11-java-17-scala-2.12
                image_pull_policy: Always
                environment:
                  SPARK_EXECUTOR_IMAGE: quay.io/okdp/spark-py:spark-3.5.6-python-3.11-scala-2.12-java-17

  serviceAccountName: spark
  storage:
    homeMountPath: "/home/{username}"
    dynamic:
      storageClass: standard
      # PVC and volume names carry the release name: no conflict between instances.
      pvcNameTemplate: {{ printf "%s-claim-{username}{servername}" $release | quote }}
      volumeNameTemplate: {{ printf "%s-volume-{username}{servername}" $release | quote }}
    type: dynamic
    extraVolumes:
      - name: cacerts
        secret:
          secretName: certs-bundle
    extraVolumeMounts:
      - name: cacerts
        mountPath: /cacerts
        readOnly: true
  cloudMetadata:
    blockWithIptables: false
  uid: 0
  fsGid: 100
  extraPodConfig:
    automount_service_account_token: true
    terminationGracePeriodSeconds: 120
  networkPolicy:
    enabled: false
prePuller:
  hook:
    enabled: false
  continuous:
    enabled: false
{{- end -}}

{{/*
PYSPARK_SUBMIT_ARGS of the PySpark profile: the platform defaults, the
sparkDefaults, then the conf lines of every enabled PySpark connection.
Takes a dict {ctx, pyspark, sparkDefaults}.
*/}}
{{- define "okdp-jupyterhub.pysparkSubmitArgs" -}}
{{- $ctx := .ctx -}}
{{- $ns := $ctx.Release.Namespace -}}
{{- $args := list
      "--master k8s://https://kubernetes.default.svc.cluster.local"
      "--conf spark.submit.deployMode=client"
      "--conf spark.driver.host=$(POD_IP)"
      "--conf spark.kubernetes.driverEnv.SPARK_USER=$(NB_USER)"
      "--conf spark.executorEnv.SPARK_USER=$(NB_USER)"
      "--conf spark.kubernetes.container.image=$(SPARK_EXECUTOR_IMAGE)"
      "--conf spark.kubernetes.executor.secrets.certs-bundle=/cacerts"
      "--conf \"spark.driver.extraJavaOptions=-Djavax.net.ssl.trustStore=/cacerts/bundle.p12 -Djavax.net.ssl.trustStoreType=PKCS12 -Djavax.net.ssl.trustStorePassword=\""
      "--conf \"spark.executor.extraJavaOptions=-Djavax.net.ssl.trustStore=/cacerts/bundle.p12 -Djavax.net.ssl.trustStoreType=PKCS12 -Djavax.net.ssl.trustStorePassword=\""
      (printf "--conf spark.kubernetes.namespace=%s" $ns)
      "--conf spark.eventLog.compress=true"
      "--conf spark.eventLog.rolling.enabled=true"
      "--conf spark.network.timeout=600" -}}
{{- range $key := keys .sparkDefaults | sortAlpha -}}
  {{- $v := include "okdp-jupyterhub.placeholders" (dict "ctx" $ctx "text" (printf "%v" (index $.sparkDefaults $key))) | replace "NAMESPACE" $ns -}}
  {{- $args = append $args (printf "--conf %s" (printf "%s=%s" $key $v | quote)) -}}
{{- end -}}
{{- $args = append $args "--conf spark.kubernetes.authenticate.serviceAccountName=spark" -}}
{{- range $c := .pyspark -}}
  {{- range $line := $c.conf -}}
    {{- $args = append $args (printf "--conf %s" (quote $line)) -}}
  {{- end -}}
{{- end -}}
{{- $args = append $args "pyspark-shell" -}}
{{- join " " $args -}}
{{- end -}}

{{/* Module oidc-dcr: registers the OAuth client (clientProvisioning: dcr). */}}
{{- define "okdp-jupyterhub.values.dcr" -}}
{{- $oidc := include "okdp.oidc" . | fromYaml -}}
{{- if ne ($oidc.dcr.authMethod | default "") "anonymous" -}}
  {{- fail (printf "jupyterhub: global.okdp.oidc.dcr.authMethod %q is not supported: this chart registers anonymously" ($oidc.dcr.authMethod | default "")) -}}
{{- end -}}
{{- include "okdp.require" (dict "ctx" . "keys" (list "oidc.dcr.registrationUrl")) -}}
ttl_seconds: 30
registration_url: {{ $oidc.dcr.registrationUrl | quote }}
request:
  application_type: web
  client_name: {{ printf "%s-%s" .Release.Name .Release.Namespace | quote }}
  redirect_uris:
    - {{ printf "%s/hub/oauth_callback" (include "okdp-jupyterhub.url" .) | quote }}
  grant_types:
    - authorization_code
    - refresh_token
  # openid is not a Keycloak client scope: Keycloak refuses it here.
  scope: {{ without (splitList " " (include "okdp-jupyterhub.scope" .)) "openid" | join " " | quote }}
tls:
  insecure: false
  certificate: certs-bundle
secret: {{ include "okdp-jupyterhub.dcrSecret" . }}
mapping:
  use_default: false
  key_mapping:
    client_id: ".client_id"
    client_secret: ".client_secret"
{{- end -}}
