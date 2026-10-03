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

## Upstream values

Any value of the vendored `spark-rbac` chart can be set per instance under
`upstream.spark-rbac`, merged over the values computed from the parameters
(okdp-lib-chart `okdp.vendor.render`, option `upstream`):

```yaml
upstream:
  spark-rbac:
    serviceAccount:
      annotations: {eks.amazonaws.com/role-arn: arn:aws:iam::111122223333:role/spark}
    rbac:
      annotations: {example.org/owner: data-team}
```

`serviceAccount.name` is refused: it is the `serviceAccountName` parameter,
which the descriptor publishes to the Spark jobs (see `okdp-spark-rbac.upstream`
in `templates/_values.tpl`). An upstream value wins over the parameter it
overlaps (`serviceAccount.automount` over `automountServiceAccountToken`). No
key or value may contain `{{` (the schema and okdp-lib-chart both refuse it).

## Notes

- The Role and RoleBinding names are fixed by the upstream chart
  (`spark-role`, `spark-rolebinding`): one instance per namespace, as before.

## Tests

```sh
scripts/vendor-charts.sh charts/services/spark-rbac   # download vendor/ (not committed)
helm dependency build charts/services/spark-rbac
for f in charts/services/spark-rbac/ci/*-values.yaml; do
  helm lint charts/services/spark-rbac -f "$f"
  helm template demo-spark-rbac charts/services/spark-rbac -n demo -f "$f" >/dev/null
done
```
