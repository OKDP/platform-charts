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
# Compiles the test cases of catalog packages (okdp-compiler format), checks
# them against the upstream charts, and renders them with Helm.
# This is the canonical copy (OKDP/platform-charts): the copies in other
# OKDP catalog repositories must stay byte-identical to it.
#
#   scripts/compile-charts.sh catalog/<service>/<version>...
#
# A package is a version directory of the catalog: its Chart.yaml names the
# service and the version of its directories. Its test cases, in ci/:
#
#   <case>-values.yaml       an instance's values (-f). A first line
#                            "# error: <message>" makes it a case that must
#                            fail with that message (compile, or check).
#   platform.yaml            the platform values of every case (--context,
#                            level 0), when the package has the file
#   <case>-platform.yaml     the case's own platform values, after it
#                            (--context, level 0)
#   <case>-connections.yaml  the case's own connections (--context 2:)
#
# Each case is compiled under the release demo-<service> in the namespace
# demo, into $OUT/<service>/<case>/ (okdp-compile -o: the umbrella chart, its
# values and OKDP's objects), then:
#
#   1. checked: okdp-compile --check --charts $OKDP_CHARTS, the final values
#      against each upstream chart's defaults and values.schema.json. A chart
#      the cache lacks (a dependency of Chart.yaml, the platform's oidc-dcr
#      chart in dcr mode) is pulled into it with the helm pull --untar
#      command okdp-compile names, then the check runs again;
#   2. rendered: helm dependency build, then helm template of the umbrella,
#      in a copy of the directory, into $OUT/<service>/<case>.yaml.
#
# Environment:
#   OKDP_COMPILE    the okdp-compile binary (default: okdp-compile in PATH)
#   OKDP_CONTRACTS  the contract schemas (default: contracts/ of this repository)
#   OKDP_CHARTS     the chart cache of the checks (default: ~/.cache/okdp/charts)
#   OUT             where the cases and their renders go (default: a temp dir)
#
# Requires helm (3 or 4), yq (https://github.com/mikefarah/yq), and access to
# the charts' repositories (helm pull, helm dependency build).
set -euo pipefail

[[ $# -gt 0 ]] || { echo "usage: $0 catalog/<service>/<version>..." >&2; exit 2; }
compile=${OKDP_COMPILE:-okdp-compile}
contracts=${OKDP_CONTRACTS:-$(cd "$(dirname "$0")/.." && pwd)/contracts}
charts=${OKDP_CHARTS:-${HOME}/.cache/okdp/charts}
out=${OUT:-$(mktemp -d)}
mkdir -p "${charts}" "${out}"
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

# check_case <args>...: okdp-compile --check with the chart cache, pulling
# each chart it reports missing. Prints the check's output; fails as it does.
check_case() {
  local log try pull cmd i
  for ((try = 0; try < 20; try++)); do
    if log=$("${compile}" --check --charts "${charts}" "$@" 2>&1); then
      printf '%s' "${log}"
      return 0
    fi
    pull=$(sed -n 's/.* is not in the chart cache: \(helm pull .*\)$/\1/p' <<<"${log}" | head -n1)
    if [[ -z "${pull}" ]]; then
      printf '%s' "${log}"
      return 1
    fi
    read -r -a cmd <<<"${pull//<chart cache>/@CHARTS@}"
    for i in "${!cmd[@]}"; do
      cmd[i]=${cmd[i]//@CHARTS@/${charts}}
    done
    if ! log=$("${cmd[@]}" 2>&1); then
      printf 'cannot pull a chart into the chart cache: %s\n%s' "${pull}" "${log}"
      return 1
    fi
  done
  printf 'the check still misses charts after 20 pulls'
  return 1
}

rc=0
for pkg in "$@"; do
  pkg=${pkg%/}
  if [[ ! -f "${pkg}/Chart.yaml" ]]; then
    echo "FAIL ${pkg}: no Chart.yaml: not a package (catalog/<service>/<version>)"
    rc=1
    continue
  fi
  service=$(yq '.name' "${pkg}/Chart.yaml")
  version=$(yq '.version' "${pkg}/Chart.yaml")
  abs=$(cd "${pkg}" && pwd -P)
  if [[ "$(basename "${abs}")" != "${version}" || "$(basename "$(dirname "${abs}")")" != "${service}" ]]; then
    echo "FAIL ${pkg}: Chart.yaml is ${service} ${version}: the package must be catalog/${service}/${version}"
    rc=1
    continue
  fi
  release="demo-${service}"
  cases=0
  for f in "${pkg}"/ci/*-values.yaml; do
    [[ -e "${f}" ]] || continue
    cases=$((cases + 1))
    case=$(basename "${f}" -values.yaml)
    dir="${out}/${service}/${case}"
    rm -rf "${dir}" "${dir}.yaml"
    mkdir -p "${dir}"
    args=(--package "${pkg}" --contracts "${contracts}")
    [[ ! -f "${pkg}/ci/platform.yaml" ]] || args+=(--context "${pkg}/ci/platform.yaml")
    [[ ! -f "${pkg}/ci/${case}-platform.yaml" ]] || args+=(--context "${pkg}/ci/${case}-platform.yaml")
    [[ ! -f "${pkg}/ci/${case}-connections.yaml" ]] || args+=(--context "2:${pkg}/ci/${case}-connections.yaml")
    args+=(-f "${f}" --release "${release}" --namespace demo)
    want=$(head -n1 "${f}" | sed -n 's/^# error: //p')

    if [[ -n "${want}" ]]; then
      # A case that must fail: at the compile, or at the check.
      if err=$("${compile}" "${args[@]}" -o "${dir}" 2>&1) && err=$(check_case "${args[@]}"); then
        echo "FAIL ${service} ${case}: compiled and checked, expected the error: ${want}"
        rc=1
      elif [[ "${err}" == *"${want}"* ]]; then
        echo "ok   ${service} ${case}: fails as expected"
      else
        echo "FAIL ${service} ${case}: ${err}"
        rc=1
      fi
      continue
    fi

    if ! err=$("${compile}" "${args[@]}" -o "${dir}" 2>&1); then
      echo "FAIL ${service} ${case}: ${err}"
      rc=1
      continue
    fi
    if ! err=$(check_case "${args[@]}"); then
      echo "FAIL ${service} ${case}: check: ${err}"
      rc=1
      continue
    fi
    while IFS= read -r line; do
      [[ "${line}" != warning:* ]] || echo "     ${service} ${case}: ${line}"
    done <<<"${err}"

    # Render the umbrella as a deployment does, in a copy: the next compile
    # into the directory refuses Chart.lock and charts/.
    chart="${work}/${service}-${case}"
    rm -rf "${chart}"
    cp -R "${dir}" "${chart}"
    if ! err=$(helm dependency build "${chart}" 2>&1); then
      echo "FAIL ${service} ${case}: helm dependency build: ${err}"
      rc=1
      continue
    fi
    if ! err=$(helm template "${release}" "${chart}" --namespace demo -f "${dir}/instance.values.yaml" 2>&1 > "${dir}.yaml"); then
      echo "FAIL ${service} ${case}: helm template: ${err}"
      rc=1
      continue
    fi
    keys=$(yq '[.dependencies[] | .alias // .name] | join(" ")' "${dir}/Chart.yaml")
    objects=$(grep -c '^kind:' "${dir}.yaml" || true)
    echo "ok   ${service} ${case}: ${keys:-no chart}, ${objects} objects (${dir}.yaml)"
  done
  if [[ ${cases} -eq 0 ]]; then
    echo "FAIL ${service} ${version}: no test case (ci/<case>-values.yaml)"
    rc=1
  fi
done
exit "${rc}"
