#!/bin/bash

# Copyright 2015 The Kubernetes Authors All rights reserved.
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

set -o errexit
set -o nounset
set -o pipefail

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/..
cd "${KUBE_ROOT}"

generated_files=$(
  find . -not \( \
      \( \
        -wholename './output' \
        -o -wholename './_output' \
        -o -wholename './release' \
        -o -wholename './target' \
        -o -wholename '*/third_party/*' \
        -o -wholename '*/Godeps/*' \
      \) -prune \
    \) -name '*.generated.go')

for generated_file in ${generated_files}; do
  initial_dir=${PWD}
  file=${generated_file//\.generated\.go/.go}
  # codecgen work only if invoked from directory where the file
  # is located.
  pushd "$(dirname ${file})" > /dev/null
  base_file=$(basename "${file}")
  base_generated_file=$(basename "${generated_file}")
  # We use '-d 1234' flag to have a deterministic output everytime.
  # The constant was just randomly chosen.
  codecgen -d 1234 -o "${base_generated_file}" "${base_file}"
  # Add boilerplate at the begining of the generated file.
  sed 's/YEAR/2015/' "${initial_dir}/hack/boilerplate/boilerplate.go.txt" > "${base_generated_file}.tmp"
  cat "${base_generated_file}" >> "${base_generated_file}.tmp"
  mv "${base_generated_file}.tmp" "${base_generated_file}"
  popd > /dev/null
done
