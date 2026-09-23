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
# Compose each chart's version from its two halves.
#
# A service chart's version (Chart.yaml `version`, also its OCI tag) is
# <upstream version>-<OKDP version>, e.g. 480.0.0-1.0.1. The upstream half is
# maintained by hand in Chart.yaml. The OKDP half is owned by release-please,
# which has just written it into .release-please-manifest.json on its release
# branch. Charts under charts/, if any, are OKDP's own: their version is the
# release-please version itself.
#
# release-please cannot write the composite itself: its `generic` updater's
# version regex swallows the prerelease, so annotating the line would replace
# the whole version with a bare X.Y.Z. Hence this step, and hence no
# `extra-files` in release-please-config.json.
#
# Runs on the release-please branch, after release-please-action.
set -euo pipefail

rc=0

while read -r path version; do
  file="${path}/Chart.yaml"
  if [[ ! -f "${file}" ]]; then
    echo "::error title=No chart::${path} is in the manifest but has no Chart.yaml"
    rc=1
    continue
  fi

  old=$(sed -n 's/^version: *//p' "${file}" | head -1 | sed -e 's/ *#.*//' -e 's/^["'\'']//' -e 's/["'\'']$//')

  if [[ "${path}" == charts/* ]]; then
    new="${version}"
  else
    # Strip exactly one trailing -X.Y.Z, anchored at end of string. Anything to
    # the left is the upstream half, however many dashes it contains:
    #   24.4.11-1.0.0          -> 24.4.11
    #   1.3.0-incubating-1.0.0 -> 1.3.0-incubating
    if [[ ! "${old}" =~ ^(.+)-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
      echo "::error file=${file}::version '${old}' has no -X.Y.Z suffix, so the upstream half cannot be identified"
      rc=1
      continue
    fi
    new="${BASH_REMATCH[1]}-${version}"
  fi

  if [[ "${new}" != "${old}" ]]; then
    # Not `sed -i`: the BSD/macOS form needs an argument, so this stays
    # runnable on a maintainer's laptop as well as on the runner.
    tmp=$(mktemp)
    sed "s|^version: .*|version: ${new}|" "${file}" > "${tmp}" && mv "${tmp}" "${file}"
    echo "  ${file}: ${old} -> ${new}"
  fi
done < <(jq -r 'to_entries[] | "\(.key) \(.value)"' .release-please-manifest.json)

exit "${rc}"
