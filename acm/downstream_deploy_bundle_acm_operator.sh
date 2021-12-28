#!/bin/bash

############ ACM and Submariner operator installation functions ############

# Set working dir
# wd="$(dirname "$(realpath -s $0)")"

# source ${wd:?}/debug.sh

trap_to_debug_commands; # Trap commands (should be called only after sourcing debug.sh)

export LOG_TITLE="cluster1"

# ------------------------------------------

function clean_acm_namespace_and_resources_cluster_a() {
### Run cleanup of previous ACM on cluster A ###
  PROMPT "Cleaning previous ACM (multiclusterhub, Subscriptions, clusterserviceversion, Namespace) on cluster A"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  clean_acm_namespace_and_resources
}

# ------------------------------------------

function clean_acm_namespace_and_resources_cluster_b() {
### Run cleanup of previous ACM on cluster A ###
  PROMPT "Cleaning previous ACM (multiclusterhub, Subscriptions, clusterserviceversion, Namespace) on cluster B"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  clean_acm_namespace_and_resources
}

# ------------------------------------------

function clean_acm_namespace_and_resources_cluster_c() {
### Run cleanup of previous ACM on cluster C ###
  PROMPT "Cleaning previous ACM (multiclusterhub, Subscriptions, clusterserviceversion, Namespace) on cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  clean_acm_namespace_and_resources
}

# ------------------------------------------

function clean_acm_namespace_and_resources() {
  trap_to_debug_commands;

  local acm_uninstaller_url="https://raw.githubusercontent.com/open-cluster-management/deploy/master/multiclusterhub/uninstall.sh"
  local acm_uninstaller_file="./acm_cleanup.sh"

  download_file "${acm_uninstaller_url}" "${acm_uninstaller_file}"
  chmod +x "${acm_uninstaller_file}"

  export TARGET_NAMESPACE="${ACM_NAMESPACE}"
  ${acm_uninstaller_file} || FAILURE "Uninstalling ACM Hub did not complete successfully"

  # TODO: Use script from https://github.com/open-cluster-management/acm-qe/wiki/Cluster-Life-Cycle-Component
    # https://raw.githubusercontent.com/open-cluster-management/deploy/master/hack/cleanup-managed-cluster.sh
    # https://github.com/open-cluster-management/endpoint-operator/raw/master/hack/hub-detach.sh

  BUG "ACM uninstaller script does not delete all resources" \
  "Delete ACM resources directly" \
  "https://github.com/open-cluster-management/deploy/issues/218"
  # Workaround:

  local cluster_name
  cluster_name="$(print_current_cluster_name)"

  TITLE "Delete global CRDs, Managed Clusters, and Validation Webhooks of ACM in cluster ${cluster_name}"

  delete_crds_by_name "open-cluster-management" || :
  ${OC} delete managedcluster --all --wait || :
  ${OC} delete validatingwebhookconfiguration --all --wait || :

  TITLE "Delete all ACM resources in Namespace '${ACM_NAMESPACE}' in cluster ${cluster_name}"

  ${OC} delete subs --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete catalogsource --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete is --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete multiclusterhub --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete clusterserviceversion --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete cm --all -n ${ACM_NAMESPACE} --wait || :
  ${OC} delete service --all -n ${ACM_NAMESPACE} --wait || :

  ${OC} delete namespace ${ACM_NAMESPACE} || :
  ${OC} wait --for=delete namespace ${ACM_NAMESPACE} || :

  # force_delete_namespace "${ACM_NAMESPACE}" 10m || :

}

# ------------------------------------------

function install_acm_operator() {
  ### Install ACM operator ###
  trap_to_debug_commands;

  local acm_version="v${1:-$ACM_VER_TAG}" # e.g. v2.4.0

  local regex_to_major_minor='[0-9]+\.[0-9]+' # Regex to trim version into major.minor (X.Y.Z ==> X.Y)
  local acm_channel
  acm_channel="release-$(echo $acm_version | grep -Po "$regex_to_major_minor")"

  PROMPT "Install ACM operator $acm_version (Channel ${acm_channel})"

  export KUBECONFIG="${KUBECONF_HUB}"
  export SUBSCRIBE=true

  # Run on the Hub install
  # ${wd:?}/downstream_push_bundle_to_olm_catalog.sh

  local cmd="${OC} get MultiClusterHub multiclusterhub"
  local retries=3
  watch_and_retry "$cmd" "$retries" "Running" || \
  deploy_ocp_bundle "${acm_version}" "${ACM_OPERATOR}" "${ACM_BUNDLE}" "${ACM_NAMESPACE}" "${acm_channel}" "${ACM_SUBSCRIPTION}" "${ACM_CATALOG}"

  TITLE "Wait for MultiClusterHub CRD to be ready for ${ACM_BUNDLE}"
  cmd="${OC} get crds multiclusterhubs.operator.open-cluster-management.io"
  watch_and_retry "$cmd" 5m || FATAL "MultiClusterHub CRD was not created for ${ACM_BUNDLE}"

  echo "# Install ACM operator completed"

}

# ------------------------------------------

function create_acm_multiclusterhub() {
  ### Create ACM MultiClusterHub instance ###
  PROMPT "Create ACM MultiClusterHub instance"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"

  # Create the MultiClusterHub instance
  cat <<EOF | ${OC} apply -f -
  apiVersion: operator.open-cluster-management.io/v1
  kind: MultiClusterHub
  metadata:
    name: multiclusterhub
    namespace: ${ACM_NAMESPACE}
  spec:
    disableHubSelfManagement: true
EOF

  TITLE "Wait for ACM console url to be available"
  cmd="${OC} get routes -n ${ACM_NAMESPACE} multicloud-console --no-headers -o custom-columns='URL:spec.host'"
  watch_and_retry "$cmd" 15m || FATAL "ACM Console url is not ready"

  TITLE "Wait for multiclusterhub to be ready"

  # cmd="${OC} get MultiClusterHub multiclusterhub -o jsonpath='{.status.phase}'"
  cmd="${OC} get MultiClusterHub multiclusterhub"
  duration=15m
  watch_and_retry "$cmd" "$duration" "Running" || acm_status=FAILED

  if [[ "$acm_status" = FAILED ]] ; then
    ${OC} get MultiClusterHub multiclusterhub
    FATAL "ACM Hub is not ready after $duration"
  fi

  TITLE "ACM console url: $(${OC} get routes -n ${ACM_NAMESPACE} multicloud-console --no-headers -o custom-columns='URL:spec.host')"

}

# ------------------------------------------

function create_clusterset_for_submariner_in_acm_hub() {
  ### Create ACM cluster-set ###
  PROMPT "Create cluster-set for Submariner on ACM"
  trap_to_debug_commands;

  local acm_resource
  acm_resource="`mktemp`_acm_resource"
  local duration=5m

  # Run on ACM hub cluster
  export KUBECONFIG="${KUBECONF_HUB}"

  cmd="${OC} api-resources | grep ManagedClusterSet"
  watch_and_retry "$cmd" "$duration" || acm_status=FAILED

  if [[ "$acm_status" = FAILED ]] ; then
    ${OC} api-resources
    FATAL "ManagedClusterSet resource type is missing"
  fi

  TITLE "Creating 'ManagedClusterSet' resource for Submariner"

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

function import_managed_cluster_a() {
  PROMPT "Import ACM CRDs for managed cluster A"
  trap_to_debug_commands;

  local cluster_id="acm-${CLUSTER_A_NAME}"
  create_new_managed_cluster_in_acm_hub "$cluster_id" "Amazon"

  export KUBECONFIG="${KUBECONF_HUB}"
  import_managed_cluster "$cluster_id"
}

# ------------------------------------------

function import_managed_cluster_b() {
  PROMPT "Import ACM CRDs for managed cluster B"
  trap_to_debug_commands;

  local cluster_id="acm-${CLUSTER_B_NAME}"
  create_new_managed_cluster_in_acm_hub "$cluster_id" "Openstack"

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  import_managed_cluster "$cluster_id"
}

# ------------------------------------------

function import_managed_cluster_c() {
  PROMPT "Import ACM CRDs for managed cluster C"
  trap_to_debug_commands;

  local cluster_id="acm-${CLUSTER_C_NAME}"
  create_new_managed_cluster_in_acm_hub "$cluster_id" "Amazon"

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  import_managed_cluster "$cluster_id"
}

# ------------------------------------------

function create_new_managed_cluster_in_acm_hub() {
  ### Create ACM managed cluster by cluster ID ###
  trap_to_debug_commands;

  local cluster_id="${1}"
  local cluster_type="${2:-Amazon}" # temporarily use Amazon as default cluster type

  # Run on ACM hub cluster (Manager)
  export KUBECONFIG="${KUBECONF_HUB}"

  TITLE "Create the namespace for the managed cluster"
  create_namespace "${cluster_id}"
  ${OC} label namespace ${cluster_id} cluster.open-cluster-management.io/managedCluster=${cluster_id} --overwrite

  TITLE "Create ACM managed cluster by ID: $cluster_id, Type: $cluster_type"

  # Define the managed Clusters
  # for i in {1..3}; do

  TITLE "Create the managed cluster"

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

  ### TODO: Wait for managedcluster
  # sleep 1m

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

  local kluster_crd="./${cluster_id}-klusterlet-crd.yaml"
  local kluster_import="./${cluster_id}-import.yaml"

  TITLE "Save the yamls to be applied on the managed clusters: '${kluster_crd}' and '${kluster_import}'"

  ${OC} get secrets -n ${cluster_id} |& highlight "${cluster_id}-import"

  ${OC} get secret ${cluster_id}-import -n ${cluster_id} -o jsonpath={.data.crds\\.yaml} | base64 --decode > ${kluster_crd}
  ${OC} get secret ${cluster_id}-import -n ${cluster_id} -o jsonpath={.data.import\\.yaml} | base64 --decode > ${kluster_import}

  # done

  # TODO: wait for kluserlet Addon
  # sleep 1m

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

function install_submariner_on_managed_cluster_a() {
  PROMPT "Install Submariner Operator $SUBM_VER_TAG on cluster A"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  install_submariner_operator_on_managed_cluster "$SUBM_VER_TAG"
}

# ------------------------------------------

function install_submariner_on_managed_cluster_b() {
  PROMPT "Install Submariner Operator $SUBM_VER_TAG on cluster B"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  install_submariner_operator_on_managed_cluster "$SUBM_VER_TAG"
}

# ------------------------------------------

function install_submariner_on_managed_cluster_c() {
  PROMPT "Install Submariner Operator $SUBM_VER_TAG on cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  install_submariner_operator_on_managed_cluster "$SUBM_VER_TAG"
}

# ------------------------------------------

function install_submariner_operator_on_managed_cluster() {
  trap_to_debug_commands;

  local submariner_version="${1:-$SUBM_VER_TAG}"

  # Fix the $submariner_version value for custom images (the function is defined in main setup_subm.sh)
  set_subm_version_tag_var "submariner_version"

  local regex_to_major_minor='[0-9]+\.[0-9]+' # Regex to trim version into major.minor (X.Y.Z ==> X.Y)
  local submariner_channel
  submariner_channel=alpha-$(echo $submariner_version | grep -Po "$regex_to_major_minor")

  local cluster_name
  cluster_name="$(print_current_cluster_name)"

  TITLE "Install custom catalog source for Submariner version $submariner_version (channel $submariner_channel) on cluster $cluster_name"

  export SUBSCRIBE=false

  ocp_login "${OCP_USR}" "$(< ${WORKDIR}/${OCP_USR}.sec)"

  # ${wd:?}/downstream_push_bundle_to_olm_catalog.sh

  deploy_ocp_bundle "${submariner_version}" "${SUBM_OPERATOR}" "${SUBM_BUNDLE}" "${SUBM_NAMESPACE}" "${submariner_channel}" "${SUBM_SUBSCRIPTION}" "${SUBM_CATALOG}"

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

function configure_submariner_for_managed_cluster_a() {
  PROMPT "Configure Submariner $SUBM_VER_TAG Addon for managed cluster A"
  trap_to_debug_commands;

  local cluster_id="acm-${CLUSTER_A_NAME}"
  configure_submariner_version_for_managed_cluster "$cluster_id" "$SUBM_VER_TAG"
}

# ------------------------------------------

function configure_submariner_for_managed_cluster_b() {
  PROMPT "Configure Submariner $SUBM_VER_TAG Addon for managed cluster B"
  trap_to_debug_commands;

  local cluster_id="acm-${CLUSTER_B_NAME}"
  configure_submariner_version_for_managed_cluster "$cluster_id" "$SUBM_VER_TAG"
}

# ------------------------------------------

function configure_submariner_for_managed_cluster_c() {
  PROMPT "Configure Submariner $SUBM_VER_TAG Addon for managed cluster C"
  trap_to_debug_commands;

  local cluster_id="acm-${CLUSTER_C_NAME}"
  configure_submariner_version_for_managed_cluster "$cluster_id" "$SUBM_VER_TAG"
}

# ------------------------------------------

function configure_submariner_version_for_managed_cluster() {
  ### Create ACM managed cluster by cluster ID ###
  trap_to_debug_commands;

  local cluster_id="${1}"

  local submariner_version="${2:-$SUBM_VER_TAG}"

  # Fix the $submariner_version value for custom images (the function is defined in main setup_subm.sh)
  set_subm_version_tag_var "submariner_version"

  local regex_to_major_minor='[0-9]+\.[0-9]+' # Regex to trim version into major.minor (X.Y.Z ==> X.Y)
  local submariner_channel
  submariner_channel=alpha-$(echo $submariner_version | grep -Po "$regex_to_major_minor")

  TITLE "Configure Submariner ${submariner_version} Addon in ACM Hub namespace $cluster_id"

  local submariner_status

  # Following steps should be run on ACM hub
  export KUBECONFIG="${KUBECONF_HUB}"

  ocp_login "${OCP_USR}" "$(< ${WORKDIR}/${OCP_USR}.sec)"

  echo "# Configure Submariner credentials"

  ( # subshell to hide commands
    ### Create the aws creds secret
    cat <<EOF | ${OC} apply -f -
    apiVersion: v1
    kind: Secret
    metadata:
        name: ${cluster_id}-aws-creds
        namespace: ${cluster_id}
    type: Opaque
    data:
        aws_access_key_id: $(echo -n ${AWS_KEY} | base64 -w0)
        aws_secret_access_key: $(echo -n ${AWS_SECRET} | base64 -w0)
EOF
  )

  TITLE "Create the Submariner Subscription config"

  cat <<EOF | ${OC} apply -f - || submariner_status=FAILED
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
      name: ${cluster_id}-aws-creds
    gatewayConfig:
      aws:
        instanceType: m5.xlarge
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


  if [[ ! "$submariner_status" = FAILED ]] ; then

    TITLE "Create the Submariner Addon to start the deployment"

    cat <<EOF | ${OC} apply -f - || submariner_status=FAILED
    apiVersion: addon.open-cluster-management.io/v1alpha1
    kind: ManagedClusterAddOn
    metadata:
      name: ${SUBM_OPERATOR}
      namespace: ${cluster_id}
    spec:
      installNamespace: ${SUBM_NAMESPACE}
EOF

    TITLE "Label the managed clusters and klusterletaddonconfigs to deploy submariner"

    ${OC} label managedclusters.cluster.open-cluster-management.io ${cluster_id} "cluster.open-cluster-management.io/${SUBM_AGENT}=true" --overwrite
  fi

  TITLE "SubmarinerConfig and ManagedClusterAddons in the ACM Hub under namespace ${cluster_id}"

  ${OC} get submarinerconfig ${SUBM_OPERATOR} -n ${cluster_id} && \
  ${OC} describe submarinerconfig ${SUBM_OPERATOR} -n ${cluster_id} || submariner_status=FAILED

  ${OC} get managedclusteraddons ${SUBM_OPERATOR} -n ${cluster_id} && \
  ${OC} describe managedclusteraddons ${SUBM_OPERATOR} -n ${cluster_id} || submariner_status=FAILED

  TITLE "Wait for ManifestWork of '${cluster_id}-klusterlet-crds' to be ready in the ACM Hub under namespace ${cluster_id}"

  local regex="klusterlet-crds"
  local cmd="${OC} get manifestwork -n ${cluster_id} --ignore-not-found"
  watch_and_retry "$cmd | grep '$regex'" "10m" || :

  $cmd |& highlight "$regex" || submariner_status=FAILED

  if [[ "$submariner_status" = FAILED ]] ; then
    FATAL "Submariner ${submariner_version} Addon installation failed in ACM Hub under namespace $cluster_id"
  fi

}
