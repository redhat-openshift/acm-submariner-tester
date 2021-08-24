#!/bin/bash

# Set working dir
wd="$(dirname "$(realpath -s $0)")"

source ${wd:?}/debug.sh

trap_to_debug_commands; # Trap commands (should be called only after sourcing debug.sh)

############ FUNCTIONS ############

### Function to import the clusters to the clusterSet
function get_latest_iib() {
  trap_to_debug_commands;

  local version="${1}"
  local bundle_name="${2}"

  local ocp_version="$(oc version | grep "Server Version: " | tr -s ' ' | cut -d ' ' -f3 | cut -d '.' -f1,2)"
  local num_of_latest_builds=5
  local num_of_days=15

  rows=$((num_of_latest_builds * 5))
  delta=$((num_of_days * 86400))

  #curl -Ls "https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.index.built&rows_per_page=3&delta=${delta}&contains=${bundle_name}-container-${version}" | jq -r '[.raw_messages[].msg | {nvr: .artifact.nvr, index_image: .index.index_image, ocp_version: .index.ocp_version}]'

  # curl -Ls -o latest_iib.txt "https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.pipeline.complete&rows_per_page=${rows}&delta=${delta}&contains=${bundle_name}-container-${version}"

  curl -o latest_iib.txt -Ls "https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.pipeline.complete&rows_per_page=${rows}&delta=${delta}&contains=${bundle_name}-container-${version}"

  cat latest_iib.txt \
  | jq -r '[.raw_messages[].msg | select(.pipeline.status=="complete") | {nvr: .artifact.nvr, index_image: .pipeline.index_image}] | .[0]' \
  | jq -r '.index_image."v'"${ocp_version}"'"'

}

############ End of FUNCTIONS ############

declare -a installModes=('AllNamespaces' 'SingleNamespace')

# OPERATORS_NAMESPACE="openshift-operators"
# MARKETPLACE_NAMESPACE=${NAMESPACE:-openshift-marketplace}
INSTALL_MODE=${installModes[1]}
BREW_SECRET_NAME='brew-registry'

#SRC_IMAGE_INDEX="https://brew.registry.redhat.io/rh-osbs/iib:5801"

if [[ -z "${VERSION}" ]] ||
   [[ -z "${OPERATOR_NAME}" ]] ||
   [[ -z "${BUNDLE_NAME}" ]] ||
   [[ -z "${NAMESPACE}" ]] ||
   [[ -z "${CHANNEL}" ]]; then
    error "Required environment variables not loaded"
    error "    VERSION"
    error "    OPERATOR_NAME"
    error "    BUNDLE_NAME"
    error "    NAMESPACE"
    error "    CHANNEL"
    exit 3
fi

SUBSCRIBE=${SUBSCRIBE:-true}

# login
oc login -u "${OCP_USR}" -p "${OCP_PWD}"
OCP_REGISTRY_URL=$(oc registry info --internal)
OCP_IMAGE_INDEX="${OCP_REGISTRY_URL}/${MARKETPLACE_NAMESPACE}/${BUNDLE_NAME}-index:${VERSION}"
# OCP_VERSION=$(oc version | grep "Server Version: " | tr -s ' ' | cut -d ' ' -f3 | cut -d '.' -f1,2)

# Create/switch project
oc new-project "${NAMESPACE}" 2>/dev/null || oc project "${NAMESPACE}" -q

### Access to private repository
if oc get secret ${BREW_SECRET_NAME} -n "${NAMESPACE}" > /dev/null 2>&1; then
  oc delete secret ${BREW_SECRET_NAME} -n "${NAMESPACE}" --wait
fi
oc create secret -n "${NAMESPACE}" docker-registry ${BREW_SECRET_NAME} --docker-server=${REGISTRY_MIRROR} --docker-username="${REGISTRY_USR}" --docker-password="${REGISTRY_PWD}" --docker-email=${BREW_REGISTRY_EMAIL}

# Set the subscription namespace
subscriptionNamespace=$([ "${INSTALL_MODE}" == "${installModes[0]}" ] && echo "${OPERATORS_NAMESPACE}" || echo "${NAMESPACE}")

# Disable the default remote OperatorHub sources for OLM
oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'

# Delete previous catalogSource and Subscription
oc delete sub/my-subscription -n "${subscriptionNamespace}" --wait > /dev/null 2>&1 || :
oc delete catalogsource/my-catalog-source -n "${MARKETPLACE_NAMESPACE}" --wait > /dev/null 2>&1 || :

# SRC_IMAGE_INDEX=$(${wd:?}/downstream_get_latest_iib.sh "${VERSION}" "${BUNDLE_NAME}" | jq -r '.index_image."v'"${OCP_VERSION}"'"')
SRC_IMAGE_INDEX="$(get_latest_iib "${VERSION}" "${BUNDLE_NAME}")"
if [ -z "${SRC_IMAGE_INDEX}" ]; then
  if [ -z "${1}" ]; then
    error "SRC_IMAGE_INDEX was not provided" && exit 4
  fi
  SRC_IMAGE_INDEX=${1}
else
  SRC_IMAGE_INDEX="${REGISTRY_MIRROR}/$(echo ${SRC_IMAGE_INDEX} | cut -d'/' -f2-)"
fi
if oc get is "${BUNDLE_NAME}-index" -n "${MARKETPLACE_NAMESPACE}" > /dev/null 2>&1; then
  oc delete is "${BUNDLE_NAME}-index" -n "${MARKETPLACE_NAMESPACE}" --wait
fi
oc import-image "${OCP_IMAGE_INDEX}" --from="${SRC_IMAGE_INDEX}" -n "${MARKETPLACE_NAMESPACE}" --confirm | grep -E 'com.redhat.component|version|release|com.github.url|com.github.commit|vcs-ref'


# create the CatalogSource
cat <<EOF | oc apply -n ${MARKETPLACE_NAMESPACE} -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: my-catalog-source
  namespace: ${MARKETPLACE_NAMESPACE}
spec:
  sourceType: grpc
  image: ${OCP_IMAGE_INDEX}
  displayName: Testing Catalog Source
  publisher: Red Hat Partner (Test)
  updateStrategy:
    registryPoll:
      interval: 5m
EOF

# wait
if ! (timeout 5m bash -c "until [[ $(oc get catalogsource -n ${MARKETPLACE_NAMESPACE} my-catalog-source -o jsonpath='{.status.connectionState.lastObservedState}') -eq 'READY' ]]; do sleep 10; done"); then
    error "CatalogSource is not ready"
    exit 1
fi

# test
info "$(oc -n ${MARKETPLACE_NAMESPACE} get catalogsource --ignore-not-found)"
info "$(oc -n ${MARKETPLACE_NAMESPACE} get pods --ignore-not-found)"
info "$( (oc -n ${MARKETPLACE_NAMESPACE} get packagemanifests --ignore-not-found | grep 'Testing Catalog Source') || true)"

if [ "${SUBSCRIBE}" = true ]; then
  if [ "${INSTALL_MODE}" == "${installModes[1]}" ]; then
    # create the OperatorGroup
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: my-group
  namespace: ${NAMESPACE}
spec:
  targetNamespaces:
    - ${NAMESPACE}
EOF

    # test
    info "$(oc get og -n ${NAMESPACE} --ignore-not-found)"
  fi

  # create the Subscription (Approval should be Manual not Automatic in order to pin the bundle version)
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: my-subscription
  namespace: ${subscriptionNamespace}
spec:
  channel: ${CHANNEL}
  installPlanApproval: Manual
  name: ${OPERATOR_NAME}
  source: my-catalog-source
  sourceNamespace: ${MARKETPLACE_NAMESPACE}
  startingCSV: ${OPERATOR_NAME}.${VERSION}
EOF

  # Manual Approve
  oc wait --for condition=InstallPlanPending --timeout=5m -n "${subscriptionNamespace}" subs/my-subscription || (error "InstallPlan not found."; exit 1)
  installPlan=$(oc get subscriptions.operators.coreos.com my-subscription -n "${subscriptionNamespace}" -o jsonpath='{.status.installPlanRef.name}')
  if [ -n "${installPlan}" ]; then
    oc patch installplan -n "${subscriptionNamespace}" "${installPlan}" -p '{"spec":{"approved":true}}' --type merge
  fi

  # test
  info "$(oc get sub -n "${subscriptionNamespace}" --ignore-not-found)"
  info "$(oc get installplan -n "${subscriptionNamespace}" --ignore-not-found)"
  info "$(oc get csv -n "${subscriptionNamespace}" --ignore-not-found)"
  info "$(oc get pods -n "${subscriptionNamespace}" --ignore-not-found)"
  info "$(oc get pods -n openshift-operator-lifecycle-manager --ignore-not-found)"
  debug "$(oc logs -n openshift-operator-lifecycle-manager deploy/catalog-operator | grep '^E0')"
  debug "$(oc logs -n openshift-operator-lifecycle-manager deploy/olm-operator | grep '^E0')"
fi
