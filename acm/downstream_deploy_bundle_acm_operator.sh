#!/bin/bash

############ ACM and Submariner operator installation functions ############

# ------------------------------------------

function remove_multicluster_engine() {
### Removing Multi Cluster Engine from ACM hub (if exists) ###
  trap_to_debug_commands;

  # Following steps should be run on ACM MultiClusterHub with $KUBECONF_HUB (NOT with the managed cluster kubeconfig)
  export KUBECONFIG="${KUBECONF_HUB}"

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Removing Multi Cluster Engine from cluster: $cluster_name"

  ${OC} get all -n multicluster-engine || echo -e "\n# MultiClusterEngine is not installed" && exit

  TITLE "Deleting the multiclusterengine custom resource"

  ${OC} delete multiclusterengine --all --timeout=30s || :

  TITLE "Deleting the MultiCluster Engine CSV, Subscription, and namespace"

  ${OC} delete csv --all -n ${MCE_NAMESPACE} --timeout=30s || :
  ${OC} delete subs --all -n ${MCE_NAMESPACE} --timeout=30s || :

  force_delete_namespace "${MCE_NAMESPACE}"
  force_delete_namespace "${MCE_NAMESPACE}"

}

# ------------------------------------------

function remove_acm_managed_cluster() {
### Removing Cluster-ID from ACM managed clusters (if exists) ###
  trap_to_debug_commands;

  local kubeconfig_file="$1"

  export KUBECONFIG="$kubeconfig_file"

  local cluster_id
  cluster_id="acm-$(print_current_cluster_name || :)"

  PROMPT "Removing the ACM Managed Cluster ID: $cluster_id"

  # Following steps should be run on ACM MultiClusterHub with $KUBECONF_HUB (NOT with the managed cluster kubeconfig)
  export KUBECONFIG="${KUBECONF_HUB}"

  ocp_login "${OCP_USR}" "$(< ${WORKDIR}/${OCP_USR}.sec)"

  ${OC} get managedcluster -o wide || :

  if ${OC} get managedcluster ${cluster_id} ; then
    ${OC} delete managedcluster ${cluster_id} --timeout=30s || force_managedcluster_delete=TRUE

    if [[ "$force_managedcluster_delete" = TRUE && $(${OC} get managedcluster ${cluster_id}) ]]; then
      TITLE "Resetting finalizers of managed cluster '${cluster_id}' and force deleting its namespace"

      ${OC} patch managedcluster ${cluster_id} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' || :

      force_delete_namespace "${cluster_id}"
    fi

  else
    echo -e "\n# ACM does not have the managed cluster '$cluster_id' (skipping removal)"
  fi

}

# ------------------------------------------

function clean_acm_namespace_and_resources() {
### Uninstall ACM MultiClusterHub ###
  PROMPT "Cleaning previous ACM (${ACM_INSTANCE}, Subscriptions, CSVs, Namespace) on cluster A"
  trap_to_debug_commands;

  # Run on ACM MultiClusterHub cluster (Manager)
  export KUBECONFIG="${KUBECONF_HUB}"

  local acm_uninstaller_url="https://raw.githubusercontent.com/open-cluster-management/deploy/master/multiclusterhub/uninstall.sh"
  local acm_uninstaller_file="./acm_cleanup.sh"

  download_file "${acm_uninstaller_url}" "${acm_uninstaller_file}"
  chmod +x "${acm_uninstaller_file}"

  export TARGET_NAMESPACE="${ACM_NAMESPACE}"
  ${acm_uninstaller_file} || FAILURE "Uninstalling ACM MultiClusterHub did not complete successfully"

  # TODO: Use script from https://github.com/open-cluster-management/acm-qe/wiki/Cluster-Life-Cycle-Component
    # https://raw.githubusercontent.com/open-cluster-management/deploy/master/hack/cleanup-managed-cluster.sh
    # https://github.com/open-cluster-management/endpoint-operator/raw/master/hack/hub-detach.sh

  BUG "ACM uninstaller script does not delete all resources" \
  "Delete ACM resources directly" \
  "https://github.com/open-cluster-management/deploy/issues/218"
  # Workaround:

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  TITLE "Delete global CRDs, Managed Clusters, and Validation Webhooks of ACM in cluster ${cluster_name}"

  delete_crds_by_name "open-cluster-management" || :
  ${OC} delete MultiClusterEngine --all --wait || :
  ${OC} delete managedcluster --all --wait || :
  ${OC} delete validatingwebhookconfiguration --all --wait || :
  ${OC} delete manifestwork --all --wait || :

  TITLE "Delete all MCE and ACM resources in cluster ${cluster_name}"

  ${OC} delete subs --all -n ${MCE_NAMESPACE} --wait || :
  ${OC} delete subs --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete catalogsource --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete is --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete ${ACM_INSTANCE} --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete csv --all -n ${MCE_NAMESPACE} --wait || :
  ${OC} delete csv --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete cm --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete service --all -n ${ACM_NAMESPACE} --wait || :

  ${OC} delete namespace ${ACM_NAMESPACE} || :
  ${OC} delete namespace ${MCE_NAMESPACE} || :
  ${OC} wait --for=delete namespace ${ACM_NAMESPACE} || :

  # force_delete_namespace "${ACM_NAMESPACE}" 10m || :

}

# ------------------------------------------

function print_major_minor_version() {
  ### Trim version into major.minor (X.Y.Z ==> X.Y) ###

  local full_numeric_version="$1"
  local regex_to_major_minor='[0-9]+\.[0-9]+'
  echo "$full_numeric_version" | grep -Po "$regex_to_major_minor"

}

# ------------------------------------------

function install_mce_operator_on_hub() {
  ### Install MCE operator - It should be run only on the Hub cluster ###
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"

  local mce_version="v${2:-$MCE_VER_TAG}" # e.g. v2.2.0

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Install MCE $mce_version bundle on the Hub cluster ${cluster_name}"

  # TODO: Move the following logic into deploy_ocp_bundle

  local mce_current_version
  mce_current_version="$(${OC} get MultiClusterEngine -n "${MCE_NAMESPACE}" ${MCE_INSTANCE} -o jsonpath='{.status.currentVersion}' 2>/dev/null)" || :

  # Install MCE if it's not installed, or if it's already installed, but with a different version than requested
  if [[ "$mce_version" != "$mce_current_version" ]] ; then

    if [[ -z "$mce_current_version" ]] ; then
      echo -e "\n# MCE is not installed on current cluster ${cluster_name} - Installing MCE $mce_version from scratch"
    else
      echo -e "\n# MCE $mce_current_version is already installed on current cluster ${cluster_name} - Re-installing MCE $mce_version"
    fi

    local mce_channel
    mce_channel="${MCE_CHANNEL_PREFIX}$(print_major_minor_version "$mce_version")"

    TITLE "Install MCE bundle $mce_version in namespace '${MCE_NAMESPACE}' on the Hub ${cluster_name}
    Catalog: ${MCE_CATALOG}
    Channel: ${mce_channel}
    "

    # Deploy MCE operator as an OCP bundle
    deploy_ocp_bundle "${MCE_BUNDLE}" "${mce_version}" "${MCE_OPERATOR}" "${mce_channel}" "${MCE_CATALOG}" "${MCE_NAMESPACE}"
    echo -e "\n# MCE $mce_version installation completed"

  else
    TITLE "MCE version $mce_version is already installed on current cluster ${cluster_name} - Skipping MCE installation"
  fi

}

# ------------------------------------------

function install_acm_operator_on_hub() {
  ### Install ACM operator - It should be run only on the Hub cluster ###
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"

  local acm_version="v${1:-$ACM_VER_TAG}" # e.g. v2.5.0

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Install ACM $acm_version bundle on the Hub cluster ${cluster_name}"

  # TODO: Move the following logic into deploy_ocp_bundle

  local acm_current_version
  acm_current_version="$(${OC} get MultiClusterHub -n "${ACM_NAMESPACE}" ${ACM_INSTANCE} -o jsonpath='{.status.currentVersion}' 2>/dev/null)" || :

  # Install ACM if it's not installed, or if it's already installed, but with a different version than requested
  if [[ "$acm_version" != "$acm_current_version" ]] ; then

    if [[ -z "$acm_current_version" ]] ; then
      echo -e "\n# ACM is not installed on current cluster ${cluster_name} - Installing ACM $acm_version from scratch"
    else
      echo -e "\n# ACM $acm_current_version is already installed on current cluster ${cluster_name} - Re-installing ACM $acm_version"
    fi

    # Deploy ACM operator as an OCP bundle
    local acm_channel
    acm_channel="${ACM_CHANNEL_PREFIX}$(print_major_minor_version "$acm_version")"

    TITLE "Install ACM bundle $acm_version in namespace '${ACM_NAMESPACE}' on the Hub ${cluster_name}
    Catalog: ${ACM_CATALOG}
    Channel: ${mce_channel}
    "

    deploy_ocp_bundle "${ACM_BUNDLE}" "${acm_version}" "${ACM_OPERATOR}" "${acm_channel}" "${ACM_CATALOG}" "${ACM_NAMESPACE}"
    echo -e "\n# ACM $acm_version installation completed"

  else
    TITLE "ACM version $acm_version is already installed on current cluster ${cluster_name} - Skipping ACM installation"
  fi

}

# ------------------------------------------

function create_mce_subscription() {
  ### Create MCE subscription - It should be run only on the Hub cluster ###
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"

  local mce_version="v${1:-$MCE_VER_TAG}" # e.g. v2.2.0

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Create Automatic Subscription for ${MCE_OPERATOR} in ${MCE_NAMESPACE} (catalog ${MCE_CATALOG}) on cluster ${cluster_name}"

  local mce_channel
  mce_channel="${MCE_CHANNEL_PREFIX}$(print_major_minor_version "$mce_version")"

  # Create Automatic Subscription (channel without a specific version) for MCE operator
  create_subscription "${MCE_CATALOG}" "${MCE_OPERATOR}" "${mce_channel}" "" "${MCE_NAMESPACE}"

  # # Create Automatic Subscription with a specific version for MCE operator
  # create_subscription "${MCE_CATALOG}" "${MCE_OPERATOR}" "${mce_channel}" "${mce_version}" "${MCE_NAMESPACE}"

  echo -e "\n# ACM Subscription for "${MCE_OPERATOR}" is ready"

}

# ------------------------------------------

function create_acm_subscription() {
  ### Create ACM subscription - It should be run only on the Hub cluster ###
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"

  local acm_version="v${1:-$ACM_VER_TAG}" # e.g. v2.5.0

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Create Automatic Subscription for ${ACM_OPERATOR} in ${ACM_NAMESPACE} (catalog ${ACM_CATALOG}) on cluster ${cluster_name}"

  local acm_channel
  acm_channel="${ACM_CHANNEL_PREFIX}$(print_major_minor_version "$acm_version")"

  # Create Automatic Subscription (channel without a specific version) for ACM operator
  create_subscription "${ACM_CATALOG}" "${ACM_OPERATOR}" "${acm_channel}" "" "${ACM_NAMESPACE}"

  # # Create Automatic Subscription with a specific version for ACM operator
  # create_subscription "${ACM_CATALOG}" "${ACM_OPERATOR}" "${acm_channel}" "${acm_version}" "${ACM_NAMESPACE}"

  echo -e "\n# ACM Subscription for "${ACM_OPERATOR}" is ready"

}

# ------------------------------------------

function create_multicluster_engine() {
  ### Create MCE instance ###
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Create Multi-Cluster Engine on cluster ${cluster_name}"

  echo -e "\n# Verify that the MultiClusterEngine CRD exists in cluster ${cluster_name}"

  cmd="${OC} get crd multiclusterengines.multicluster.openshift.io"
  watch_and_retry "$cmd" 5m || FATAL "MultiClusterEngine CRD does not exist in cluster ${cluster_name}"

  TITLE "Create the MultiClusterEngine in namespace ${MCE_NAMESPACE} on cluster ${cluster_name}"

  cat <<EOF | ${OC} apply -f -
  apiVersion: multicluster.openshift.io/v1
  kind: MultiClusterEngine
  metadata:
    name: ${MCE_INSTANCE}
    namespace: ${MCE_NAMESPACE}
  spec: {}
EOF

  {
    TITLE "Wait for MCE instance '${MCE_INSTANCE}' to be available"
    local duration=15m
    cmd="${OC} get MultiClusterEngine ${MCE_INSTANCE} -n ${MCE_NAMESPACE}"
    watch_and_retry "$cmd" "$duration" "Available"

  } || acm_status=FAILED

  TITLE "All MultiClusterEngine resources status:"
  ${OC} get MultiClusterEngine -A -o json | jq -r '.items[].status' || :

  if [[ "$acm_status" = FAILED ]] ; then
    FATAL "MultiClusterEngine is not ready after $duration"
  fi

  local mce_current_version
  mce_current_version="$(${OC} get MultiClusterEngine -n "${MCE_NAMESPACE}" ${MCE_INSTANCE} -o jsonpath='{.status.currentVersion}')" || :

  echo -e "\n# MultiClusterEngine version '${mce_current_version}' is installed"
  # TITLE "MCE ${mce_current_version} console url: $(${OC} get routes -n ${MCE_NAMESPACE} multicloud-console --no-headers -o custom-columns='URL:spec.host')"

}

# ------------------------------------------

function create_acm_multiclusterhub() {
  ### Create ACM MultiClusterHub instance ###
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Create ACM MultiClusterHub instance on cluster ${cluster_name}"

  echo -e "\n# Verify that the MultiClusterHub CRD exists in cluster ${cluster_name}"

  cmd="${OC} get crd multiclusterhubs.operator.open-cluster-management.io"
  watch_and_retry "$cmd" 5m || FATAL "MultiClusterHub CRD does not exist in cluster ${cluster_name}"

  TITLE "Create the MultiClusterHub in namespace ${ACM_NAMESPACE} on cluster ${cluster_name}"

  cat <<EOF | ${OC} apply -f -
  apiVersion: operator.open-cluster-management.io/v1
  kind: MultiClusterHub
  metadata:
    name: ${ACM_INSTANCE}
    namespace: ${ACM_NAMESPACE}
    annotations: {}
  spec:
    disableHubSelfManagement: true
EOF

  {
    TITLE "Wait for ACM console url to be available"
    local duration=15m
    cmd="${OC} get routes -n ${ACM_NAMESPACE} multicloud-console --no-headers -o custom-columns='URL:spec.host'"
    watch_and_retry "$cmd" "$duration"

    TITLE "Wait for ACM Instance '${ACM_INSTANCE}' to be running"
    # cmd="${OC} get MultiClusterHub ${ACM_INSTANCE} -o jsonpath='{.status.phase}'"
    cmd="${OC} get MultiClusterHub ${ACM_INSTANCE} -n ${ACM_NAMESPACE}"
    watch_and_retry "$cmd" "$duration" "Running"

  } || acm_status=FAILED

  TITLE "All MultiClusterHub resources status:"

  ${OC} get MultiClusterHub -A -o json | jq -r '.items[].status' || :

  if [[ "$acm_status" = FAILED ]] ; then
    TITLE "Checking for errors in MultiClusterHub deployment logs in cluster ${cluster_name}"

    ${OC} logs deploy/multiclusterhub-operator \
    --all-containers --limit-bytes=10000 --since=10m |& (! highlight '^E0|"error"|level=error') || :

    FATAL "ACM MultiClusterHub is not ready after $duration"
  fi

  local acm_current_version
  acm_current_version="$(${OC} get MultiClusterHub -n "${ACM_NAMESPACE}" ${ACM_INSTANCE} -o jsonpath='{.status.currentVersion}')" || :

  TITLE "ACM ${acm_current_version} console url: $(${OC} get routes -n ${ACM_NAMESPACE} multicloud-console --no-headers -o custom-columns='URL:spec.host')"

}

# ------------------------------------------

function create_clusterset_for_submariner_in_acm_hub() {
  ### Create ACM cluster-set ###
  PROMPT "Create cluster-set for Submariner on ACM"
  trap_to_debug_commands;

  local acm_resource
  acm_resource="`mktemp`_acm_resource"
  local duration=5m

  # Run on ACM MultiClusterHub cluster
  export KUBECONFIG="${KUBECONF_HUB}"

  cmd="${OC} api-resources | grep ManagedClusterSet"
  watch_and_retry "$cmd" "$duration" || acm_status=FAILED

  if [[ "$acm_status" = FAILED ]] ; then
    ${OC} api-resources
    FATAL "ManagedClusterSet resource type is missing"
  fi

  TITLE "Creating 'ManagedClusterSet' resource for ${SUBM_OPERATOR}"

  ${OC} new-project "${SUBM_OPERATOR}" 2>/dev/null || ${OC} project "${SUBM_OPERATOR}" -q

  # Create the cluster-set
  cat <<EOF | ${OC} apply -f -
  apiVersion: cluster.open-cluster-management.io/v1beta1
  kind: ManagedClusterSet
  metadata:
    name: ${SUBM_OPERATOR}
EOF

  local cmd="${OC} describe ManagedClusterSets &> '$acm_resource'"
  # local regex="Reason:\s*ClustersSelected" # Only later it includes "ManagedClusterSet"
  local regex="Manager:\s*${SUBM_OPERATOR}"

  watch_and_retry "$cmd ; grep -E '$regex' $acm_resource" "$duration" || :
  cat $acm_resource |& highlight "$regex" || acm_status=FAILED

  if [[ "$acm_status" = FAILED ]] ; then
    # FATAL "ManagedClusterSet for '${SUBM_OPERATOR}' is still empty after $duration"
    FATAL "'${SUBM_OPERATOR}' was not added to ManagedClusterSet after $duration"
  fi

  TITLE "Creating 'ManagedClusterSetBinding' resource for Submariner"

  # Bind the namespace
  cat <<EOF | ${OC} apply -f -
  apiVersion: cluster.open-cluster-management.io/v1beta1
  kind: ManagedClusterSetBinding
  metadata:
    name: ${SUBM_OPERATOR}
    namespace: ${SUBM_NAMESPACE}
  spec:
    clusterSet: ${SUBM_OPERATOR}
EOF

  local cmd="${OC} describe ManagedClusterSetBinding -n ${SUBM_NAMESPACE} &> '$acm_resource'"
  local regex="Cluster Set:\s*${SUBM_OPERATOR}"

  watch_and_retry "$cmd ; grep -E '$regex' $acm_resource" "$duration" || :
  cat $acm_resource |& highlight "$regex" || acm_status=FAILED

  if [[ "$acm_status" = FAILED ]] ; then
    FATAL "ManagedClusterSetBinding for '${SUBM_OPERATOR}' was not created in ${SUBM_NAMESPACE} after $duration"
  fi

}

# ------------------------------------------

function create_and_import_managed_cluster() {
  trap_to_debug_commands;

  local kubeconfig_file="$1"

  export KUBECONFIG="$kubeconfig_file"

  local cluster_id
  cluster_id="acm-$(print_current_cluster_name || :)"

  PROMPT "Create and import a managed cluster in ACM: $cluster_id"

  local ocp_cloud
  ocp_cloud="$(print_current_cluster_cloud)"

  create_new_managed_cluster_in_acm_hub "$cluster_id" "$ocp_cloud"

  export KUBECONFIG="$kubeconfig_file"

  import_managed_cluster "$cluster_id"
}

# ------------------------------------------

function create_new_managed_cluster_in_acm_hub() {
  ### Create ACM managed cluster by cluster ID ###
  trap_to_debug_commands;

  local cluster_id="${1}"
  local cluster_type="${2:-Amazon}" # temporarily use Amazon as default cluster type

  # Run on ACM MultiClusterHub cluster (Manager)
  export KUBECONFIG="${KUBECONF_HUB}"

  TITLE "Create the namespace for the managed cluster: ${cluster_id}"

  # ${OC} new-project "${cluster_id}" | ${OC} project "${cluster_id}" -q
  create_namespace "${cluster_id}"

  ${OC} label namespace ${cluster_id} cluster.open-cluster-management.io/managedCluster=${cluster_id} --overwrite

  TITLE "Create ACM ManagedCluster by ID: $cluster_id, Type: $cluster_type"

  cat <<EOF | ${OC} apply -f -
  apiVersion: cluster.open-cluster-management.io/v1
  kind: ManagedCluster
  metadata:
    name: ${cluster_id}
    labels:
      cloud: ${cluster_type}
      name: ${cluster_id}
      vendor: OpenShift
      cluster.open-cluster-management.io/clusterset: ${SUBM_OPERATOR}
  spec:
    hubAcceptsClient: true
    leaseDurationSeconds: 60
EOF


  TITLE "Create ACM klusterlet Addon config for cluster '$cluster_id'"

  ### Create the klusterlet Addon config
  cat <<EOF | ${OC} apply -f -
  apiVersion: agent.open-cluster-management.io/v1
  kind: KlusterletAddonConfig
  metadata:
    name: ${cluster_id}
    namespace: ${cluster_id}
    labels:
      cluster.open-cluster-management.io/${SUBM_AGENT}: "true"
  spec:
    applicationManager:
      argocdCluster: false
      enabled: true
    certPolicyController:
      enabled: true
    clusterLabels:
      cloud: auto-detect
      cluster.open-cluster-management.io/clusterset: ${SUBM_OPERATOR}
      name: ${cluster_id}
      vendor: auto-detect
    clusterName: ${cluster_id}
    clusterNamespace: ${cluster_id}
    iamPolicyController:
      enabled: true
    policyController:
      enabled: true
    searchCollector:
      enabled: true
    version: 2.2.0
EOF

  TITLE "Wait for ManagedCluster Opaque secret '${cluster_id}-import' to be created"

  local duration=5m

  # Wait for the new ManagedCluster $cluster_id
  ${OC} wait --timeout=$duration managedcluster ${cluster_id} -n ${cluster_id} --for=condition=HubAcceptedManagedCluster || :

  # Wait for the Opaque secret
  local cmd="${OC} get secrets -n ${cluster_id}"
  local regex="${cluster_id}-import"

  watch_and_retry "$cmd" "$duration" || \
  FATAL "Opaque secret '${cluster_id}-import' was not created after $duration"

  local kluster_crd="./${cluster_id}-klusterlet-crd.yaml"
  local kluster_import="./${cluster_id}-import.yaml"

  TITLE "Save the yamls to be applied on the managed clusters: '${kluster_crd}' and '${kluster_import}'"

  ${OC} get secret ${cluster_id}-import -n ${cluster_id} -o jsonpath="{.data.crds\\.yaml}" | base64 --decode > ${kluster_crd}
  ${OC} get secret ${cluster_id}-import -n ${cluster_id} -o jsonpath="{.data.import\\.yaml}" | base64 --decode > ${kluster_import}

}

# ------------------------------------------

### Function to import the clusters to the clusterSet
function import_managed_cluster() {
  trap_to_debug_commands;

  local cluster_id="${1}"

  local kluster_crd="./${cluster_id}-klusterlet-crd.yaml"
  local kluster_import="./${cluster_id}-import.yaml"

  ocp_login "${OCP_USR}" "$(< ${WORKDIR}/${OCP_USR}.sec)"

  TITLE "Install klusterlet (Addon) on the managed clusters"
  # Import the managed clusters
  # info "install the agent"
  ${OC} apply -f ${kluster_crd}

  # TODO: Wait for klusterlet crds installation
  # sleep 2m

  ${OC} apply -f ${kluster_import}
  ${OC} get pod -n open-cluster-management-agent

}

# ------------------------------------------

function install_submariner_operator_on_cluster() {
  trap_to_debug_commands;

  local kubeconfig_file="$1"
  local submariner_version="${2:-$SUBM_VER_TAG}"

  export KUBECONFIG="$kubeconfig_file"

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Install Submariner bundle $submariner_version (without Subscription) on cluster $cluster_name"

  # Fix the $submariner_version value for custom images (the function is defined in main setup_subm.sh)
  set_subm_version_tag_var "submariner_version"

  echo -e "\n# Since Submariner 0.12 the channel has changed from 'alpha' to 'stable'"
  local submariner_channel
  if check_version_greater_or_equal "$SUBM_VER_TAG" "0.12" ; then
    submariner_channel="${SUBM_CHANNEL_PREFIX}$(print_major_minor_version "$submariner_version")"
  else
    submariner_channel="${SUBM_CHANNEL_PREFIX_TECH_PREVIEW}$(print_major_minor_version "$submariner_version")"
  fi

  ocp_login "${OCP_USR}" "$(< ${WORKDIR}/${OCP_USR}.sec)"

  # Deploy Submariner operator as an OCP bundle
  deploy_ocp_bundle "${SUBM_BUNDLE}" "${submariner_version}" "${SUBM_OPERATOR}" "${submariner_channel}" "${SUBM_CATALOG}" "${SUBM_NAMESPACE}"
  # Note: No need to create Subscription for Submariner bundle, as it is done later within: create_submariner_config_in_acm_managed_cluster()

  TITLE "Apply the 'scc' policy for Submariner Gateway, Router-agent, Globalnet and Lighthouse on cluster $cluster_name"
  ${OC} adm policy add-scc-to-user privileged system:serviceaccount:${SUBM_NAMESPACE}:${SUBM_GATEWAY}
  ${OC} adm policy add-scc-to-user privileged system:serviceaccount:${SUBM_NAMESPACE}:${SUBM_ROUTE_AGENT}
  ${OC} adm policy add-scc-to-user privileged system:serviceaccount:${SUBM_NAMESPACE}:${SUBM_GLOBALNET}
  ${OC} adm policy add-scc-to-user privileged system:serviceaccount:${SUBM_NAMESPACE}:${SUBM_LH_COREDNS}

  # TODO: Wait for acm agent installation on the managed clusters
  local cmd="${OC} get clusterrolebindings --no-headers -o custom-columns='USER:subjects[].*' | grep '${SUBM_LH_COREDNS}'"
  watch_and_retry "$cmd" 5m || BUG "WARNING: Submariner users may not be scc privileged"

  ${OC} get clusterrolebindings

}

# ------------------------------------------

function configure_submariner_addon_for_acm_managed_cluster() {
  # TODO: This funtion should be split and executed as several junit tests

  trap_to_debug_commands;

  local kubeconfig_file="$1"

  export KUBECONFIG="$kubeconfig_file"

  echo -e "\n# Generate '\$cluster_id' according to the current cluster name of kubeconfig: $kubeconfig_file"

  local cluster_id
  cluster_id="acm-$(print_current_cluster_name || :)"

  PROMPT "Configure Submariner $SUBM_VER_TAG Addon for ACM managed cluster: $cluster_id"

  # Following steps should be run on ACM MultiClusterHub to configure Submariner addon with $KUBECONF_HUB (NOT with the managed cluster kubeconfig)
  export KUBECONFIG="${KUBECONF_HUB}"

  ocp_login "${OCP_USR}" "$(< ${WORKDIR}/${OCP_USR}.sec)"

  ${OC} get managedcluster -o wide

  local managed_cluster_cloud
  managed_cluster_cloud=$(${OC} get managedcluster -o jsonpath="{.items[?(@.metadata.name=='${cluster_id}')].metadata.labels.cloud}")

  TITLE "Configure ${cluster_id} credentials for the Submariner Gateway on cloud: $managed_cluster_cloud"

  local cluster_secret_name

  if [[ "$managed_cluster_cloud" = "Amazon" ]] ; then
    cluster_secret_name="${cluster_id}-aws-creds"
    configure_submariner_addon_for_amazon "$cluster_id" "$cluster_secret_name"
  elif [[ "$managed_cluster_cloud" = "Google" ]] ; then
    cluster_secret_name="${cluster_id}-gcp-creds"
    configure_submariner_addon_for_google "$cluster_id" "$cluster_secret_name"
  elif [[ "$managed_cluster_cloud" = "Openstack" ]] ; then
    cluster_secret_name="${cluster_id}-osp-creds"
    configure_submariner_addon_for_openstack "$cluster_id" "$cluster_secret_name"
  else
    FATAL "Could not determine Cloud type '$managed_cluster_cloud' for Managed cluster '${cluster_id}'"
  fi

  # After creating the cloud credentials for the managed cluster - use it in the SubmarinerConfig
  create_submariner_config_in_acm_managed_cluster "$cluster_id" "$cluster_secret_name" "$SUBM_VER_TAG"

  # Validate manifestwork
  validate_submariner_manifestwork_in_acm_managed_cluster "$cluster_id"

  # Validate managedclusteraddons
  validate_submariner_addon_status_in_acm_managed_cluster "$cluster_id"

  # Validate submarinerconfig
  validate_submariner_config_in_acm_managed_cluster "$cluster_id"

  # Validate submariner connection
  validate_submariner_agent_connected_in_acm_managed_cluster "$cluster_id"

}

# ------------------------------------------

function configure_submariner_addon_for_amazon() {
  ### Configure submariner addon credentials for AWS cloud ###

  trap_to_debug_commands;

  local cluster_id="${1}"
  local cluster_secret_name="${2}"

  echo -e "\n# Using '${cluster_secret_name}' for Submariner on Amazon"

  ( # subshell to hide commands
    ( [[ -n "$AWS_KEY" ]] && [[ -n "$AWS_SECRET" ]] ) \
    || FATAL "AWS credentials are required to configure Submariner in the managed cluster '${cluster_id}'"

    cat <<EOF | ${OC} apply -f -
    apiVersion: v1
    kind: Secret
    metadata:
        name: ${cluster_secret_name}
        namespace: ${cluster_id}
    type: Opaque
    data:
        aws_access_key_id: $(echo -n ${AWS_KEY} | base64 -w0)
        aws_secret_access_key: $(echo -n ${AWS_SECRET} | base64 -w0)
EOF
  )

}

# ------------------------------------------

function configure_submariner_addon_for_google() {
  ### Configure submariner addon credentials for GCP cloud ###

  trap_to_debug_commands;

  local cluster_id="${1}"
  local cluster_secret_name="${2}"

  echo -e "\n# Using '${cluster_secret_name}' for Submariner on Google"

  ( # subshell to hide commands
    [[ -s "$GCP_CRED_JSON" ]] || FATAL "GCP credentials file (json) is required to configure Submariner in the managed cluster '${cluster_id}'"

    cat <<EOF | ${OC} apply -f -
    apiVersion: v1
    kind: Secret
    metadata:
        name: ${cluster_secret_name}
        namespace: ${cluster_id}
    type: Opaque
    data:
        osServiceAccount.json: $(base64 -w0 "${GCP_CRED_JSON}")
EOF
  )

}

# ------------------------------------------

function configure_submariner_addon_for_openstack() {
  ### Configure submariner addon credentials for OSP cloud ###

  trap_to_debug_commands;

  local cluster_id="${1}"
  local cluster_secret_name="${2}"

  echo -e "\n# Using '${cluster_secret_name}' for Submariner on Openstack"

  # Since ACM 2.5 Openstack cloud prepare is supported
  if check_version_greater_or_equal "$ACM_VER_TAG" "2.5" ; then

    ( # subshell to hide commands
        ( [[ -n "$OS_PROJECT_DOMAIN_ID" ]] ) \
        || FATAL "OSP credentials are required to configure Submariner in the managed cluster '${cluster_id}'"

    cat <<EOF | ${OC} apply -f -
    apiVersion: v1
    kind: Secret
    metadata:
        name: ${cluster_secret_name}
        namespace: ${cluster_id}
    type: Opaque
    data:
        clouds.yaml: $(echo -n "
        clouds:
          openstack:
            auth:
              auth_url: ${OS_AUTH_URL}
              username: '${OS_USERNAME}'
              project_id: ${OS_PROJECT_DOMAIN_ID}
              project_name: '${OS_PROJECT_NAME}'
              user_domain_name: '${OS_USER_DOMAIN_NAME}'
            region_name: '${OS_REGION_NAME}'
            interface: 'public'
            identity_api_version: 3
         " | base64 -w0)
        cloud: $(echo -n "openstack" | base64 -w0)
EOF
    )

  else
    BUG "Openstack Gateway creation is not yet supported with Submariner Addon" \
    "The Gateway should be configured externally with 'configure_osp.sh'"
  fi

}

# ------------------------------------------


function create_submariner_config_in_acm_managed_cluster() {
  ### Create the SubmarinerConfig on the managed cluster_id with specified submariner version ###

  trap_to_debug_commands;

  local cluster_id="${1}"
  local cluster_secret_name="${2}"
  local submariner_version="${3:-$SUBM_VER_TAG}"

  # Fix the $submariner_version value for custom images (the function is defined in main setup_subm.sh)
  set_subm_version_tag_var "submariner_version"

  echo -e "\n# Since Submariner 0.12 the channel has changed from 'alpha' to 'stable'"
  local submariner_channel
  if check_version_greater_or_equal "$SUBM_VER_TAG" "0.12" ; then
    submariner_channel="${SUBM_CHANNEL_PREFIX}$(print_major_minor_version "$submariner_version")"
  else
    submariner_channel="${SUBM_CHANNEL_PREFIX_TECH_PREVIEW}$(print_major_minor_version "$submariner_version")"
  fi

  TITLE "Create the SubmarinerConfig in ACM namespace '${cluster_id}' with version: ${submariner_version} (channel ${submariner_channel})"

  local submariner_conf="SubmarinerConfig_${cluster_id}.yaml"

  cat <<-EOF > $submariner_conf
  apiVersion: submarineraddon.open-cluster-management.io/v1alpha1
  kind: SubmarinerConfig
  metadata:
    name: ${SUBM_OPERATOR}
    namespace: ${cluster_id}
  spec:
    IPSecIKEPort: ${IPSEC_IKE_PORT}
    IPSecNATTPort: ${IPSEC_NATT_PORT}
    cableDriver: libreswan
    credentialsSecret:
      name: ${cluster_secret_name}
    gatewayConfig:
      aws:
        instanceType: c5d.large
      gateways: 1
    imagePullSpecs:
      lighthouseAgentImagePullSpec: ''
      lighthouseCoreDNSImagePullSpec: ''
      submarinerImagePullSpec: ''
      submarinerRouteAgentImagePullSpec: ''
    subscriptionConfig:
      channel: ${submariner_channel}
      source: ${SUBM_CATALOG}
      sourceNamespace: ${SUBM_NAMESPACE}
      startingCSV: ${SUBM_OPERATOR}.${submariner_version}
EOF

  echo -e "\n# Apply SubmarinerConfig (if failed once - apply again)"

  ${OC} apply --dry-run='server' -f $submariner_conf | highlight "unchanged" \
  || ${OC} apply -f $submariner_conf || ${OC} apply -f $submariner_conf

  TITLE "Display the SubmarinerConfig CRD"

  ${OC} describe crd submarinerconfigs.submarineraddon.open-cluster-management.io || :

  TITLE "Create the Submariner Addon to start the deployment"

  cat <<EOF | ${OC} apply -f -
  apiVersion: addon.open-cluster-management.io/v1alpha1
  kind: ManagedClusterAddOn
  metadata:
    name: ${SUBM_OPERATOR}
    namespace: ${cluster_id}
  spec:
    installNamespace: ${SUBM_NAMESPACE}
EOF

  ${OC} describe managedclusteraddons -n ${cluster_id} ${SUBM_OPERATOR}

  TITLE "Label the managed clusters and klusterletaddonconfigs to deploy submariner"

  # ${OC} label managedclusters.cluster.open-cluster-management.io ${cluster_id} "cluster.open-cluster-management.io/${SUBM_AGENT}=true" --overwrite
  ${OC} label managedcluster ${cluster_id} "cluster.open-cluster-management.io/clusterset=${SUBM_OPERATOR}" --overwrite

}

# ------------------------------------------

function validate_submariner_manifestwork_in_acm_managed_cluster() {
  ### Validate that Submariner manifestwork created in ACM, for the managed cluster_id ###

  trap_to_debug_commands;

  local cluster_id="${1}"
  local manifestwork_status
  local regex
  local cmd

  # Check Submariner manifests
  regex="submariner"
  TITLE "Wait for ManifestWork of '${regex}' to be ready in the ACM MultiClusterHub under namespace ${cluster_id}"
  cmd="${OC} get manifestwork -n ${cluster_id} --ignore-not-found"
  watch_and_retry "$cmd | grep -E '$regex'" "5m" || :
  $cmd |& highlight "$regex" || FATAL "Submariner Manifestworks were not created in ACM MultiClusterHub for the cluster id: $cluster_id"


  # Check Klusterlet manifests

  # In ACM 2.5 the addon manifest was renamed to "addon-application-manager-deploy"
  if check_version_greater_or_equal "$ACM_VER_TAG" "2.5" ; then
    regex="addon-application-manager-deploy"
  else
    regex="klusterlet-addon-appmgr"
  fi

  TITLE "Wait for ManifestWork of '${regex}' to be ready in the ACM MultiClusterHub under namespace ${cluster_id}"
  cmd="${OC} get manifestwork -n ${cluster_id} --ignore-not-found"
  watch_and_retry "$cmd | grep -E '$regex'" "15m" || :
  $cmd |& highlight "$regex" || FAILURE "Klusterlet Manifestworks were not created in ACM MultiClusterHub for the cluster id: $cluster_id"

}

# ------------------------------------------

function validate_submariner_addon_status_in_acm_managed_cluster() {
  ### Validate that Submariner Addon has gateway labels and running agent for the managed cluster_id ###

  trap_to_debug_commands;

  local cluster_id="${1}"

  local managed_cluster_status

  TITLE "Verify ManagedClusterAddons '${SUBM_OPERATOR}' in ACM MultiClusterHub under namespace ${cluster_id}"

  ${OC} get managedclusteraddons ${SUBM_OPERATOR} -n ${cluster_id} || :

  ### Test ManagedClusterAddons ###
  # All checks should print: managedclusteraddon.addon.open-cluster-management.io/submariner condition met
  # "Degraded" conditions should be false

  ${OC} wait --timeout=5m managedclusteraddons ${SUBM_OPERATOR} -n ${cluster_id} --for=condition=RegistrationApplied && \
  ${OC} wait --timeout=15m managedclusteraddons ${SUBM_OPERATOR} -n ${cluster_id} --for=condition=ManifestApplied && \
  ${OC} wait --timeout=5m managedclusteraddons ${SUBM_OPERATOR} -n ${cluster_id} --for=condition=Available && \
  ${OC} wait --timeout=5m managedclusteraddons ${SUBM_OPERATOR} -n ${cluster_id} --for=condition=SubmarinerGatewayNodesLabeled && \
  ${OC} wait --timeout=15m managedclusteraddons ${SUBM_OPERATOR} -n ${cluster_id} --for=condition=SubmarinerAgentDegraded=false || managed_cluster_status=FAILED

  ${OC} describe managedclusteraddons ${SUBM_OPERATOR} -n ${cluster_id} || managed_cluster_status=FAILED

  if [[ "$managed_cluster_status" = FAILED ]] ; then
    ${OC} logs deploy/submariner-addon \
    --all-containers --limit-bytes=10000 --since=10m |& (! highlight '^E0|"error"|level=error') || :

    FATAL "Submariner ManagedClusterAddon has unhealthy conditions in ACM cluster id: $cluster_id"
  fi

}

# ------------------------------------------

function validate_submariner_config_in_acm_managed_cluster() {
  ### Validate that SubmarinerConfig is ready in ACM, for the cluster_id ###

  trap_to_debug_commands;

  local cluster_id="${1}"

  local config_status

  TITLE "Verify SubmarinerConfig '${SUBM_OPERATOR}' in the ACM MultiClusterHub under namespace ${cluster_id}"

  ${OC} get submarinerconfig ${SUBM_OPERATOR} -n ${cluster_id} || :

  ### Test SubmarinerConfig ###
  # All checks should print: submarinerconfig.submarineraddon.open-cluster-management.io/submariner condition met

  ${OC} wait --timeout=5m submarinerconfig ${SUBM_OPERATOR} -n ${cluster_id} --for=condition=SubmarinerClusterEnvironmentPrepared && \
  ${OC} wait --timeout=5m submarinerconfig ${SUBM_OPERATOR} -n ${cluster_id} --for=condition=SubmarinerConfigApplied && \
  ${OC} wait --timeout=5m submarinerconfig ${SUBM_OPERATOR} -n ${cluster_id} --for=condition=SubmarinerGatewaysLabeled || config_status=FAILED

  ${OC} describe submarinerconfig ${SUBM_OPERATOR} -n ${cluster_id} || config_status=FAILED

  if [[ "$config_status" = FAILED ]] ; then
    FATAL "SubmarinerConfig resource has unhealthy conditions in ACM cluster id: $cluster_id"
  fi

}

# ------------------------------------------

function validate_submariner_agent_connected_in_acm_managed_cluster() {
  ### Validate that Submariner Addon has gateway labels and running agent for the managed cluster_id ###

  trap_to_debug_commands;

  local cluster_id="${1}"

  local managed_cluster_status

  TITLE "Verify Submariner connection established in the '${SUBM_OPERATOR}' cluster-set of ACM namespace ${cluster_id}"

  ${OC} get managedcluster -o wide

  # The ManagedCluster-Broker connection is a management-plane connection only (via the Kube API), and not a data-plane connection.
  # "SubmarinerConnectionDegraded" condition is relevant only when more than one ManagedClusters are configured.
  # i.e. To establish actual inter-cluster data-plane connections between ManagedClusters (which are part of the same ManagedClusterSet).

  local clusterset_count
  clusterset_count="$(${OC} get managedclusteraddons -A -o jsonpath="{.items[?(@.metadata.name=='${SUBM_OPERATOR}')].metadata.name}" | wc -w)"

  if (( clusterset_count > 1 )) ; then
    ${OC} wait --timeout=15m managedclusteraddons ${SUBM_OPERATOR} -n ${cluster_id} --for=condition=SubmarinerConnectionDegraded=false || managed_cluster_status=FAILED

    if [[ "$managed_cluster_status" = FAILED ]] ; then
      ${OC} describe managedclusteraddons ${SUBM_OPERATOR} -n ${cluster_id}
      FAILURE "Submariner connection could not be established in ACM cluster id: $cluster_id"
    fi

  else
    echo -e "\n# Ignoring 'SubmarinerConnectionDegraded' condition, as it requires at least 2 Submariner agents in '${SUBM_OPERATOR}' ManagedClusterSet"
  fi

}
