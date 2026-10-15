# spark-rbac

OKDP package of the ServiceAccount and RBAC (Role `spark-role`, RoleBinding
`spark-rolebinding`) the Spark jobs of a namespace run with. The RoleBinding
also binds the group `system:serviceaccounts:<namespace>`, so Airflow tasks can
manage SparkApplications.

A package in the okdp-compiler format: `values.cel.yaml` computes the values
of the upstream chart `oci://quay.io/okdp/charts/spark-rbac` 1.0.1, the
dependency of `Chart.yaml`, from the parameters below
(`config.schema.json`). The console parameters are flat (`rbacCreate`) while
the upstream keys are nested (`rbac.create`): the mapping renames them.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `rbacCreate` | `true` | Create the Role and RoleBinding. |
| `serviceAccountCreate` | `true` | Create the ServiceAccount. |
| `serviceAccountName` | `spark` | ServiceAccount name (created or existing). |
| `automountServiceAccountToken` | `true` | Mount the ServiceAccount token. |

No platform value is read. No provided connection, no UI.

## Upstream values

Any value of the `spark-rbac` chart can be set per instance, under
`upstream.spark-rbac`, merged over the values computed from the parameters
(`upstream` in `okdp.yaml`):

```yaml
upstream:
  spark-rbac:
    serviceAccount:
      annotations: {eks.amazonaws.com/role-arn: arn:aws:iam::111122223333:role/spark}
    rbac:
      annotations: {example.org/owner: data-team}
```

`serviceAccount.name` is refused (`protect`): it is the `serviceAccountName`
parameter, which `okdp.instance.yaml` publishes to the Spark jobs. An
upstream value wins over the parameter it overlaps
(`serviceAccount.automount` over `automountServiceAccountToken`). No key or
value may contain `{{` (the schema and okdp-compile both refuse it).

## Notes

- The Role and RoleBinding names are fixed by the upstream chart
  (`spark-role`, `spark-rolebinding`): one instance per namespace, as before.

## Tests

```sh
scripts/compile-charts.sh catalog/spark-rbac/1.0.1-1.0.0   # compile, check and render ci/*-values.yaml
```
