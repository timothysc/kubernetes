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

# Source this script in the Jenkins "Execute shell" build action to have all
# test artifacts and the console log uploaded at the end of the test run.

# For example, you might use the following line as the first command:
# mkdir -p _tmp/ && curl -fsS --retry 3 -o _tmp/upload-to-gcs.sh \
#   "https://raw.githubusercontent.com/kubernetes/kubernetes/master/hack/jenkins/upload-to-gcs.sh" \
#   && source _tmp/upload-to-gcs.sh

# Note that this script requires the Jenkins shell binary to be set to bash, not
# the system default (which may be dash on Debian-based systems).
# Also, for magicfile support to work correctly, the "file" utility must be
# installed.

set -o errexit
set -o nounset
set -o pipefail
set -o xtrace

if [[ ${JOB_NAME} =~ -pull- ]]; then
  : ${JENKINS_GCS_LOGS_PATH:="gs://kubernetes-jenkins/pr-logs/${ghprbActualCommit:-unknown}"}
else
  : ${JENKINS_GCS_LOGS_PATH:="gs://kubernetes-jenkins/logs"}
fi

: ${JENKINS_UPLOAD_TO_GCS:="y"}

# Upload the build log and all test artifacts (under _artifacts) to GCS when
# JENKINS_UPLOAD_TO_GCS is set to y.
# We intentionally ignore gsutil errors since we don't want failed uploads to
# fail the entire test run (#13548).
function upload_logs_to_gcs() {
  if [[ ! ${JENKINS_UPLOAD_TO_GCS:-} =~ ^[yY]$ ]]; then
      return
  fi
  local -r artifacts_path="${WORKSPACE}/_artifacts"
  local -r gcs_job_path="${JENKINS_GCS_LOGS_PATH}/${JOB_NAME}"
  local -r gcs_build_path="${gcs_job_path}/${BUILD_NUMBER}"
  local -r gcs_acl="public-read"
  for upload_attempt in $(seq 3); do
    echo "Uploading to ${gcs_build_path} (attempt ${upload_attempt})"
    if [[ -d "${artifacts_path}" ]]; then
      gsutil -m -q -o "GSUtil:use_magicfile=True" cp -a "${gcs_acl}" -r -c \
        -z log,txt,xml "${artifacts_path}" "${gcs_build_path}/artifacts" || continue
    fi
    # Remove ANSI escape sequences from the console log before uploading.
    local -r filtered_console_log="${WORKSPACE}/console-log.txt"
    sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" \
      "${JENKINS_HOME}/jobs/${JOB_NAME}/builds/${BUILD_NUMBER}/log" \
      > "${filtered_console_log}"
    gsutil -q cp -a "${gcs_acl}" -z txt "${filtered_console_log}" "${gcs_build_path}/" || continue
    # Mark this build as the latest completed.
    {
      echo "BUILD_NUMBER=${BUILD_NUMBER}"
      echo "GIT_COMMIT=${GIT_COMMIT:-}"
    } | gsutil -q -h "Content-Type:text/plain" -h "Cache-Control:private, max-age=0, no-transform" \
      cp -a "${gcs_acl}" - "${gcs_job_path}/latest-build.txt" || continue
    break  # all uploads succeeded if we hit this point
  done
}

# Automatically upload logs to GCS on exit or timeout.
trap upload_logs_to_gcs EXIT SIGTERM SIGINT
