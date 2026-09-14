# spark-rbac

OKDP chart of the ServiceAccount and RBAC (Role `spark-role`, RoleBinding
`spark-rolebinding`) the Spark jobs of a namespace run with. The RoleBinding
also binds the group `system:serviceaccounts:<namespace>`, so Airflow tasks can
manage SparkApplications.

It renders the upstream chart `oci://quay.io/okdp/charts/spark-rbac` 1.0.1,
vendored under `vendor/` (see `vendor.yaml`), with values computed from the
parameters below (`templates/_values.tpl`). It is vendored rather than a plain
dependency because the console parameters are flat (`rbacCreate`) while the
upstream keys are nested (`rbac.create`): a dependency only takes static
values under its own keys, which would have renamed every parameter.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `rbacCreate` | `true` | Create the Role and RoleBinding. |
| `serviceAccountCreate` | `true` | Create the ServiceAccount. |
| `serviceAccountName` | `spark` | ServiceAccount name (created or existing). |
| `automountServiceAccountToken` | `true` | Mount the ServiceAccount token. |

No platform value is read. No provided connection, no UI.

## Notes

- The Role and RoleBinding names are fixed by the upstream chart
  (`spark-role`, `spark-rolebinding`): one instance per namespace, as before.

## Tests

```sh
helm dependency build charts/services/spark-rbac
for f in charts/services/spark-rbac/ci/*-values.yaml; do
  helm lint charts/services/spark-rbac -f "$f"
  helm template demo-spark-rbac charts/services/spark-rbac -n demo -f "$f" >/dev/null
done
scripts/vendor-charts.sh --check charts/services/spark-rbac
```
