#!/usr/bin/env bash
#
# Copyright 2026 The OKDP Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Prints the values each vendored upstream chart of a wrapper chart is
# rendered with: the values.yaml of the values ConfigMaps okdp.vendor.render
# emits (okdp-lib-chart >= the release carrying them), from an offline
# `helm template`. Vendored defaults, computed values, instance `upstream`
# values and global, merged: what a plain Helm install of the upstream chart
# would take as values.yaml.
#
#   scripts/show-values.sh [options] <chart dir> [helm template args...]
#
#   --release NAME     release name (default demo-<chart>; names derive from it)
#   --namespace NS     namespace (default demo)
#   --only NAME        one render only, as bare YAML (pipe it to diff): the
#                      ConfigMap name (<release>-<chart>-values) or the
#                      vendored chart name when the release renders it once
#
# Run `helm dependency build` and scripts/vendor-charts.sh on the chart first.
#
#   scripts/show-values.sh charts/services/trino -f charts/services/trino/ci/opa-opal-values.yaml
#   scripts/show-values.sh --only trino charts/services/trino -f a.yaml > a.out
#   diff <(scripts/show-values.sh --only trino charts/services/trino -f a.yaml) \
#        <(scripts/show-values.sh --only trino charts/services/trino -f b.yaml)
set -euo pipefail

usage() { sed -n '/^#   scripts\/show-values.sh \[/,/^# Run/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

release="" namespace=demo only=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) release=${2:?}; shift 2 ;;
    --namespace) namespace=${2:?}; shift 2 ;;
    --only) only=${2:?}; shift 2 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) break ;;
  esac
done
[[ $# -gt 0 ]] || usage
chart=$1; shift
[[ -f "${chart}/Chart.yaml" ]] || { echo "error: ${chart}: no Chart.yaml" >&2; exit 2; }
command -v yq >/dev/null || { echo "error: yq (mikefarah) is required" >&2; exit 2; }
release=${release:-demo-$(yq '.name' "${chart}/Chart.yaml")}

rendered=$(helm template "${release}" "${chart}" --namespace "${namespace}" "$@" 2> >(grep -v 'failed to load plugins' >&2))
# One JSON line per values ConfigMap: {name, chart, version, values}.
maps=$(yq -o=json -I=0 'select(.kind == "ConfigMap" and .metadata.labels["okdp.io/vendor-values"] != null)
  | {"name": .metadata.name, "chart": .metadata.labels["okdp.io/vendor-values"],
     "version": .metadata.annotations["okdp.io/vendor-chart"], "values": .data["values.yaml"]}' <<<"${rendered}")
if [[ -z "${maps}" ]]; then
  echo "error: ${chart}: no values ConfigMap rendered (okdp-lib-chart too old, or global.okdp.vendor.valuesConfigMap: false)" >&2
  exit 1
fi

if [[ -n "${only}" ]]; then
  match=$(jq -c --arg o "${only}" 'select(.name == $o)' <<<"${maps}")
  [[ -n "${match}" ]] || match=$(jq -c --arg o "${only}" 'select(.chart == $o)' <<<"${maps}")
  case $(grep -c . <<<"${match}" || true) in
    0) echo "error: no render '${only}'; renders:" >&2; jq -r '"  \(.name) (\(.chart))"' <<<"${maps}" >&2; exit 1 ;;
    1) jq -r '.values' <<<"${match}" ;;
    *) echo "error: '${only}' is rendered more than once; pick a ConfigMap name:" >&2
       jq -r '"  \(.name)"' <<<"${match}" >&2; exit 1 ;;
  esac
else
  jq -r '"---\n# \(.name): values of \(.version)\n\(.values)"' <<<"${maps}"
fi
