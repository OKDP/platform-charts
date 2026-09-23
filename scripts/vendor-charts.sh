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
# This is the canonical copy (OKDP/platform-charts): the copies in other
# OKDP chart repositories must stay byte-identical to it.
#
# Each wrapper lists them in <chart>/vendor.yaml:
#
#   charts:
#     - name: trino                                   # required: directory under vendor/
#       repository: https://trinodb.github.io/charts  # required: https://, oci://registry/path
#                                                     #   or file://<path>
#       version: 1.42.1                               # required: exact chart version
#       chart: trino                                  # optional: upstream chart name,
#                                                     #   default: name
#       drop: [charts/postgresql]                     # optional: paths removed after unpacking
#
# No other key is accepted. vendor/<name>/ receives the pristine
# `helm pull --untar`, its nested dependency archives unpacked (their partials
# must load), minus the `drop` paths, then minus the directories left empty.
#
# drop: paths RELATIVE TO THE VENDORED CHART ROOT (e.g. charts/postgresql,
# templates/secret.yaml), never absolute, never containing "..", and each must
# exist in the pulled chart. Use it for what the wrapper never renders: a
# bundled application subchart it disables or replaces (okdp.vendor.render
# refuses to carry one), an upstream template it replaces.
#
# repository: file://<path>, relative to the wrapper chart: a chart of the same
# repository (e.g. charts/<helper>) copied as is; its Chart.yaml version
# must be the listed version.
#
# vendor/ is committed (lock files of vendored charts included): the chart
# renders offline, the published chart is self-contained, and an upgrade shows
# up as a diff. Git keeps no empty directory, hence their removal, so --check
# passes on a fresh clone.
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
    name=$(yq ".charts[${i}].name // \"\"" "${manifest}")
    listed+=("${name}")
    unknown=$(yq ".charts[${i}] | keys | .[] | select(. != \"name\" and . != \"repository\" and . != \"version\" and . != \"chart\" and . != \"drop\")" "${manifest}")
    if [[ -n "${unknown}" ]]; then
      echo "FAIL ${manifest}: charts[${i}]: unknown key(s) $(echo ${unknown}) (allowed: name, repository, version, chart, drop)"
      rc=1; continue
    fi
    repo=$(yq ".charts[${i}].repository // \"\"" "${manifest}")
    version=$(yq ".charts[${i}].version // \"\"" "${manifest}")
    upstream=$(yq ".charts[${i}].chart // .charts[${i}].name" "${manifest}")
    if [[ -z "${name}" || -z "${repo}" || -z "${version}" ]]; then
      echo "FAIL ${manifest}: charts[${i}]: name, repository and version are required"
      rc=1; continue
    fi
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
      pull=(helm pull "${repo%/}/${upstream}" --version "${version}" --untar --untardir "${dest}")
    else
      pull=(helm pull "${upstream}" --repo "${repo}" --version "${version}" --untar --untardir "${dest}")
    fi
    if [[ "${repo}" != file://* ]] && ! err=$("${pull[@]}" 2>&1 >/dev/null); then
      echo "FAIL ${manifest}: cannot pull ${upstream} ${version} from ${repo}: ${err}"
      rc=1; continue
    fi
    pulled="${dest}/${upstream}"
    # Nested dependencies ship as archives: unpack them so their partials load.
    if [[ -d "${pulled}/charts" ]]; then
      for tgz in "${pulled}"/charts/*.tgz; do
        [[ -e "${tgz}" ]] || continue
        tar -xzf "${tgz}" -C "${pulled}/charts" && rm -f "${tgz}"
      done
    fi
    # Paths the wrapper never renders (vendor.yaml `drop`, relative to the chart root).
    bad=false
    while IFS= read -r drop; do
      [[ -n "${drop}" ]] || continue
      if [[ "${drop}" == /* || "${drop}" == *..* ]]; then
        echo "FAIL ${manifest}: charts[${i}].drop: '${drop}' must be a path relative to the chart root, without '..'"
        bad=true; continue
      fi
      if [[ ! -e "${pulled}/${drop}" ]]; then
        echo "FAIL ${manifest}: charts[${i}].drop: '${drop}' not found in ${upstream} ${version} (paths are relative to the chart root, e.g. charts/<subchart>)"
        bad=true; continue
      fi
      rm -rf "${pulled:?}/${drop}"
    done < <(yq ".charts[${i}].drop // [] | .[]" "${manifest}")
    if ${bad}; then rc=1; continue; fi
    # Git keeps no empty directory: drop them so --check matches a clone.
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
