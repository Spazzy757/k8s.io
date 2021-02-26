#!/usr/bin/env bash
#
# Copyright 2019 The Kubernetes Authors.
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

# This script creates & configures the project that governs access to GSuite
# APIs.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "${SCRIPT_DIR}/lib.sh"

function usage() {
    echo "usage: $0" > /dev/stderr
    echo > /dev/stderr
}

if [ $# != 0 ]; then
    usage
    exit 1
fi

org_roles=(
    prow.viewer
    audit.viewer
    secretmanager.secretLister
    organization.admin
    CustomRole
    StorageBucketLister
)

color 6 "Ensuring organization custom roles exist"
(
    for role in "${org_roles[@]}"; do
      color 6 "Ensuring organization custom role ${role}"
      ensure_custom_iam_role_from_file "org" "${role}" "${SCRIPT_DIR}/roles/${role}.yaml"
    done
) 2>&1 | indent

color 6 "Ensuring org-level IAM bindings exist"
(
    # k8s-infra-prow-oncall@kubernetes.io should be able to browse org resources
    ensure_org_role_binding "group:k8s-infra-prow-oncall@kubernetes.io" "roles/browser"
    
    # TODO: this already exists, but seems overprivileged for a group that is about
    #       access to the "aaa" cluster in "kubernetes-public"
    ensure_org_role_binding "group:gke-security-groups@kubernetes.io" "roles/browser"

    # k8s-infra-gcp-accounting@
    ensure_org_role_binding "group:k8s-infra-gcp-accounting@kubernetes.io" "$(custom_org_role_name "CustomRole")"

    # k8s-infra-gcp-auditors@
    ensure_org_role_binding "group:k8s-infra-gcp-auditors@kubernetes.io" "$(custom_org_role_name "audit.viewer")"
    # TODO(https://github.com/kubernetes/k8s.io/issues/1659): obviated by audit.viewer, remove when bindings gone
    old_audit_roles=(
        "$(custom_org_role_name "StorageBucketLister")"
        roles/compute.viewer
        roles/dns.reader
        roles/iam.securityReviewer
        roles/resourcemanager.organizationViewer
        roles/serviceusage.serviceUsageConsumer
    )
    for role in "${old_audit_roles[@]}"; do
        ensure_removed_org_role_binding "group:k8s-infra-gcp-auditors@kubernetes.io" "${role}"
    done

    echo "exiting early to confirm audit.viewer role migration has worked"
    exit 0

    # k8s-infra-org-admins@
    # TODO: there are more granular roles also bound, they seem redundant given
    #       this role
    ensure_org_role_binding "group:k8s-infra-gcp-org-admins@kubernetes.io" "roles/owner"
) 2>&1 | indent
