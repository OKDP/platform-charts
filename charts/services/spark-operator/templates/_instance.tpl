{{/* Descriptor hooks (okdp-lib-chart): no UI, no output. The former package usage. */}}
{{- define "okdp.instance.usage" -}}
Spark Operator has been deployed successfully.

The operator manages SparkApplication custom resources in
{{- if and .Values.jobNamespaces (not (has "" .Values.jobNamespaces)) }} the namespaces {{ .Values.jobNamespaces | join ", " }}.
{{- else }} every namespace.
{{- end }}

To submit a Spark application:
1. Create a namespace for your Spark applications (e.g., spark-apps)
2. Create a ServiceAccount with appropriate RBAC permissions (the spark-rbac service)
3. Submit a SparkApplication manifest

Example SparkApplication:
```yaml
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: spark-pi
  namespace: spark-apps
spec:
  type: Scala
  mode: cluster
  image: "quay.io/okdp/spark-py:spark-3.5.6-python-3.11-scala-2.12-java-17"
  imagePullPolicy: Always
  mainClass: org.apache.spark.examples.SparkPi
  mainApplicationFile: "local:///opt/spark/examples/jars/spark-examples_2.12-3.5.6.jar"
  sparkVersion: "3.5.6"
  restartPolicy:
    type: Never
  driver:
    cores: 1
    coreLimit: "1200m"
    memory: "512m"
    serviceAccount: spark
  executor:
    cores: 1
    instances: 2
    memory: "512m"
```

Monitor your application using:
kubectl get sparkapplications -n spark-apps
kubectl describe sparkapplication spark-pi -n spark-apps
{{- end -}}
