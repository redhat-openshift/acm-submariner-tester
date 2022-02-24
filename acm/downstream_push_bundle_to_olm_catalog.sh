#!/bin/bash

############ OCP Operators functions ############


### Function to find latest index-image for a bundle in datagrepper.engineering.redhat
function export_LATEST_IIB() {
  trap_to_debug_commands;

  local version="${1}"
  local bundle_name="${2}"

  TITLE "Retrieving index-image from UMB (datagrepper.engineering.redhat) for bundle '${bundle_name}' version '${version}'"

  local index_images

  local umb_url="https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.pipeline.complete"
  local umb_output="latest_iib.txt"
  local iib_query='[.raw_messages[].msg | select(.pipeline.status=="complete") | {nvr: .artifact.nvr, index_image: .pipeline.index_image}] | .[0]'
  # local iib_query='[.raw_messages[].msg | {nvr: .artifact.nvr, index_image: .pipeline.index_image}] | .[0]'

  local num_of_latest_builds=5
  local rows=$((num_of_latest_builds * 5))

  local num_of_days=30
  local delta=$((num_of_days * 86400)) # 1296000 = 15 days * 86400 seconds

  curl --retry 30 --retry-delay 5 -o $umb_output -Ls "${umb_url}&rows_per_page=${rows}&delta=${delta}&contains=${bundle_name}-container-${version}"

  index_images="$(cat $umb_output | jq -r "${iib_query}")"

  # index-images example:
  # {
  # "nvr": "submariner-operator-bundle-container-v0.11.0-6",
  # "index_image": {
  #   "v4.6": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105099",
  #   "v4.7": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105101",
  #   "v4.8": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105104",
  #   "v4.9": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105105"
  # }

  if [[ "$index_images" = null ]]; then
    BUG "Failed to retrieve completed images during the last $num_of_days days, getting all images during delta of 3X${num_of_days} days"
    delta=$((delta * 3))

    curl --retry 30 --retry-delay 5 -o $umb_output -Ls "${umb_url}&rows_per_page=${rows}&delta=${delta}&contains=${bundle_name}-container-${version}"

    cat $umb_output | jq -r "${iib_query}"

    index_images="$(cat $umb_output | jq -r "${iib_query}")"

    if [[ "$index_images" = null ]]; then
      FATAL "Failed to retrieve index-image for bundle '${bundle_name}' version '${version}': $index_images"
    fi
  fi

  local ocp_version_x_y
  ocp_version_x_y=$(${OC} version | awk '/Server Version/ { print $3 }' | cut -d '.' -f 1,2 || :)

  TITLE "Getting index-image according to OCP version '${ocp_version_x_y}' \n $index_images"

  LATEST_IIB=$(echo "$index_images" | jq -r '.index_image."v'"${ocp_version_x_y}"'"' ) || :

  if [[ ! "$LATEST_IIB" =~ iib:[0-9]+ ]]; then
    BUG "No index-image bundle '${bundle_name}' for OCP version '${ocp_version_x_y}'"

    # Find the latest version, after sorting by product versions (not by real numbers), so for example: v4.10 is higher than v4.9

    ocp_version_x_y="$(echo "$index_images" | jq '.index_image | keys | .[]' | sort -V | tail -1)" || :

    TITLE "Getting the last index-image for bundle '${bundle_name}' version '${ocp_version_x_y}'"

    LATEST_IIB=$(echo "$index_images" | jq -r '.index_image.'${ocp_version_x_y} ) || :

    if [[ ! "$LATEST_IIB" =~ iib:[0-9]+ ]]; then
      FATAL "Failed to retrieve index-image for bundle '${bundle_name}' version '${ocp_version_x_y}' from datagrepper.engineering.redhat"
    fi
  fi

  echo "# Exporting LATEST_IIB as: $LATEST_IIB"

  export LATEST_IIB

}

# ------------------------------------------

function deploy_ocp_bundle() {
  ### Deploy OCP Bundle ###

  trap_to_debug_commands;

  # Input args
  local bundle_name="$1"
  local operator_version="$2"
  local operator_name="$3"
  local operator_channel="$4"
  local catalog_source="$5"
  local bundle_namespace="${6:-$MARKETPLACE_NAMESPACE}"

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  TITLE "Import image and create catalog-source for OCP operator bundle '${bundle_name} in cluster ${cluster_name}'
  Bundle Name: ${bundle_name}
  Operator Version: ${operator_version}
  Operator Name: ${operator_name}
  Channel: ${operator_channel}
  Catalog Source: ${catalog_source}
  Bundle Namespace: ${bundle_namespace}
  "

  if [[ -z "${bundle_name}" ]] ||
     [[ -z "${operator_version}" ]] ||
     [[ -z "${operator_name}" ]] ||
     [[ -z "${operator_channel}" ]] ||
     [[ -z "${catalog_source}" ]] ; then
       FATAL "Required parameters for the Bundle installation are missing:
       Bundle Name: ${bundle_name}
       Operator Version: ${operator_version}
       Operator Name: ${operator_name}
       Channel: ${operator_channel}
       Catalog Source: ${catalog_source}"
  fi

  # login to current kubeconfig cluster
  ocp_login "${OCP_USR}" "$(< ${WORKDIR}/${OCP_USR}.sec)"

  ocp_registry_url=$(${OC} registry info --internal)

  echo "# Create/switch project"
  ${OC} new-project "${bundle_namespace}" 2>/dev/null || ${OC} project "${bundle_namespace}" -q

  echo "# Disable the default remote OperatorHub sources for OLM"
  ${OC} patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'

  # Set and export the variable ${LATEST_IIB}
  export_LATEST_IIB "${operator_version}" "${bundle_name}"

  local source_image_path
  source_image_path="${BREW_REGISTRY}/$(echo ${LATEST_IIB} | cut -d'/' -f2-)"

  local bundle_image_name="${bundle_name}-index"

  local target_image_path="${ocp_registry_url}/${bundle_namespace}/${bundle_image_name}:${operator_version}"

  TITLE "Import new Bundle image into cluster ${cluster_name} namespace '${bundle_namespace}'
  Source image path: ${source_image_path}
  Target image path: ${target_image_path}"

  if ${OC} get is "${bundle_image_name}" -n "${bundle_namespace}" > /dev/null 2>&1; then
    echo "# Delete previous Image Stream before importing a new Bundle image '${bundle_image_name}'"
    ${OC} delete is "${bundle_image_name}" -n "${bundle_namespace}" --wait
  fi

  ${OC} import-image "${target_image_path}" --from="${source_image_path}" -n "${bundle_namespace}" --confirm \
  | grep -E 'com.redhat.component|version|release|com.github.url|com.github.commit|vcs-ref'


  TITLE "Create the CatalogSource '${catalog_source}' in cluster ${cluster_name} for image: ${source_image_path}"

  echo "# Delete previous catalogSource if exists"
  ${OC} delete catalogsource/${catalog_source} -n "${bundle_namespace}" --wait --ignore-not-found || :

  local catalog_display_name="${bundle_name} Catalog Source"

    cat <<EOF | ${OC} apply -n ${bundle_namespace} -f -
    apiVersion: operators.coreos.com/v1alpha1
    kind: CatalogSource
    metadata:
      name: ${catalog_source}
      namespace: ${bundle_namespace}
    spec:
      sourceType: grpc
      image: ${target_image_path}
      displayName: ${catalog_display_name}
      publisher: Red Hat Partner (Test)
      # updateStrategy:
      #   registryPoll:
      #     interval: 5m
EOF

  echo "# Wait for CatalogSource '${catalog_source}' to be created:"

  cmd="${OC} get catalogsource -n ${bundle_namespace} ${catalog_source} -o jsonpath='{.status.connectionState.lastObservedState}'"
  watch_and_retry "$cmd" 5m "READY" || FATAL "ACM CatalogSource '${catalog_source}' was not created"

  ${OC} -n ${bundle_namespace} get catalogsource -o yaml --ignore-not-found

  TITLE "Verify that the Package Manifest '${operator_name}' includes the required '${catalog_display_name}', channel '${operator_channel}' and version '${operator_version}' before installing the Bundle '${bundle_name}'"

  local packagemanifests_status

  ${OC} -n ${bundle_namespace} get packagemanifests --ignore-not-found \
  |& highlight "${catalog_display_name}" || packagemanifests_status=FAILED

  cmd="${OC} get packagemanifests -n ${bundle_namespace} ${operator_name} -o json | jq -r '(.status.channels[].name)'"
  regex="${operator_channel}"
  watch_and_retry "$cmd" 3m "$regex" || packagemanifests_status=FAILED

  cmd="${OC} get packagemanifests -n ${bundle_namespace} ${operator_name} -o json | jq -r '(.status.channels[].currentCSVDesc.version)'"
  regex="${operator_version//[a-zA-Z]}"
  watch_and_retry "$cmd" 3m "$regex" || packagemanifests_status=FAILED

  TITLE "Display OLM and ${bundle_namespace} pods in cluster ${cluster_name}"

  ${OC} -n ${bundle_namespace} get pods --ignore-not-found
  ${OC} get pods -n openshift-operator-lifecycle-manager --ignore-not-found

  TITLE "Display OLM Operator deployment logs in cluster ${cluster_name}"

  ${OC} logs -n openshift-operator-lifecycle-manager deploy/olm-operator \
  --all-containers --limit-bytes=100000 --since=1h | grep -E '^E0|Error|Warning' || :

  TITLE "Display Catalog Operator deployment logs in cluster ${cluster_name}"

  ${OC} logs -n openshift-operator-lifecycle-manager deploy/catalog-operator \
  --all-containers --limit-bytes=10000 --since=10m | grep -E '^E0|Error|Warning' || :

  if [[ "$packagemanifests_status" = FAILED ]] ; then
    FAILURE "Package Manifest '${operator_name}' did not include either '${catalog_display_name}', channel '${operator_channel}' or '${operator_version}'"
  fi

}

# ------------------------------------------

function create_subscription() {
  ### Create Subscription for an Operator ###

  trap_to_debug_commands;

  # Input args
  local subscription_display_name="$1"
  local operator_name="$2"
  local operator_version="$3"
  local operator_channel="$4"
  local catalog_source="$5"

  # Optional args: "openshift-operators" or "openshift-marketplace" are only required if deploying as a global operator
  local operator_namespace="${6:-$OPERATORS_NAMESPACE}"
  local subscription_namespace="${6:-$MARKETPLACE_NAMESPACE}"

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  echo "# Delete previous Subscription '${subscription_display_name}' if exists"
  ${OC} delete sub/${subscription_display_name} -n "${subscription_namespace}" --wait --ignore-not-found || :

  if [[ -n "${operator_namespace}" ]]; then
    local operator_group_name="my-${operator_name}-group"
    TITLE "Create the OperatorGroup '${operator_group_name}' for the Operator in a target namespace '${operator_namespace}' in cluster ${cluster_name}"

    cat <<EOF | ${OC} apply -f -
    apiVersion: operators.coreos.com/v1alpha2
    kind: OperatorGroup
    metadata:
      name: ${operator_group_name}
      namespace: ${operator_namespace}
    spec:
      targetNamespaces:
      - ${operator_namespace}
EOF

    echo "# Display all Operator Groups in '${operator_namespace}' namespace"
    ${OC} get operatorgroup -n ${operator_namespace} --ignore-not-found
  fi

  TITLE "Apply InstallPlan with 'Manual' approval (instead of 'Automatic'), in order to pin the Operator version (startingCSV) to '${operator_name}.${operator_version}'"

  cat <<EOF | ${OC} apply -f -
  apiVersion: operators.coreos.com/v1alpha1
  kind: Subscription
  metadata:
    name: ${subscription_display_name}
    namespace: ${subscription_namespace}
  spec:
    channel: ${operator_channel}
    installPlanApproval: Manual
    name: ${operator_name}
    source: ${catalog_source}
    sourceNamespace: ${operator_namespace}
    startingCSV: ${operator_name}.${operator_version}
EOF

  local duration=5m
  echo "# Wait $duration for Subscription '${subscription_display_name}' status to be 'AtLatestKnown' or 'UpgradePending'"

  local subscription_status
  # ${OC} wait --for condition=InstallPlanPending --timeout=${duration} -n ${subscription_namespace} subs/${subscription_display_name} || subscription_status=FAILED

  local acm_subscription="`mktemp`_acm_subscription"
  local cmd="${OC} describe subs/${subscription_display_name} -n "${subscription_namespace}" &> '$acm_subscription'"
  local regex="State:\s*AtLatestKnown|UpgradePending"

  watch_and_retry "$cmd ; grep -E '$regex' $acm_subscription" "$duration" || :

  if cat $acm_subscription |& highlight "$regex" ; then

    local installPlan
    installPlan="$(${OC} get subscriptions.operators.coreos.com ${subscription_display_name} -n "${subscription_namespace}" -o jsonpath='{.status.installPlanRef.name}')" || :

    if [[ -n "${installPlan}" ]] ; then
      ${OC} patch installplan -n "${subscription_namespace}" "${installPlan}" -p '{"spec":{"approved":true}}' --type merge || subscription_status=FAILED
    fi

  else
    subscription_status=FAILED
  fi

  TITLE "Display Subscription resources of namespace '${subscription_namespace}' in cluster ${cluster_name}"

  ${OC} get sub -n "${subscription_namespace}" --ignore-not-found
  ${OC} get installplan -n "${subscription_namespace}" --ignore-not-found
  ${OC} get csv -n "${subscription_namespace}" --ignore-not-found
  ${OC} get pods -n "${subscription_namespace}" --ignore-not-found

  if [[ "$subscription_status" = FAILED ]] ; then
    FAILURE "InstallPlan for the Subscription '${subscription_display_name}' of Operator '${operator_name}' could not be created"
  fi

}
