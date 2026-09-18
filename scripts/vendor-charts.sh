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
# Unpacks the upstream charts a wrapper chart renders with okdp.vendor.render.
#
# Each wrapper lists them in <chart>/vendor.yaml:
#
#   charts:
#     - name: trino                                   # directory under vendor/
#       repository: https://trinodb.github.io/charts  # or oci://registry/path
#       version: 1.42.1
#       chart: trino                                  # optional, default: name
#       drop: [charts/postgresql]                     # optional, paths removed after unpacking
#
# and gets vendor/<name>/ (the pristine `helm pull --untar`, nested library
# charts unpacked too, minus the `drop` paths: e.g. a disabled application
# subchart, which okdp.vendor.render refuses to carry). vendor/ is committed: the chart renders offline, the
# published chart is self-contained, and an upgrade shows up as a diff.
#
# repository may also be file://<path>, relative to the wrapper chart: a chart
# of this repository (charts/oidc-client) copied as is; its Chart.yaml
# version must be the listed version.
#
#   scripts/vendor-charts.sh <chart dir>...          (re)vendor
#   scripts/vendor-charts.sh --check <chart dir>...  fail if vendor/ differs from vendor.yaml
set -euo pipefail

check=false
if [[ "${1:-}" == "--check" ]]; then check=true; shift; fi
[[ $# -gt 0 ]] || { echo "usage: $0 [--check] <chart dir>..." >&2; exit 2; }

rc=0
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

for chart in "$@"; do
  manifest="${chart}/vendor.yaml"
  [[ -f "${manifest}" ]] || { echo "${manifest}: not found" >&2; rc=1; continue; }
  count=$(yq '.charts | length' "${manifest}")
  listed=()
  for ((i = 0; i < count; i++)); do
    name=$(yq ".charts[${i}].name" "${manifest}")
    repo=$(yq ".charts[${i}].repository" "${manifest}")
    version=$(yq ".charts[${i}].version" "${manifest}")
    upstream=$(yq ".charts[${i}].chart // .charts[${i}].name" "${manifest}")
    listed+=("${name}")
    dest="${work}/$(basename "${chart}")/${name}"
    mkdir -p "${dest}"
    if [[ "${repo}" == file://* ]]; then
      src="${chart}/${repo#file://}"
      got=$(yq '.version' "${src}/Chart.yaml")
      if [[ "${got}" != "${version}" ]]; then
        echo "FAIL ${src} is version ${got}, ${manifest} lists ${version}"
        rc=1
        continue
      fi
      cp -r "${src}" "${dest}/${upstream}"
    elif [[ "${repo}" == oci://* ]]; then
      helm pull "${repo%/}/${upstream}" --version "${version}" --untar --untardir "${dest}" >/dev/null 2>&1
    else
      helm pull "${upstream}" --repo "${repo}" --version "${version}" --untar --untardir "${dest}" >/dev/null 2>&1
    fi
    pulled="${dest}/${upstream}"
    # Nested dependencies ship as archives: unpack them so their partials load.
    if [[ -d "${pulled}/charts" ]]; then
      for tgz in "${pulled}"/charts/*.tgz; do
        [[ -e "${tgz}" ]] || continue
        tar -xzf "${tgz}" -C "${pulled}/charts" && rm -f "${tgz}"
      done
    fi
    # Paths the wrapper never renders (e.g. a disabled application subchart).
    while IFS= read -r drop; do
      [[ -n "${drop}" ]] || continue
      [[ "${drop}" != /* && "${drop}" != *..* ]] || { echo "${manifest}: bad drop path ${drop}" >&2; exit 2; }
      rm -rf "${pulled:?}/${drop}"
    done < <(yq ".charts[${i}].drop // [] | .[]" "${manifest}")
    # Git does not keep empty directories: drop them so --check matches a checkout.
    find "${pulled}" -mindepth 1 -type d -empty -delete
    target="${chart}/vendor/${name}"
    if ${check}; then
      if diff -r "${pulled}" "${target}" >/dev/null 2>&1; then
        echo "ok   ${target} = ${upstream} ${version}"
      else
        echo "FAIL ${target} differs from ${upstream} ${version} (${repo}): run $0 ${chart}"
        rc=1
      fi
    else
      rm -rf "${target}"
      mkdir -p "${chart}/vendor"
      mv "${pulled}" "${target}"
      echo "vendored ${target} = ${upstream} ${version}"
    fi
  done
  # Anything under vendor/ that vendor.yaml does not list is stale.
  if [[ -d "${chart}/vendor" ]]; then
    for d in "${chart}"/vendor/*/; do
      n=$(basename "${d}")
      if [[ ! " ${listed[*]} " == *" ${n} "* ]]; then
        if ${check}; then echo "FAIL ${chart}/vendor/${n} is not listed in vendor.yaml"; rc=1
        else rm -rf "${d}"; echo "removed ${chart}/vendor/${n}"; fi
      fi
    done
  fi
done

exit "${rc}"
