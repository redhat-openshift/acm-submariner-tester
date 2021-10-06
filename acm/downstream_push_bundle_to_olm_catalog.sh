#!/bin/bash

############ OCP Operators functions ############


### Function to find latest index image for a bundle in datagrepper.engineering.redhat
function export_LATEST_IIB() {
  trap_to_debug_commands;

  local version="${1}"
  local bundle_name="${2}"

  local ocp_version_x_y
  ocp_version_x_y=$(${OC} version | awk '/Server Version/ { print $3 }' | cut -d '.' -f 1,2 || :)
  local num_of_latest_builds=5
  local num_of_days=15

  rows=$((num_of_latest_builds * 5))
  delta=$((num_of_days * 86400)) # 1296000 = 15 days * 86400 seconds

  curl --retry 30 --retry-delay 5 -o latest_iib.txt -Ls 'https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.pipeline.complete&rows_per_page='${rows}'&delta='${delta}'&contains='${bundle_name}'-container-'${version}

  # export LATEST_IIB=$(cat latest_iib.txt \
  # | jq -r '[.raw_messages[].msg | select(.pipeline.status=="complete") | {nvr: .artifact.nvr, index_image: .pipeline.index_image}] | .[0]' \
  # | jq -r '.index_image."v'"${ocp_version_x_y}"'"' )

  LATEST_IIB=$(cat latest_iib.txt \
  | jq -r '[.raw_messages[].msg | {nvr: .artifact.nvr, index_image: .pipeline.index_image}] | .[0]' \
  | jq -r '.index_image."v'"${ocp_version_x_y}"'"' )

  export LATEST_IIB

  # Index Image example:
  # {
  # "nvr": "submariner-operator-bundle-container-v0.11.0-6",
  # "index_image": {
  #   "v4.6": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105099",
  #   "v4.7": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105101",
  #   "v4.8": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105104",
  #   "v4.9": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105105"
  # }

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

  marketplace_namespace=${namespace:-$MARKETPLACE_NAMESPACE}
  INSTALL_MODE=${installModes[1]}

  SUBSCRIBE=${SUBSCRIBE:-false}

  # login
  ( # subshell to hide commands
    ocp_pwd="$(< ${WORKDIR}/${OCP_USR}.sec)"
    cmd="${OC} login -u ${OCP_USR} -p ${ocp_pwd}"
    # Attempt to login up to 3 minutes
    watch_and_retry "$cmd" 3m
  )

  ocp_registry_url=$(${OC} registry info --internal)

  echo "# Create/switch project"
  ${OC} new-project "${namespace}" 2>/dev/null || ${OC} project "${namespace}" -q

  echo "# Set the subscription namespace"
  subscriptionNamespace=$([ "${INSTALL_MODE}" == "${installModes[0]}" ] && echo "${OPERATORS_NAMESPACE}" || echo "${namespace}")

  echo "# Disable the default remote OperatorHub sources for OLM"
  ${OC} patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'

  echo "# Delete previous catalogSource and Subscription"
  ${OC} delete sub/${ACM_SUBSCRIPTION} -n "${subscriptionNamespace}" --wait > /dev/null 2>&1 || :
  ${OC} delete catalogsource/${ACM_CATALOG} -n "${marketplace_namespace}" --wait > /dev/null 2>&1 || :

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
    name: ${ACM_CATALOG}
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


  TITLE "Wait for CatalogSource '${ACM_CATALOG}' to be created"

  cmd="${OC} get catalogsource -n ${marketplace_namespace} ${ACM_CATALOG} -o jsonpath='{.status.connectionState.lastObservedState}'"
  watch_and_retry "$cmd" 5m "READY" || FATAL "ACM CatalogSource '${ACM_CATALOG}' was not created"

  # test
  ${OC} -n ${marketplace_namespace} get catalogsource --ignore-not-found
  ${OC} -n ${marketplace_namespace} get pods --ignore-not-found
  ${OC} -n ${marketplace_namespace} get packagemanifests --ignore-not-found | grep 'Testing Catalog Source' || :

  cmd="${OC} get packagemanifests -n ${marketplace_namespace} ${operator_name} -o json | jq -r '(.status.channels[].currentCSVDesc.version)'"
  regex="${version//[a-zA-Z]}"
  watch_and_retry "$cmd" 3m "$regex" || FATAL "The package ${operator_name} version ${version//[a-zA-Z]} was not found in the CatalogSource '${ACM_CATALOG}'"

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

    # Display operator group
    ${OC} get operatorgroup -n ${namespace} --ignore-not-found
  fi

  TITLE "Create the Subscription (Automatic Approval)"

  cat <<EOF | ${OC} apply -f -
  apiVersion: operators.coreos.com/v1alpha1
  kind: Subscription
  metadata:
    name: ${ACM_SUBSCRIPTION}
    namespace: ${subscriptionNamespace}
  spec:
    channel: ${channel}
    installPlanApproval: Automatic
    name: ${operator_name}
    source: ${ACM_CATALOG}
    sourceNamespace: ${marketplace_namespace}
    startingCSV: ${operator_name}.${version}
EOF

    # echo "# InstallPlan Manual Approve (instead of Automatic), in order to pin the bundle version"
    #
    # # local duration=5m
    # # ${OC} wait --for condition=InstallPlanPending --timeout=${duration} -n ${subscriptionNamespace} subs/${ACM_SUBSCRIPTION} || subscription_status=FAILED
    #
    # local acm_subscription="`mktemp`_acm_subscription"
    # local cmd="${OC} describe subs/${ACM_SUBSCRIPTION} -n "${subscriptionNamespace}" &> '$acm_subscription'"
    # local duration=5m
    # local regex="State:\s*AtLatestKnown|UpgradePending"
    #
    # watch_and_retry "$cmd ; grep -E '$regex' $acm_subscription" "$duration" || :
    # cat $acm_subscription |& highlight "$regex" || subscription_status=FAILED
    #
    # ${OC} describe subs/${ACM_SUBSCRIPTION} -n "${subscriptionNamespace}"
    #
    # if [[ "$subscription_status" = FAILED ]] ; then
    #   FATAL "InstallPlan for '${ACM_SUBSCRIPTION}' subscription in ${subscriptionNamespace} is not ready after $duration"
    # fi
    #
    # installPlan=$(${OC} get subscriptions.operators.coreos.com ${ACM_SUBSCRIPTION} -n "${subscriptionNamespace}" -o jsonpath='{.status.installPlanRef.name}')
    # if [ -n "${installPlan}" ]; then
    #   ${OC} patch installplan -n "${subscriptionNamespace}" "${installPlan}" -p '{"spec":{"approved":true}}' --type merge
    # fi

    TITLE "Display ${subscriptionNamespace} resources"

    ${OC} get sub -n "${subscriptionNamespace}" --ignore-not-found
    ${OC} get installplan -n "${subscriptionNamespace}" --ignore-not-found
    ${OC} get csv -n "${subscriptionNamespace}" --ignore-not-found
    ${OC} get pods -n "${subscriptionNamespace}" --ignore-not-found
    ${OC} get pods -n openshift-operator-lifecycle-manager --ignore-not-found

    TITLE "Display Operator deployments logs"

    ${OC} logs -n openshift-operator-lifecycle-manager deploy/catalog-operator | grep '^E0|Error|Warning' || :
    ${OC} logs -n openshift-operator-lifecycle-manager deploy/olm-operator | grep '^E0|Error|Warning' || :
    
  fi

}
