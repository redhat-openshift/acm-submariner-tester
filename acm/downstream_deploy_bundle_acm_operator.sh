#!/bin/bash

############ ACM and Submariner operator installation functions ############

# Set working dir
# wd="$(dirname "$(realpath -s $0)")"

# source ${wd:?}/debug.sh

trap_to_debug_commands; # Trap commands (should be called only after sourcing debug.sh)

export LOG_TITLE="cluster1"

# ------------------------------------------

function install_acm_operator() {
  ### Install ACM operator ###
  PROMPT "Install ACM operator $ACM_VER_TAG"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_A}"

  # TODO: Run function with args ("$ACM_VER_TAG") instead of calling sh script with exported variables

  export ACM_VERSION="v${ACM_VER_TAG}" # e.g. v2.4.0
  export ACM_CHANNEL="release-$(echo ${ACM_VERSION} | cut -d'-' -f1 | cut -c2- | cut -d'.' -f1,2)"

  export SUBSCRIBE=true

  # Run on the Hub install
  # ${wd:?}/downstream_push_bundle_to_olm_catalog.sh

  deploy_ocp_bundle "${ACM_VERSION}" "${ACM_OPERATOR_NAME}" "${ACM_BUNDLE_NAME}" "${ACM_NAMESPACE}" "${ACM_CHANNEL}"

  # # Wait
  # if ! (timeout 5m bash -c "until ${OC} get crds multiclusterhubs.operator.open-cluster-management.io > /dev/null 2>&1; do sleep 10; done"); then
  #   error "MultiClusterHub CRD was not found."
  #   exit 1
  # fi

  set -x
  TITLE "Wait for MultiClusterHub CRD to be ready"
  cmd="${OC} get crds multiclusterhubs.operator.open-cluster-management.io"
  watch_and_retry "$cmd" 5m || FATAL "MultiClusterHub CRD was not created"

  echo "Install ACM operator completed"
  return 0
  set -x

}

# ------------------------------------------

function create_acm_multiclusterhub() {
  ### Create ACM MultiClusterHub instance ###
  PROMPT "Create ACM MultiClusterHub instance"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_A}"

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

  # # Wait for the console url
  # if ! (timeout 15m bash -c "until ${OC} get routes -n ${ACM_NAMESPACE} multicloud-console > /dev/null 2>&1; do sleep 10; done"); then
  #   error "ACM Console url was not found."
  #   exit 1
  # fi
  #
  # # Print ACM console url
  # echo ""
  # info "ACM Console URL: $(${OC} get routes -n ${ACM_NAMESPACE} multicloud-console --no-headers -o custom-columns='URL:spec.host')"
  # echo ""

  TITLE "Wait for ACM console url to be available"
  cmd="${OC} get routes -n ${ACM_NAMESPACE} multicloud-console --no-headers -o custom-columns='URL:spec.host'"
  watch_and_retry "$cmd" 15m || FATAL "ACM Console url is not ready"

  TITLE "Wait for multiclusterhub to be ready"

  BUG "ACM multiclusterhub install get stuck due to:
  3 Insufficient cpu, 3 node(s) had taint {node-role.kubernetes.io/master: }, that the pod didn't tolerate." \
  "Remove taint from all master nodes" \
  "https://bugzilla.redhat.com/show_bug.cgi?id=2000511"

  # for node in $(kubectl get nodes --selector='node-role.kubernetes.io/master' | awk 'NR>1 {print $1}' ) ; do
  #   echo -e "\n### Remove taint from master node $node ###"
  #   kubectl taint node $node node-role.kubernetes.io/master-
  # done

  # cmd="${OC} get MultiClusterHub multiclusterhub -o jsonpath='{.status.phase}'"
  cmd="${OC} get MultiClusterHub multiclusterhub"
  duration=15m
  watch_and_retry "$cmd" "$duration" "Running" || acm_status=FAILED

  if [[ "$acm_status" = FAILED ]] ; then
    ${OC} get MultiClusterHub multiclusterhub
    FATAL "ACM Hub is not ready after $duration"
  fi

  ${OC} get routes -A | highlight "multicloud-console"

}

# ------------------------------------------

function create_acm_clusterset_for_submariner() {
  ### Create ACM cluster-set ###
  PROMPT "Create ACM cluster-set"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_A}"

  cmd="${OC} api-resources | grep ManagedClusterSet"
  duration=5m
  watch_and_retry "$cmd" "$duration" || acm_status=FAILED

  if [[ "$acm_status" = FAILED ]] ; then
    ${OC} api-resources
    FATAL "ManagedClusterSet resource type is missing"
  fi

  # Create the cluster-set
  cat <<EOF | ${OC} apply -f -
  apiVersion: cluster.open-cluster-management.io/v1alpha1
  kind: ManagedClusterSet
  metadata:
    name: submariner
EOF

  TITLE "Checking 'ManagedClusterSet' resource for Submariner"

  local acm_resource="`mktemp`_acm_resource"
  local cmd="${OC} describe ManagedClusterSets &> '$acm_resource'"
  local regex="Status:\s*True"

  watch_and_retry "$cmd ; grep -E '$regex' $acm_resource" "$duration" || acm_status=FAILED

  if [[ "$acm_status" = FAILED ]] ; then
    cat $acm_resource
    FATAL "ManagedClusterSet resource for Submariner was not created after $duration"
  fi

  # Bind the namespace
  cat <<EOF | ${OC} apply -f -
  apiVersion: cluster.open-cluster-management.io/v1alpha1
  kind: ManagedClusterSetBinding
  metadata:
    name: submariner
    namespace: ${SUBMARINER_NAMESPACE}
  spec:
    clusterSet: submariner
EOF

  # Define the managed Clusters
  for i in {1..3}; do

    ### Create the namespace for the managed cluster
    ${OC} new-project cluster${i} || :
    ${OC} label namespace cluster${i} cluster.open-cluster-management.io/managedCluster=cluster${i} --overwrite

    # TODO: wait for namespace
    sleep 2m

    ### Create the managed cluster
  cat <<EOF | ${OC} apply -f -
  apiVersion: cluster.open-cluster-management.io/v1
  kind: ManagedCluster
  metadata:
    name: cluster${i}
    labels:
      cloud: Amazon
      name: cluster${i}
      vendor: OpenShift
      cluster.open-cluster-management.io/clusterset: submariner
  spec:
    hubAcceptsClient: true
    leaseDurationSeconds: 60
EOF

    ### TODO: Wait for managedcluster
    sleep 1m

  ### Create the klusterlet addon config
  cat <<EOF | ${OC} apply -f -
  apiVersion: agent.open-cluster-management.io/v1
  kind: KlusterletAddonConfig
  metadata:
    name: cluster${i}
    namespace: cluster${i}
    labels:
      cluster.open-cluster-management.io/submariner-agent: "true"
  spec:
    applicationManager:
      argocdCluster: false
      enabled: true
    certPolicyController:
      enabled: true
    clusterLabels:
      cloud: auto-detect
      cluster.open-cluster-management.io/clusterset: submariner
      name: cluster${i}
      vendor: auto-detect
    clusterName: cluster${i}
    clusterNamespace: cluster${i}
    iamPolicyController:
      enabled: true
    policyController:
      enabled: true
    searchCollector:
      enabled: true
    version: 2.2.0
EOF

    ### Save the yamls to be applied on the managed clusters
    ${OC} get secret cluster${i}-import -n cluster${i} -o jsonpath={.data.crds\\.yaml} | base64 --decode > /tmp/cluster${i}-klusterlet-crd.yaml
    ${OC} get secret cluster${i}-import -n cluster${i} -o jsonpath={.data.import\\.yaml} | base64 --decode > /tmp/cluster${i}-import.yaml
  done

  # TODO: wait for kluserlet addon
  sleep 1m

}

# ------------------------------------------

# Run on the managed clusters

# -### Import the clusters to the clusterSet
# for i in {1..3}; do
#   export LOG_TITLE="cluster${i}"
#   export KUBECONFIG=/opt/openshift-aws/smattar-cluster${i}/auth/kubeconfig
#   ${OC} login -u ${OCP_USR} -p ${OCP_PWD}
#
#   # Install klusterlet (addon) on the managed clusters
#   # Import the managed clusters
#   info "install the agent"
#   ${OC} apply -f /tmp/cluster${i}-klusterlet-crd.yaml
#
#   # TODO: Wait for klusterlet crds installation
#   sleep 2m
#
#   ${OC} apply -f /tmp/cluster${i}-import.yaml
#   info "$(${OC} get pod -n open-cluster-management-agent)"
#
# done

function import_managed_cluster_a() {
  PROMPT "Import ACM CRDs for managed cluster A"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_A}"
  import_managed_cluster "1"
}

# ------------------------------------------

function import_managed_cluster_c() {
  PROMPT "Import ACM CRDs for managed cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  import_managed_cluster "3"
}

# ------------------------------------------

### Function to import the clusters to the clusterSet
function import_managed_cluster() {
  trap_to_debug_commands;

  local cluster_name="$(print_current_cluster_name)"
  # TODO: cluster counter should rather not be used. Need to create crd with function
  local cluster_counter="$1"

  ( # subshell to hide commands
    local cmd="${OC} login -u ${OCP_USR} -p ${OCP_PWD}"
    # Attempt to login up to 3 minutes
    watch_and_retry "$cmd" 3m
  )

  TITLE "Install klusterlet (addon) on the managed clusters"
  # Import the managed clusters
  # info "install the agent"
  ${OC} apply -f /tmp/cluster${cluster_counter}-klusterlet-crd.yaml

  # TODO: Wait for klusterlet crds installation
  sleep 2m

  ${OC} apply -f /tmp/cluster${cluster_counter}-import.yaml
  ${OC} get pod -n open-cluster-management-agent

}

# ------------------------------------------

function prepare_acm_for_submariner() {
  PROMPT "Prepare ACM for Submariner $SUBM_VER_TAG"
  trap_to_debug_commands;

  FAILURE "Prepare ACM for Submariner (TODO)"

  ### Prepare Submariner
  for i in {1..3}; do
    export LOG_TITLE="cluster${i}"
    export KUBECONFIG=/opt/openshift-aws/smattar-cluster${i}/auth/kubeconfig
    ${OC} login -u ${OCP_USR} -p ${OCP_PWD}

    # Install the submariner custom catalog source

    # TODO: Run function with args ($SUBM_VER_TAG) instead of using exported variables

    export SUBMARINER_VERSION=v0.11.0 # TODO use $SUBM_VER_TAG
    export SUBMARINER_CHANNEL=alpha-$(echo ${SUBMARINER_VERSION} | cut -d'-' -f1 | cut -c2- | cut -d'.' -f1,2)

    export SUBSCRIBE=false

    # ${wd:?}/downstream_push_bundle_to_olm_catalog.sh

    deploy_ocp_bundle "${SUBMARINER_VERSION}" "${SUBM_OPERATOR_NAME}" "${SUBM_BUNDLE_NAME}" "${SUBMARINER_NAMESPACE}" "${SUBMARINER_CHANNEL}"

    ### Apply the Submariner scc
    ${OC} adm policy add-scc-to-user privileged system:serviceaccount:${SUBMARINER_NAMESPACE}:submariner-gateway
    ${OC} adm policy add-scc-to-user privileged system:serviceaccount:${SUBMARINER_NAMESPACE}:submariner-routeagent
    ${OC} adm policy add-scc-to-user privileged system:serviceaccount:${SUBMARINER_NAMESPACE}:submariner-globalnet
    ${OC} adm policy add-scc-to-user privileged system:serviceaccount:${SUBMARINER_NAMESPACE}:submariner-lighthouse-coredns
  done

  # TODO: Wait for acm agent installation on the managed clusters
  sleep 3m

# }
# ------------------------------------------
#
# function ttt() {
#   PROMPT "Prepare ACM for Submariner"
#

  # Run on the hub
  export LOG_TITLE="cluster1"
  export KUBECONFIG=/opt/openshift-aws/smattar-cluster1/auth/kubeconfig
  ${OC} login -u ${OCP_USR} -p ${OCP_PWD}

  ### Install Submariner
  for i in {1..3}; do
    ### Create the aws creds secret
  cat <<EOF | ${OC} apply -f -
  apiVersion: v1
  kind: Secret
  metadata:
      name: cluster${i}-aws-creds
      namespace: cluster${i}
  type: Opaque
  data:
      aws_access_key_id: $(echo ${AWS_KEY} | base64 -w0)
      aws_secret_access_key: $(echo ${AWS_SECRET} | base64 -w0)
EOF

    ### Create the Submariner Subscription config
  cat <<EOF | ${OC} apply -f -
  apiVersion: submarineraddon.open-cluster-management.io/v1alpha1
  kind: SubmarinerConfig
  metadata:
    name: submariner
    namespace: cluster${i}
  spec:
    IPSecIKEPort: 501
    IPSecNATTPort: 4501
    cableDriver: libreswan
    credentialsSecret:
      name: cluster${i}-aws-creds
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
      channel: ${SUBMARINER_CHANNEL}
      source: my-catalog-source
      sourceNamespace: ${SUBMARINER_NAMESPACE}
      startingCSV: submariner.${SUBMARINER_VERSION}
EOF

    ### Create the Submariner addon to start the deployment
  cat <<EOF | ${OC} apply -f -
  apiVersion: addon.open-cluster-management.io/v1alpha1
  kind: ManagedClusterAddOn
  metadata:
    name: submariner
    namespace: cluster${i}
  spec:
    installNamespace: ${SUBMARINER_NAMESPACE}
EOF

    ### Label the managed clusters and klusterletaddonconfigs to deploy submariner
    ${OC} label managedclusters.cluster.open-cluster-management.io cluster${i} "cluster.open-cluster-management.io/submariner-agent=true" --overwrite
  done

  for i in {1..3}; do
    ${OC} get submarinerconfig submariner -n cluster${i} >/dev/null 2>&1 && ${OC} describe submarinerconfig submariner -n cluster${i}
    ${OC} get managedclusteraddons submariner -n cluster${i} >/dev/null 2>&1 && ${OC} describe managedclusteraddons submariner -n cluster${i}
    ${OC} get manifestwork -n cluster${i} --ignore-not-found
  done

  export LOG_TITLE=""
  echo "All done"
  exit 0

}

# ------------------------------------------

function clean_acm_namespace_and_resources_cluster_a() {
### Run cleanup of previous ACM on cluster A ###
  PROMPT "Cleaning previous ACM (multiclusterhub, Subscriptions, clusterserviceversion, Namespace) on cluster A"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_A}"
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

  oc delete multiclusterhub --all || :
  oc delete subs --all || :
  oc delete clusterserviceversion --all || :
  oc delete validatingwebhookconfiguration multiclusterhub-operator-validating-webhook || :
  oc delete namespace $ACM_NAMESPACE || :

}
