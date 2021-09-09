#!/bin/bash

############ OCP Operators Functions ############

# Set working dir
# wd="$(dirname "$(realpath -s $0)")"

# source ${wd:?}/debug.sh

### Function to import the clusters to the clusterSet
function export_LATEST_IIB() {
  trap_to_debug_commands;

  local version="${1}"
  local bundle_name="${2}"

  local ocp_version_x_y=$(${OC} version | awk '/Server Version/ { print $3 }' | cut -d '.' -f 1,2 || :)
  local num_of_latest_builds=5
  local num_of_days=15

  rows=$((num_of_latest_builds * 5))
  delta=$((num_of_days * 86400))

  #curl -Ls "https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.index.built&rows_per_page=3&delta=${delta}&contains=${bundle_name}-container-${version}" | jq -r '[.raw_messages[].msg | {nvr: .artifact.nvr, index_image: .index.index_image, ocp_version: .index.ocp_version}]'

  curl --retry 30 --retry-delay 5 -o latest_iib.txt -Ls "https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.pipeline.complete&rows_per_page=${rows}&delta=${delta}&contains=${bundle_name}-container-${version}"

  export LATEST_IIB=$(cat latest_iib.txt \
  | jq -r '[.raw_messages[].msg | select(.pipeline.status=="complete") | {nvr: .artifact.nvr, index_image: .pipeline.index_image}] | .[0]' \
  | jq -r '.index_image."v'"${ocp_version_x_y}"'"' )

}

# ------------------------------------------

function deploy_ocp_bundle() {
  ### Deploy OCP Bundel ###

  trap_to_debug_commands;

  local version="$1"
  local operator_name="$2"
  local bundle_name="$3"
  local namespace="$4"
  local channel="$5"

  # Whether to install operator on the default namespace, or in a specific namespace
  declare -a installModes=('AllNamespaces' 'SingleNamespace')

  TITLE "Deploy OCP operator bundle using defined variables:
  \n# VERSION=${version}
  \n# OPERATOR_NAME=${operator_name}
  \n# BUNDLE_NAME=${bundle_name}
  \n# NAMESPACE=${namespace}
  \n# CHANNEL=${channel}"

  if [[ -z "${version}" ]] ||
     [[ -z "${operator_name}" ]] ||
     [[ -z "${bundle_name}" ]] ||
     [[ -z "${namespace}" ]] ||
     [[ -z "${channel}" ]]; then
      error "Required environment variables not loaded"
      error "    VERSION"
      error "    OPERATOR_NAME"
      error "    BUNDLE_NAME"
      error "    NAMESPACE"
      error "    CHANNEL"
      exit 3
  fi

  # OPERATORS_NAMESPACE="openshift-operators"
  marketplace_namespace=${namespace:-$MARKETPLACE_NAMESPACE}
  INSTALL_MODE=${installModes[1]}
  # BREW_SECRET_NAME='brew-registry'

  SUBSCRIBE=${SUBSCRIBE:-false}

  # login
  ( # subshell to hide commands
    cmd="${OC} login -u ${OCP_USR} -p ${OCP_PWD}"
    # Attempt to login up to 3 minutes
    watch_and_retry "$cmd" 3m
  )

  ocp_registry_url=$(${OC} registry info --internal)

  # Create/switch project
  ${OC} new-project "${namespace}" 2>/dev/null || ${OC} project "${namespace}" -q

  # ### Access to private repository
  # if ${OC} get secret ${BREW_SECRET_NAME} -n "${namespace}" > /dev/null 2>&1; then
  #   ${OC} delete secret ${BREW_SECRET_NAME} -n "${namespace}" --wait
  # fi
  # ${OC} create secret -n "${namespace}" docker-registry ${BREW_SECRET_NAME} --docker-server=${BREW_REGISTRY} --docker-username="${REGISTRY_USR}" --docker-password="${REGISTRY_PWD}" --docker-email=${BREW_REGISTRY_EMAIL}

  ( # subshell to hide commands
    TITLE "Configure OCP registry local secret"
    ocp_token=$(${OC} whoami -t)
    create_docker_registry_secret "$ocp_registry_url" "$OCP_USR" "$ocp_token" "$namespace"
  )

  # Set the subscription namespace
  subscriptionNamespace=$([ "${INSTALL_MODE}" == "${installModes[0]}" ] && echo "${OPERATORS_NAMESPACE}" || echo "${namespace}")

  # Disable the default remote OperatorHub sources for OLM
  ${OC} patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'

  # Delete previous catalogSource and Subscription
  ${OC} delete sub/my-subscription -n "${subscriptionNamespace}" --wait > /dev/null 2>&1 || :
  ${OC} delete catalogsource/my-catalog-source -n "${marketplace_namespace}" --wait > /dev/null 2>&1 || :

  # SRC_IMAGE_INDEX=$(${wd:?}/downstream_get_latest_iib.sh "${version}" "${bundle_name}" | jq -r '.index_image."v'"${OCP_VERSION}"'"')
  # if [ -z "${SRC_IMAGE_INDEX}" ]; then
  #   if [ -z "${1}" ]; then
  #     error "SRC_IMAGE_INDEX was not provided" && exit 4
  #   fi
  #   SRC_IMAGE_INDEX=${1}
  # else
  #   SRC_IMAGE_INDEX="${BREW_REGISTRY}/$(echo ${SRC_IMAGE_INDEX} | cut -d'/' -f2-)"
  # fi

  export_LATEST_IIB "${version}" "${bundle_name}"

  SRC_IMAGE_INDEX="${BREW_REGISTRY}/$(echo ${LATEST_IIB} | cut -d'/' -f2-)"

  if ${OC} get is "${bundle_name}-index" -n "${marketplace_namespace}" > /dev/null 2>&1; then
    ${OC} delete is "${bundle_name}-index" -n "${marketplace_namespace}" --wait
  fi

  OCP_IMAGE_INDEX="${ocp_registry_url}/${marketplace_namespace}/${bundle_name}-index:${version}"

  ${OC} import-image "${OCP_IMAGE_INDEX}" --from="${SRC_IMAGE_INDEX}" -n "${marketplace_namespace}" --confirm | grep -E 'com.redhat.component|version|release|com.github.url|com.github.commit|vcs-ref'


  TITLE "Create the CatalogSource"

  cat <<EOF | ${OC} apply -n ${marketplace_namespace} -f -
  apiVersion: operators.coreos.com/v1alpha1
  kind: CatalogSource
  metadata:
    name: my-catalog-source
    namespace: ${marketplace_namespace}
  spec:
    sourceType: grpc
    image: ${OCP_IMAGE_INDEX}
    displayName: Testing Catalog Source
    publisher: Red Hat Partner (Test)
    updateStrategy:
      registryPoll:
        interval: 5m
EOF

  # # wait
  # if ! (timeout 5m bash -c "until [[ $(${OC} get catalogsource -n ${marketplace_namespace} my-catalog-source -o jsonpath='{.status.connectionState.lastObservedState}') -eq 'READY' ]]; do sleep 10; done"); then
  #     error "CatalogSource is not ready"
  #     exit 1
  # fi

  TITLE "Wait for CatalogSource to be created"

  cmd="${OC} get catalogsource -n ${marketplace_namespace} my-catalog-source -o jsonpath='{.status.connectionState.lastObservedState}'"
  watch_and_retry "$cmd" 5m "READY" || FATAL "ACM CatalogSource was not created"

  # test
  ${OC} -n ${marketplace_namespace} get catalogsource --ignore-not-found
  ${OC} -n ${marketplace_namespace} get pods --ignore-not-found
  (${OC} -n ${marketplace_namespace} get packagemanifests --ignore-not-found | grep 'Testing Catalog Source') || true

  if [ "${SUBSCRIBE}" = true ]; then
    # Deprecated since ACM 2.3
    if [ "${INSTALL_MODE}" == "${installModes[1]}" ]; then
      # create the OperatorGroup
  cat <<EOF | ${OC} apply -f -
  apiVersion: operators.coreos.com/v1alpha2
  kind: OperatorGroup
  metadata:
    name: my-group
    namespace: ${namespace}
  spec:
    targetNamespaces:
      - ${namespace}
EOF

      # test
      ${OC} get og -n ${namespace} --ignore-not-found
    fi

  TITLE "Create the Subscription (Approval should be Manual not Automatic in order to pin the bundle version)"

  cat <<EOF | ${OC} apply -f -
  apiVersion: operators.coreos.com/v1alpha1
  kind: Subscription
  metadata:
    name: my-subscription
    namespace: ${subscriptionNamespace}
  spec:
    channel: ${channel}
    installPlanApproval: Manual
    name: ${operator_name}
    source: my-catalog-source
    sourceNamespace: ${marketplace_namespace}
    startingCSV: ${operator_name}.${version}
EOF

    # Manual Approve
    ${OC} wait --for condition=InstallPlanPending --timeout=5m -n "${subscriptionNamespace}" subs/my-subscription || (error "InstallPlan not found."; exit 1)
    installPlan=$(${OC} get subscriptions.operators.coreos.com my-subscription -n "${subscriptionNamespace}" -o jsonpath='{.status.installPlanRef.name}')
    if [ -n "${installPlan}" ]; then
      ${OC} patch installplan -n "${subscriptionNamespace}" "${installPlan}" -p '{"spec":{"approved":true}}' --type merge
    fi

    # test
    ${OC} get sub -n "${subscriptionNamespace}" --ignore-not-found
    ${OC} get installplan -n "${subscriptionNamespace}" --ignore-not-found
    ${OC} get csv -n "${subscriptionNamespace}" --ignore-not-found
    ${OC} get pods -n "${subscriptionNamespace}" --ignore-not-found
    ${OC} get pods -n openshift-operator-lifecycle-manager --ignore-not-found
    ${OC} logs -n openshift-operator-lifecycle-manager deploy/catalog-operator | grep '^E0'
    ${OC} logs -n openshift-operator-lifecycle-manager deploy/olm-operator | grep '^E0'
  fi

}
