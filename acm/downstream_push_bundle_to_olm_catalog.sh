#!/bin/bash
# shellcheck disable=SC2153,SC2031,SC2016,SC2120,SC2005,SC1091

############ OCP Operators functions ############

# ------------------------------------------

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

  local num_of_latest_builds=5
  local rows=$((num_of_latest_builds * 5))

  local num_of_days=30
  local delta=$((num_of_days * 86400)) # 1296000 = 15 days * 86400 seconds

  curl --retry 30 --retry-delay 5 -o $umb_output -Ls "${umb_url}&rows_per_page=${rows}&delta=${delta}&contains=${bundle_name}-container-${version}"

  index_images="$(jq -r "${iib_query}" $umb_output)" || :

  # index-images example:
  # {
  # "nvr": "submariner-operator-bundle-container-v0.11.0-6",
  # "index_image": {
  #   "v4.6": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105099",
  #   "v4.7": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105101",
  #   "v4.8": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105104",
  #   "v4.9": "registry-proxy.engineering.redhat.com/rh-osbs/iib:105105"
  # }

  # If no image was found - increase the delta
  if [[ -z "$index_images" || "$index_images" == null ]]; then
    BUG "Failed to retrieve images during the last $num_of_days days - Searching images during delta of 3X${num_of_days} days"
    
    delta=$((delta * 3))

    curl --retry 30 --retry-delay 5 -o $umb_output -Ls "${umb_url}&rows_per_page=${rows}&delta=${delta}&contains=${bundle_name}-container-${version}"

    index_images="$(jq -r "${iib_query}" $umb_output)" || :

    # If still no image found - ignore non-completed pipelines
    if [[ -z "$index_images" || "$index_images" == null ]]; then
      BUG "Failed to retrieve images during the last 3X${num_of_days} days - Searching images in non-completed pipelines"

      iib_query='[.raw_messages[].msg | {nvr: .artifact.nvr, index_image: .pipeline.index_image}] | .[0]'

      index_images="$(jq -r "${iib_query}" $umb_output)" || :
    fi
  fi

  if [[ -z "$index_images" || "$index_images" == null ]]; then
    FATAL "Failed to retrieve index-image for bundle '${bundle_name}' version '${version}': $index_images"
  else
    echo "$index_images"
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

    LATEST_IIB=$(echo "$index_images" | jq -r '.index_image.'"${ocp_version_x_y}" ) || :

    if [[ ! "$LATEST_IIB" =~ iib:[0-9]+ ]]; then
      FATAL "Failed to retrieve index-image for bundle '${bundle_name}' version '${ocp_version_x_y}' from datagrepper.engineering.redhat"
    fi
  fi

  echo -e "\n# Exporting LATEST_IIB as: $LATEST_IIB"

  export LATEST_IIB

}

# ------------------------------------------

function deploy_ocp_bundle() {
  ### Deploy OCP Bundle ###

  trap_to_debug_commands;

  # Input args:
  local bundle_name="$1"
  local operator_version="$2"
  local operator_name="$3"
  local operator_channel="$4"

  # Optional args:
  local catalog_source="${5:-${operator_name}-${operator_channel}-catalog}"
  local bundle_namespace="${6:-$MARKETPLACE_NAMESPACE}"

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  # Replace anything but letters and numbers with "-" (required for the catalog source metadata.name)
  catalog_source="${catalog_source//[^a-zA-Z0-9]/-}"

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
  ocp_login "${OCP_USR}" "$(< "${WORKDIR}/${OCP_USR}.sec")"

  ocp_registry_url=$(${OC} registry info --internal)

  echo -e "\n# Create/switch project"
  ${OC} new-project "${bundle_namespace}" || ${OC} project "${bundle_namespace}" -q

  echo -e "\n# Disable the default remote OperatorHub sources for OLM"
  ${OC} patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'

  # Set and export the variable ${LATEST_IIB}
  export_LATEST_IIB "${operator_version}" "${bundle_name}"

  local source_image_path
  source_image_path="${BREW_REGISTRY}/$(echo "${LATEST_IIB}" | cut -d'/' -f2-)"

  local bundle_image_name="${bundle_name}-index"

  local target_image_path="${ocp_registry_url}/${bundle_namespace}/${bundle_image_name}:${operator_version}"

  TITLE "Import new Bundle image into cluster ${cluster_name} namespace '${bundle_namespace}'
  Source image path: ${source_image_path}
  Target image path: ${target_image_path}"

  if ${OC} get is "${bundle_image_name}" -n "${bundle_namespace}" > /dev/null 2>&1; then
    echo -e "\n# Delete previous Image Stream before importing a new Bundle image '${bundle_image_name}'"
    ${OC} delete is "${bundle_image_name}" -n "${bundle_namespace}" --wait
  fi

  # ${OC} import-image "${target_image_path}" --from="${source_image_path}" -n "${bundle_namespace}" --confirm \
  # | grep -E 'com.redhat.component|version|release|com.github.url|com.github.commit|vcs-ref'

  local cmd="${OC} import-image ${target_image_path} --from=${source_image_path} -n ${bundle_namespace} --confirm"

  watch_and_retry "$cmd" 3m "Image Name:\s+${bundle_image_name}"

  TITLE "Create the CatalogSource '${catalog_source}' in cluster ${cluster_name} for image: ${source_image_path}"

  # echo -e "\n# Delete previous catalogSource if exists"
  # ${OC} delete catalogsource/${catalog_source} -n "${bundle_namespace}" --wait --ignore-not-found || :

  local catalog_display_name="${bundle_name}-${operator_channel} Catalog Source"

    cat <<EOF | ${OC} apply -n "${bundle_namespace}" -f -
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
      updateStrategy:
        registryPoll:
          interval: 5m
EOF

  echo -e "\n# Wait for CatalogSource '${catalog_source}' to be created:"

  cmd="${OC} get catalogsource -n ${bundle_namespace} ${catalog_source} -o jsonpath='{.status.connectionState.lastObservedState}'"
  watch_and_retry "$cmd" 5m "READY" || FATAL "${bundle_namespace} CatalogSource '${catalog_source}' was not created"

  ${OC} -n "${bundle_namespace}" get catalogsource -o yaml --ignore-not-found

  TITLE "Verify the Package Manifest before installing Bundle '${bundle_name}':
  Catalog: ${catalog_display_name}
  Operator: ${operator_name}
  Channel: ${operator_channel}
  Version ${operator_version}
  "

  local packagemanifests_status

  cmd="${OC} get packagemanifests -n ${bundle_namespace}"
  regex="${catalog_display_name}"
  watch_and_retry "$cmd" 3m "$regex" || packagemanifests_status=FAILED

  cmd="${OC} get packagemanifests -n ${bundle_namespace} ${operator_name} -o json | jq -r '(.status.channels[].name)'"
  regex="${operator_channel}"
  watch_and_retry "$cmd" 3m "$regex" || packagemanifests_status=FAILED

  cmd="${OC} get packagemanifests -n ${bundle_namespace} ${operator_name} -o json | jq -r '(.status.channels[].currentCSVDesc.version)'"
  regex="${operator_version//[a-zA-Z]}"
  watch_and_retry "$cmd" 3m "$regex" || packagemanifests_status=FAILED

  TITLE "Display running pods in Bundle namespace ${bundle_namespace} in cluster ${cluster_name}"

  ${OC} -n "${bundle_namespace}" get pods |& (! highlight "Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|No resources found") \
  || packagemanifests_status=FAILED

  if [[ "$packagemanifests_status" == FAILED ]] ; then
    FAILURE "Bundle ${bundle_name} failed either due to Package Manifest '${operator_name}', Catalog '${catalog_display_name}', \
    Channel '${operator_channel}', Version '${operator_version}', or Images deployment"
  fi

}

# ------------------------------------------

function check_olm_in_current_cluster() {
  ### Check OLM pods and logs ###

  trap_to_debug_commands;

  local kubeconfig_file="$1"
  export KUBECONFIG="$kubeconfig_file"

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  local olm_status

  PROMPT "Check OLM status in cluster ${cluster_name}"

  ${OC} get pods -n openshift-operator-lifecycle-manager --ignore-not-found

  TITLE "Check OLM Operator deployment logs in cluster ${cluster_name}"

  ${OC} logs -n openshift-operator-lifecycle-manager deploy/olm-operator \
  --all-containers --limit-bytes=100000 --since=10m --timestamps \
  |& (! highlight '^E0|"error"|level=error') || olm_status=FAILED

  TITLE "Check OLM Catalog deployment logs in cluster ${cluster_name}"

  ${OC} logs -n openshift-operator-lifecycle-manager deploy/catalog-operator \
  --all-containers --tail=15 --timestamps \
  |& (! highlight '^E0|"error"|level=error') || olm_status=FAILED

  if [[ "$olm_status" == FAILED ]] ; then
    FAILURE "OLM deployment logs have some failures/warnings, please investigate"
  fi

}

# ------------------------------------------

function create_subscription() {
  ### Create Subscription for an Operator ###
  # Ref: https://github.com/stolostron/release/blob/master/doc/how-to-orchestrate-operator-upgrade.md
  
  trap_to_debug_commands;

  # Input args
  local operator_name="$1"
  local operator_channel="$2"

  # Optional input args:

  # Catalog source name
  local catalog_source="${3:-${operator_name}-${operator_channel}-catalog}"
  # To set a specific version of an Operator CSV with a Manual subscription (prevent automatic updates for newer versions in the channel):
  local operator_version="$4"
  # To deploy in a specified namespace, and not as a global operator (within "openshift-operators" and "openshift-marketplace" namespaces)
  local operator_namespace="$5"

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  # Replace anything but letters and numbers with "-" (required for the catalog source metadata.name)
  catalog_source="${catalog_source//[^a-zA-Z0-9]/-}"

  local subscription_namespace

  # Create the OperatorGroup
  if [[ -n "${operator_namespace}" ]]; then
    local operator_group_name="my-${operator_namespace}-operators-group"
    subscription_namespace="${operator_namespace}"

    TITLE "Create one OperatorGroup '${operator_group_name}' in the specified namespace '${operator_namespace}' of cluster ${cluster_name}"

    ${OC} delete operatorgroup --all -n "${operator_namespace}" --wait || :

    cat <<EOF | ${OC} apply -f -
    apiVersion: operators.coreos.com/v1
    kind: OperatorGroup
    metadata:
      name: ${operator_group_name}
      namespace: ${operator_namespace}
    spec:
      targetNamespaces:
      - ${operator_namespace}
EOF

    echo -e "\n# Display all Operator Groups in '${operator_namespace}' namespace"
    ${OC} get operatorgroup -n "${operator_namespace}" --ignore-not-found

  else
    TITLE "Deploying as a global Operator in the Openshift marketplace of cluster ${cluster_name}"
    operator_namespace="${OPERATORS_NAMESPACE}"
    subscription_namespace="${MARKETPLACE_NAMESPACE}"

  fi

  # Create the Subscription
  local subscription_display_name="${operator_name}-${operator_channel}-subscription"
  TITLE "Create Subscription '${subscription_display_name}' to Catalog Source '${catalog_source}' in namespace '${subscription_namespace}'"

  BUG "Upgrading ACM major version can fail if InstallPlan not generated by Subscription" \
  "Delete previous ACM Subscription and CSV, before creating new Subscription" \
  "https://bugzilla.redhat.com/show_bug.cgi?id=2078543"
  # Workaround:

  echo -e "\n# Delete previous Subscription '${subscription_display_name}' if exists"
  # ${OC} delete sub/${subscription_display_name} -n "${subscription_namespace}" --wait --ignore-not-found || :
  ${OC} delete subs --all -n "${subscription_namespace}" --wait --ignore-not-found || :
  ${OC} delete csv --all -n "${subscription_namespace}" --wait --ignore-not-found || :

  echo -e "\n# Create new Subscription '${subscription_display_name}' for Operator '${operator_name}' with the required Install Plan Approval"
  local install_plan_approval
  local starting_csv

  if [[ -n "${operator_version}" ]] ; then
    echo -e "\n# Specific ${operator_name} version was requested - Apply Manual installPlanApproval and startingCSV: ${starting_csv}"
    install_plan_approval="Manual"
    starting_csv="${operator_name}.${operator_version}"

    # BUG "There might be a bug in OCP - if not defining CSV (but just the channel), it pulls base CSV version, and not latest" \
    # "Use Automatic installPlanApproval (instead of Manual)"
    # # Workaround:
    # install_plan_approval="Automatic"

  else
    echo -e "\n# No specific ${operator_name} version was requested - Apply Automatic installPlanApproval"
    install_plan_approval="Automatic"

  fi

  cat <<EOF | ${OC} apply -f -
  apiVersion: operators.coreos.com/v1alpha1
  kind: Subscription
  metadata:
    name: ${subscription_display_name}
    namespace: ${subscription_namespace}
  spec:
    channel: ${operator_channel}
    installPlanApproval: ${install_plan_approval}
    name: ${operator_name}
    source: ${catalog_source}
    sourceNamespace: ${operator_namespace}
    ${starting_csv:+startingCSV: $starting_csv}
EOF

  local duration=3m
  echo -e "\n# Wait $duration for Subscription '${subscription_display_name}' status to be 'AtLatestKnown' or 'UpgradePending'"

  local subscription_status
  # ${OC} wait --for condition=InstallPlanPending --timeout=${duration} -n ${subscription_namespace} subs/${subscription_display_name} || subscription_status=FAILED

  local subscription_data
  subscription_data="$(mktemp)_subscription_data"
  local cmd="${OC} describe subs/${subscription_display_name} -n ${subscription_namespace} &> '$subscription_data'"
  local regex="State:\s*AtLatestKnown|UpgradePending"

  watch_and_retry "$cmd ; grep -E '$regex' $subscription_data" "$duration" || :

  if highlight "$regex" "$subscription_data" ; then

    local install_plan_name
    install_plan_name="$(${OC} get subscriptions.operators.coreos.com "${subscription_display_name}" -n "${subscription_namespace}" -o jsonpath='{.status.installPlanRef.name}')" || :

    if [[ -n "${install_plan_name}" ]] ; then
      ${OC} patch installplan -n "${subscription_namespace}" "${install_plan_name}" -p '{"spec":{"approved":true}}' --type merge || subscription_status=FAILED
    fi

  else
    subscription_status=FAILED
  fi

  TITLE "Display Subscription resources of '${subscription_namespace}' in cluster ${cluster_name}"

  ${OC} get sub -n "${subscription_namespace}" --ignore-not-found
  ${OC} get csv -n "${subscription_namespace}" --ignore-not-found
  ${OC} get pods -n "${subscription_namespace}" --ignore-not-found

  TITLE "Verify Install Plan created for '${subscription_namespace}' in cluster ${cluster_name}"

  ${OC} wait installplan --all -n "${subscription_namespace}" --for condition=Installed --timeout="$duration" || subscription_status=FAILED

  local cmd="${OC} get installplan -n ${subscription_namespace} -o json | jq -r 'del(.items[].status.plan[].resource.manifest)'"

  watch_and_retry "$cmd" "$duration" || subscription_status=FAILED

  if [[ "$subscription_status" == FAILED ]] ; then
    cat "${subscription_data}"
    FAILURE "InstallPlan '${install_plan_name}' or Subscription '${subscription_display_name}' for Operator '${operator_name}' could not be created"
  fi

}

# ------------------------------------------

function get_channel_name() {
  ### Generate and print Subscription Channel from a defined perfix and version number ###

  local prefix="$1"
  local version="$2"

  local regex_to_major_minor='[0-9]+\.[0-9]+'

  # Trim version into major.minor (X.Y.Z ==> X.Y)
  version="$(echo "$version" | grep -Po "$regex_to_major_minor")"

  # Print channel, after trimming version into major.minor (X.Y.Z ==> X.Y)
  echo "${prefix}${version}"

}

# ------------------------------------------

function get_catalog_name() {
  ### Generate and print Catalog Source name from Operator and Channel ###

  local operator_name="$1"
  local channel_name="$2"

  # Catalog source name
  local catalog_source="${operator_name}-${channel_name}-catalog"

  # Replace anything but letters and numbers with "-" (required for the catalog source metadata.name)
  echo "${catalog_source//[^a-zA-Z0-9]/-}"

}

# ------------------------------------------
