#!/bin/bash
# shellcheck disable=SC2153,SC2031,SC2016,SC2120,SC2005,SC1091

#######################################################################################################
#                                                                                                     #
# Setup ACM with Submariner on public clouds (Amazon and Google) and On-premise (OpenStack)           #
# By Noam Manos, nmanos@redhat.com                                                                    #
#                                                                                                     #
# You can find latest script files here:                                                              #
# https://github.com/redhat-openshift/acm-submariner-tester                                           #
#                                                                                                     #
# It is assumed that you have existing Openshift configuration files (install-config.yaml)            #
# for all the clusters (AWS/OSP/GCP/AZURE) in the current directory. For example:                           #
#                                                                                                     #
# To create Openshift-installer config for Amazon cloud:                                              #
# https://github.com/openshift/installer/blob/master/docs/user/aws/customization.md#examples          #
#                                                                                                     #
# To create Openshift-installer config for Google cloud:                                              #
# https://github.com/openshift/installer/blob/master/docs/user/gcp/customization.md#examples          #
#                                                                                                     #
# To create Openshift-installer config for Azure cloud:                                              #
# https://github.com/openshift/installer/blob/master/docs/user/azure/customization.md#examples          #
#                                                                                                     #
# To create those config files, you need to supply your Red Hat pull secret, and SSH public key:      #
#                                                                                                     #
# (1) Get access to OpenStack on PSI account:                                                         #
# - Follow PnT Resource Workflow:                                                                     #
# https://docs.engineering.redhat.com/display/HSSP/PnT+Resource+Request+Workflow+including+PSI        #
# - PSI Resource (Openstack, OpenStack on PSI) request form:                                          #
# https://redhat.service-now.com/help?id=sc_cat_item&sys_id=0430d9eedb2150d0d8a333f3b9961927          #
# - Make sure your user is included in the Rover group with the same OSP project name:                #
# https://rover.redhat.com/groups/group/{your-rover-group-name}                                       #
# - Login to Openstack Admin with your kerberos credentials (and your company domain.com):            #
# https://openstack.psi.redhat.com/dashboard/auth/login/?next=/dashboard/                             #
# - Support email: psi-openstack-users@redhat.com                                                     #
# - Support IRC: #psi , #ops-escalation                                                               #
# - Support Google-Chat: exd-infra-escalation                                                         #
#                                                                                                     #
# (2) Get access to AWS account:                                                                      #
# - To get it, please fill AWS request form:                                                          #
# https://devservices.dpp.openshift.com/support/aws_iam_account_request/                              #
# - Once you get approved, login to AWS openshift-dev account via the web console:                    #
# https://{aws-account-id}.signin.aws.amazon.com/console                                              #
#                                                                                                     #
# (3) Get access to GCP account:                                                                      #
# - Create a personal service account (SA) with a user email, in:                                     #
# https://cloud.google.com/iam/docs/creating-managing-service-accounts#creating_a_service_account     #
# - Grant these roles to your SA: Compute Admin, Security Admin, Service Account Admin,               #
#   Service Account User, Storage Admin, DNS Administrator, Service Account Key Admin.                #
# - Download your personal GCP credentials from:                                                      #
# https://console.cloud.google.com/iam-admin/serviceaccounts?project={gcp-project}                    #
#                                                                                                     #
# (4) Get access to Azure account:                                                                    #
# - Follow instructions to spin up a new OCP cluster in the Azure subscriptions                       #
# https://docs.google.com/document/d/1Kzy4N8LQGozRmgmEaz_54CkzkjAbevMfnXfv7uvHkvk                     #
# - Verify your Azure subscription:                                                                   #
# https://portal.azure.com/#view/Microsoft_Azure_Billing/SubscriptionsBlade                           #
#                                                                                                     #
# (5) Your Red Hat Openshift pull secret, found in:                                                   #
# https://cloud.redhat.com/openshift/install/aws/installer-provisioned                                #
# It is used by Openshift-installer to download OCP images from Red Hat repositories.                 #
#                                                                                                     #
# (6) Your SSH Public Key, that you generated with " ssh-keygen -b 4096 "                             #
# cat ~/.ssh/id_rsa.pub                                                                               #
# It is required by Openshift-installer for authentication.                                           #
#                                                                                                     #
#                                                                                                     #
#######################################################################################################

# Script description
disclosure='----------------------------------------------------------------------

Interactive script to install Advanced Cluster Manager on private and public OpenShift clusters, and test inter-connectivity with Submariner.

Running with pre-defined parameters (optional):

- Openshift setup and environment options:

  * Reset (destroy & create) OCP cluster A:            --reset-cluster-a [latest / x.y / x.y.z / nightly]
  * Reset (destroy & create) OSP cluster B:            --reset-cluster-b [latest / x.y / x.y.z / nightly]
  * Reset (destroy & create) OCP cluster C:            --reset-cluster-c [latest / x.y / x.y.z / nightly]
  * Destroy existing OCP cluster A:                    --destroy-cluster-a
  * Destroy existing OSP cluster B:                    --destroy-cluster-b
  * Destroy existing OCP cluster C:                    --destroy-cluster-c
  * Re-create OCP cluster A (existing installation):   --create-cluster-a
  * Re-create OCP cluster B (existing installation):   --create-cluster-b
  * Re-create OCP cluster C (existing installation):   --create-cluster-c
  * Delete ACM & Submariner in OCP cluster A:          --clean-cluster-a
  * Delete ACM & Submariner in OCP cluster B:          --clean-cluster-b
  * Delete ACM & Submariner in OCP cluster C:          --clean-cluster-c
  * Install & configure Golang (and other libs):       --config-golang
  * Configure Clouds access (AWS/OSP/GCP/AZURE):       --config-clouds
  * Skip OCP clusters setup (registry, users, etc.):   --skip-ocp-setup

- Submariner installation options:

  * Install ACM version:                               --acm-version [x.y / x.y.z]
  * Specify ACM images date (default to latest):       --acm-date [YYYY-MM-DD]
  * Specify MCE version (default to latest):           --mce-version [x.y / x.y.z]
  * Install Submariner version:                        --subctl-version [latest / x.y / x.y.z / {tag}]
  * Install Submariner with SubCtl (default to API):   --subctl-install
  * Override images from downstream registry:          --registry-images
  * Configure and test Submariner with GlobalNet:      --globalnet
  * Configure Submariner Network Cable Driver:         --cable-driver [libreswan / vxlan]
  * Join managed cluster A:                            --join-cluster-a
  * Join managed cluster B:                            --join-cluster-b
  * Join managed cluster C:                            --join-cluster-c

- Submariner test options:

  * Skip tests execution (by type):                    --skip-tests [sys / e2e / pkg / all]
  * Update Git and test with GO (instead of subctl):   --build-tests
  * Create Junit test results (xml):                   --junit
  * Upload Junit results to Polarion:                  --polarion

- General script options:

  * Import additional variables from file:             --import-vars  [variables file path]
  * Print Submariner pods logs on failure:             --print-logs
  * Show debug info (verbose) for commands:            -d / --debug
  * Show this help menu:                               -h / --help


### Command examples:

To run interactively (enter options manually):

`./setup_subm.sh`


Examples with pre-defined options:

`./setup_subm.sh --clean-cluster-a --clean-cluster-b --acm-version 2.7 --subctl-version 0.14 --registry-images`

  * Reuse (clean) existing clusters
  * Install ACM 2.7.z release (latest Z release)
  * Install Submariner 0.14.z release (latest Z release)
  * Override Submariner images from a custom downstream repository (defined in $REGISTRY variables)
  * Run Submariner E2E tests (with subctl)


`./setup_subm.sh --reset-cluster-c nightly --clean-cluster-a --subctl-version subctl-devel --build-tests --junit`

  * Install OCP nightly (RC version) on cluster C, as defined in $CLUSTER_C_YAML variable
  * Clean existing cluster A (which is also the ACM Hub cluster)
  * Install Submariner version "subctl-devel" (upstream development branch)
  * Build and run Submariner E2E and unit-tests with GO
  * Create Junit tests result (xml files)

----------------------------------------------------------------------'


####################################################################################
#               Global bash configurations and external sources                    #
####################################################################################

# Set $SCRIPT_DIR as current absolute path where this script runs in (e.g. Jenkins build directory)
# Note that files in $SCRIPT_DIR are not guaranteed to be permanently saved, as in $WORKDIR
SCRIPT_DIR="$(dirname "$(realpath -s "$0")")"
export SCRIPT_DIR

### Import Test and Helper functions ###
source "$SCRIPT_DIR/helper_functions"
source "$SCRIPT_DIR/test_functions"

### Import ACM Functions ###
source "$SCRIPT_DIR/olm_functions"
source "$SCRIPT_DIR/acm_functions"

# To exit on errors and extended trap
# set -Eeo pipefail
set -Ee
# -e : Exit at the first error
# -E : Ensures that ERR traps get inherited by functions, command substitutions, and subshell environments.
# -u : Treats unset variables as errors.
# -o pipefail : Propagate intermediate errors (not just last command exit code)

# Set Case-insensitive match for string evaluations
shopt -s nocasematch

# Expend user aliases
shopt -s expand_aliases


####################################################################################
#                             CLI Script parameters                                #
####################################################################################

export_param_value() {
  if [[ -z "$1" || "$1" =~ ^- ]] ; then
    echo -e "\n# Missing or bad input parameter '${1}' for '${2}'. Please see script Help with: --help"
    exit 1
  fi
  export "${2}=${1}"
}

# Get script parameters, and split by tabs instead of space
SCRIPT_PARAMS="$*"
SCRIPT_PARAMS=${SCRIPT_PARAMS// -/$'\t'-}
IFS=$'\t'
POSITIONAL=()

for param in ${SCRIPT_PARAMS} ; do
  export got_user_input=TRUE

  # Get the next parameter (flag) name, without the value
  param_name=${param%% *}

  # Get the parameter value after the flag, without surrounding quotes
  param_value=$(echo "${param#*"$param_name" }" | xargs)

  case $param_name in
  -h|--help)
    echo -e "\n# ${disclosure}" && exit 0
    shift ;;
  -d|--debug)
    export SCRIPT_DEBUG_MODE=YES
    shift ;;
  --acm-version)
    export_param_value "${param_value}" "ACM_VER_TAG" # $ACM_VER_TAG will get the value
    export INSTALL_ACM=YES
    shift 2 ;;
  --acm-date)
    export_param_value "${param_value}" "ACM_BUILD_DATE" # $ACM_BUILD_DATE will get the value
    shift 2 ;;
  --mce-version)
    export_param_value "${param_value}" "MCE_VER_TAG" # $MCE_VER_TAG will get the value
    export INSTALL_MCE=YES
    shift 2 ;;
  --subctl-version)
    export_param_value "${param_value}" "SUBM_VER_TAG" # $SUBM_VER_TAG will get the value
    export INSTALL_SUBMARINER=YES
    shift 2 ;;
  --registry-images)
    export REGISTRY_IMAGES=YES
    shift ;;
  --build-tests)
    export BUILD_GO_TESTS=YES
    shift ;;
  --destroy-cluster-a)
    # export OCP_INSTALLER_REQUIRED=YES
    export DESTROY_CLUSTER_A=YES
    shift ;;
  --create-cluster-a)
    # export OCP_INSTALLER_REQUIRED=YES
    export CREATE_CLUSTER_A=YES
    shift ;;
  --reset-cluster-a)
    # OCP_INSTALLER_REQUIRED=YES
    export_param_value "${param_value}" "TARGET_VERION_CLUSTER_A" # $TARGET_VERION_CLUSTER_A will get the value
    export RESET_CLUSTER_A=YES
    export DESTROY_CLUSTER_A=YES
    export CREATE_CLUSTER_A=YES
    shift ;;
  --clean-cluster-a)
    export CLEAN_CLUSTER_A=YES
    shift ;;
  --destroy-cluster-b)
    export DESTROY_CLUSTER_B=YES
    shift ;;
  --create-cluster-b)
    export CREATE_CLUSTER_B=YES
    shift ;;
  --reset-cluster-b)
    export_param_value "${param_value}" "TARGET_VERION_CLUSTER_B" # $TARGET_VERION_CLUSTER_B will get the value
    export RESET_CLUSTER_B=YES
    export DESTROY_CLUSTER_B=YES
    export CREATE_CLUSTER_B=YES
    shift ;;
  --clean-cluster-b)
    export CLEAN_CLUSTER_B=YES
    shift ;;
  --destroy-cluster-c)
    export OCP_INSTALLER_REQUIRED=YES
    export DESTROY_CLUSTER_C=YES
    shift ;;
  --create-cluster-c)
    export OCP_INSTALLER_REQUIRED=YES
    export CREATE_CLUSTER_C=YES
    shift ;;
  --reset-cluster-c)
    export_param_value "${param_value}" "TARGET_VERION_CLUSTER_C" # $TARGET_VERION_CLUSTER_C will get the value
    export OCP_INSTALLER_REQUIRED=YES
    export RESET_CLUSTER_C=YES
    export DESTROY_CLUSTER_C=YES
    export CREATE_CLUSTER_C=YES
    shift ;;
  --clean-cluster-c)
    export CLEAN_CLUSTER_C=YES
    shift ;;
  --subctl-install)
    export INSTALL_WITH_SUBCTL=YES
    shift ;;
  --join-cluster-a)
    export JOIN_CLUSTER_A=YES
    shift ;;
  --join-cluster-b)
    export JOIN_CLUSTER_B=YES
    shift ;;
  --join-cluster-c)
    export JOIN_CLUSTER_C=YES
    shift ;;
  --globalnet)
    export GLOBALNET=YES
    shift ;;
  --cable-driver)
    # Default is libreswan
    export_param_value "${param_value}" "SUBM_CABLE_DRIVER" # $SUBM_CABLE_DRIVER will get the value
    shift 2 ;;
  --skip-ocp-setup)
    export SKIP_OCP_SETUP=YES
    shift ;;
  --skip-tests)
    # sys,e2e,pkg,all
    export_param_value "${param_value}" "SKIP_TESTS" # $SKIP_TESTS will get the value
    shift 2 ;;
  --print-logs)
    export PRINT_LOGS=YES
    shift ;;
  --config-golang)
    export CONFIG_GOLANG=YES
    shift ;;
  --config-clouds)
    export CONFIG_CLOUDS_CLI=YES
    shift ;;
  --junit)
    export CREATE_JUNIT_XML=YES
    shift ;;
  --polarion)
    export UPLOAD_TO_POLARION=YES
    shift ;;
  --import-vars)
    # Import additional variables from local file
    export_param_value "${param_value}" "GLOBAL_VARS" # $GLOBAL_VARS will get the value
    shift 2 ;;
  -*)
    echo -e "${disclosure} \n\n$0: Error - unrecognized option: ${param}" 1>&2
    exit 1 ;;
  *)
    break ;;
  esac
done

# Restore positional parameters and IFS
set -- "${POSITIONAL[@]}"
unset IFS

####################################################################################
#               Get User input (only for missing CLI parameters)                    #
####################################################################################

if [[ -z "$got_user_input" ]]; then
  echo -e "\n# ${disclosure}"

  # User input: $SKIP_OCP_SETUP - to skip OCP clusters setup (destroy / create / clean)
  while [[ ! "$SKIP_OCP_SETUP" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to deploy Submariner WITHOUT preparing OCP clusters (will not destroy / create / clean) ? ${NO_COLOR}
    Enter \"yes\" to run without preparing OCP: "
    read -r input
    SKIP_OCP_SETUP=${input:-NO}
  done

  if [[ ! "$SKIP_OCP_SETUP" =~ ^(yes|y)$ ]]; then

    # User input: $RESET_CLUSTER_A - to destroy_ocp_cluster AND create_ocp_cluster
    while [[ ! "$RESET_CLUSTER_A" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to destroy & create OpenShift cluster A ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      RESET_CLUSTER_A=${input:-no}
    done

    # User input: $CLEAN_CLUSTER_A - to clean cluster A
    if [[ "$RESET_CLUSTER_A" =~ ^(no|n)$ ]]; then
      while [[ ! "$CLEAN_CLUSTER_A" =~ ^(yes|no)$ ]]; do
        echo -e "\n${YELLOW}Do you want to clean OpenShift cluster A ? ${NO_COLOR}
        Enter \"yes\", or nothing to skip: "
        read -r input
        CLEAN_CLUSTER_A=${input:-no}
      done
    fi

    # User input: $RESET_CLUSTER_B - to destroy_openstack_cluster AND create_openstack_cluster
    while [[ ! "$RESET_CLUSTER_B" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to destroy & create OSP cluster B ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      RESET_CLUSTER_B=${input:-no}
    done

    # User input: $CLEAN_CLUSTER_B - to clean cluster B
    if [[ "$RESET_CLUSTER_B" =~ ^(no|n)$ ]]; then
      while [[ ! "$CLEAN_CLUSTER_B" =~ ^(yes|no)$ ]]; do
        echo -e "\n${YELLOW}Do you want to clean OSP cluster B ? ${NO_COLOR}
        Enter \"yes\", or nothing to skip: "
        read -r input
        CLEAN_CLUSTER_B=${input:-no}
      done
    fi

    # User input: $RESET_CLUSTER_C - to destroy_ocp_cluster AND CREATE_CLUSTER_C
    while [[ ! "$RESET_CLUSTER_C" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to destroy & create OCP cluster C ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      RESET_CLUSTER_C=${input:-no}
    done

    # User input: $CLEAN_CLUSTER_C - to clean cluster C
    if [[ "$RESET_CLUSTER_C" =~ ^(no|n)$ ]]; then
      while [[ ! "$CLEAN_CLUSTER_C" =~ ^(yes|no)$ ]]; do
        echo -e "\n${YELLOW}Do you want to clean OCP cluster C ? ${NO_COLOR}
        Enter \"yes\", or nothing to skip: "
        read -r input
        CLEAN_CLUSTER_C=${input:-no}
      done
    fi

  fi # END of SKIP_OCP_SETUP options

  # User input: $GLOBALNET - to deploy with --globalnet
  while [[ ! "$GLOBALNET" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to install Global Net ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    GLOBALNET=${input:-no}
  done

  # User input: $build_operator - to build_operator_latest # [DEPRECATED]
  # while [[ ! "$build_operator" =~ ^(yes|no)$ ]]; do
  #   echo -e "\n${YELLOW}Do you want to pull Submariner-Operator repository (\"devel\" branch) and build subctl ? ${NO_COLOR}
  #   Enter \"yes\", or nothing to skip: "
  #   read -r input
  #   build_operator=${input:-no}
  # done

  # User input: $INSTALL_ACM and ACM_VER_TAG - to Install ACM and add managed clusters
  if [[ "$INSTALL_ACM" =~ ^(yes|y)$ ]]; then
    while [[ ! "$ACM_VER_TAG" =~ ^[0-9a-Z]+ ]]; do
      echo -e "\n${YELLOW}Which ACM version do you want to install ? ${NO_COLOR}
      Enter version number, or nothing to install \"latest\" version: "
      read -r input
      ACM_VER_TAG=${input:-latest}
    done
  fi

  # User input: $INSTALL_SUBMARINER and SUBM_VER_TAG - to download_and_install_subctl
  if [[ "$INSTALL_SUBMARINER" =~ ^(yes|y)$ ]]; then
    while [[ ! "$SUBM_VER_TAG" =~ ^[0-9a-Z]+ ]]; do
      echo -e "\n${YELLOW}Which Submariner version (or tag) do you want to install ? ${NO_COLOR}
      Enter version number, or nothing to install \"latest\" version: "
      read -r input
      SUBM_VER_TAG=${input:-latest}
    done
  fi

  # User input: $JOIN_CLUSTER_A - to join managed cluster A
  while [[ ! "$JOIN_CLUSTER_A" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to join managed cluster A ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    JOIN_CLUSTER_A=${input:-no}
  done

  # User input: $JOIN_CLUSTER_B - to join managed cluster B
  while [[ ! "$JOIN_CLUSTER_B" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to join managed cluster B ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    JOIN_CLUSTER_B=${input:-no}
  done

  # User input: $JOIN_CLUSTER_C - to join managed cluster C
  while [[ ! "$JOIN_CLUSTER_C" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to join managed cluster C ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    JOIN_CLUSTER_C=${input:-no}
  done

  # User input: $REGISTRY_IMAGES - to configure_cluster_custom_registry
  while [[ ! "$REGISTRY_IMAGES" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to override Submariner images with those from custom registry (as configured in REGISTRY variables) ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    REGISTRY_IMAGES=${input:-no}
  done

  # User input: $BUILD_GO_TESTS - to build and run ginkgo tests from all submariner repos
  while [[ ! "$BUILD_GO_TESTS" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to run E2E and unit tests from all Submariner repositories ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    BUILD_GO_TESTS=${input:-YES}
  done

  # User input: $INSTALL_WITH_SUBCTL - to install using SUBCTL tool
  while [[ ! "$INSTALL_WITH_SUBCTL" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to install Submariner with SubCtl tool ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    INSTALL_WITH_SUBCTL=${input:-NO}
  done

  # User input: $SKIP_TESTS - to skip tests: sys / e2e / pkg / all ^((sys|e2e|pkg)(,|$))+
  while [[ ! "$SKIP_TESTS" =~ ((sys|e2e|pkg|all)(,|$))+ ]]; do
    echo -e "\n${YELLOW}Do you want to run WITHOUT executing Submariner Tests (will exclude System, E2E, Unit-Tests, or all) ? ${NO_COLOR}
    Enter either \"sys,e2e,pkg,all\" to exclude these tests: "
    read -r input
    SKIP_TESTS=${input:-NO}
  done

  while [[ ! "$PRINT_LOGS" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to print full Submariner diagnostics (Pods logs, etc.) on failure ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    PRINT_LOGS=${input:-NO}
  done

  # User input: $CONFIG_GOLANG - to install latest golang if missing
  while [[ ! "$CONFIG_GOLANG" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to install latest Golang on the environment ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    CONFIG_GOLANG=${input:-NO}
  done

  # User input: $CONFIG_CLOUDS_CLI - to configure clouds access and required CLI tools
  while [[ ! "$CONFIG_CLOUDS_CLI" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to configure clouds access and required CLI tools ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    CONFIG_CLOUDS_CLI=${input:-NO}
  done

  # User input: $CREATE_JUNIT_XML - to record shell results into Junit xml output
  while [[ ! "$CREATE_JUNIT_XML" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to record shell results into Junit xml output ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    CREATE_JUNIT_XML=${input:-NO}
  done

  # User input: $UPLOAD_TO_POLARION - to upload junit xml results to Polarion
  while [[ ! "$UPLOAD_TO_POLARION" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to upload junit xml results to Polarion ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    UPLOAD_TO_POLARION=${input:-NO}
  done

fi

####################################################################################
#                    MAIN - ACM and Submariner Deploy and Tests                    #
####################################################################################

# Set and export all global env variables, redirect output to temporary log, and save as $SYS_LOG
# Exporting vars must first be in parent shell process, but not in a sub-shell (e.g. do not run with tee)
temp_script_log="$(mktemp)_script_log"

export_all_env_variables &>> "$temp_script_log" || :
cp "$temp_script_log" "$SYS_LOG"
cat "$SYS_LOG"

# Subshell to print output both to stdout and to $SYS_LOG with tee
(
  # (export_all_env_variables) # Required to run again, to check exit code, but without exporting (now in sub-shell)

  # Set script trap functions
  set_trap_functions

  ### Script debug calls (should be left as a comment) ###

    # ${JUNIT_CMD} debug_test_polarion
    # echo 0 > "$TEST_STATUS_FILE"
    # ${JUNIT_CMD} debug_test_pass "junit" "junit"
    # ${JUNIT_CMD} debug_test_fail "path/with  double  spaces  /  and even back\\slashes"
    # rc=$?
    # BUG "debug_test_fail - Exit code: $rc" \
    # "If RC $rc = 5 - JUNIT_CMD should continue execution"
    # ${JUNIT_CMD} debug_test_pass 100 200 300
    # ${JUNIT_CMD} debug_test_fatal
    # ${JUNIT_CMD} debug_test_pass "1" "2" "3"
    # ${JUNIT_CMD} debug_test_fail "should be skipped"
    # ${JUNIT_CMD} debug_test_pass "should be skipped too"

  ### END Script debug ###

  # Setup and verify environment
  setup_workspace

  # Print planned steps according to CLI/User inputs
  ${JUNIT_CMD} show_test_plan

  ### OCP Clusters preparations (unless requested to --skip-ocp-setup) ###
  
  ### Cluster A Setup (mandatory cluster)

  # Running destroy or create or both (reset) for cluster A

  if [[ "$DESTROY_CLUSTER_A" =~ ^(y|yes)$ ]] ; then

    ${JUNIT_CMD} destroy_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_NAME"

  fi

  if [[ "$RESET_CLUSTER_A" =~ ^(y|yes)$ ]] ; then

    ${JUNIT_CMD} download_ocp_installer "$TARGET_VERION_CLUSTER_A" "$CLUSTER_A_DIR"

    ${JUNIT_CMD} prepare_ocp_install "$CLUSTER_A_DIR" "$CLUSTER_A_YAML" "$CLUSTER_A_NAME"

  fi

  if [[ "$CREATE_CLUSTER_A" =~ ^(y|yes)$ ]] ; then

    ${JUNIT_CMD} create_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_NAME"

  fi

  ### Cluster B Setup (if it is expected to be an active cluster) ###

  if [[ -s "$CLUSTER_B_YAML" ]] ; then

    # Running destroy or create or both (reset) for cluster B

    if [[ "$DESTROY_CLUSTER_B" =~ ^(y|yes)$ ]] ; then

      ${JUNIT_CMD} destroy_cluster "$CLUSTER_B_DIR" "$CLUSTER_B_NAME"

    fi

    if [[ "$RESET_CLUSTER_B" =~ ^(y|yes)$ ]] ; then
    
      ${JUNIT_CMD} download_ocp_installer "$TARGET_VERION_CLUSTER_B" "$CLUSTER_B_DIR"

      ${JUNIT_CMD} prepare_ocp_install "$CLUSTER_B_DIR" "$CLUSTER_B_YAML" "$CLUSTER_B_NAME"

    fi

    if [[ "$CREATE_CLUSTER_B" =~ ^(y|yes)$ ]] ; then

      ${JUNIT_CMD} create_cluster "$CLUSTER_B_DIR" "$CLUSTER_B_NAME"

    fi

  fi

  ### Cluster C Setup (if it is expected to be an active cluster) ###

  if [[ -s "$CLUSTER_C_YAML" ]] ; then

    # Running destroy or create or both (reset) for cluster C

    if [[ "$DESTROY_CLUSTER_C" =~ ^(y|yes)$ ]] ; then

      ${JUNIT_CMD} destroy_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_NAME"

    fi

    if [[ "$RESET_CLUSTER_C" =~ ^(y|yes)$ ]] ; then
    
      ${JUNIT_CMD} download_ocp_installer "$TARGET_VERION_CLUSTER_C" "$CLUSTER_C_DIR"

      ${JUNIT_CMD} prepare_ocp_install "$CLUSTER_C_DIR" "$CLUSTER_C_YAML" "$CLUSTER_C_NAME"
    
    fi

    if [[ "$CREATE_CLUSTER_C" =~ ^(y|yes)$ ]] ; then

      ${JUNIT_CMD} create_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_NAME"

    fi

  fi

  # Get test exit status (from file $TEST_STATUS_FILE)
  SCRIPT_EXIT_STATUS="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat "$TEST_STATUS_FILE")"

  # Update test exit status to 0, unless it is already 1 or 2
  [[ "$SCRIPT_EXIT_STATUS" == @(1|2) ]] || echo 0 > "$TEST_STATUS_FILE"

  # fi
  # ### END of OCP Setup (Create or Destroy) ###


  ### OCP general preparations required for ALL tests, except unit-tests (pkg) ###
  # Skipping if using "--skip-tests all" : To run clusters create/destroy without further tests, or if just running unit-tests ###

  if [[ ! "$SKIP_TESTS" =~ ((all)(,|$))+ ]]; then

    # Get test exit status (from file $TEST_STATUS_FILE)
    SCRIPT_EXIT_STATUS="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat "$TEST_STATUS_FILE")"

    # Update test exit status to empty, unless it is already 1 or 2
    [[ "$SCRIPT_EXIT_STATUS" == @(1|2) ]] || : > "$TEST_STATUS_FILE"

    ### Verify clusters status after OCP reset/create ###

    ${JUNIT_CMD} update_kubeconfig_default_context "${KUBECONF_HUB}" "${CLUSTER_A_NAME}"

    ${JUNIT_CMD} test_cluster_status "${KUBECONF_HUB}" "${CLUSTER_A_NAME}"

    # Verify cluster B (if it is expected to be an active cluster)
    if [[ -s "$CLUSTER_B_YAML" ]] && [[ -s "$KUBECONF_CLUSTER_B" ]] ; then

      ${JUNIT_CMD} update_kubeconfig_default_context "${KUBECONF_CLUSTER_B}" "${CLUSTER_B_NAME}"

      ${JUNIT_CMD} test_cluster_status "${KUBECONF_CLUSTER_B}" "${CLUSTER_B_NAME}"

    else

      check_if_cluster_is_active "${KUBECONF_CLUSTER_B}" || unset "KUBECONF_CLUSTER_B"

    fi

    # Verify cluster C (if it is expected to be an active cluster)
    if [[ -s "$CLUSTER_C_YAML" ]] && [[ -s "$KUBECONF_CLUSTER_C" ]] ; then

      ${JUNIT_CMD} update_kubeconfig_default_context "${KUBECONF_CLUSTER_C}" "${CLUSTER_C_NAME}"

      ${JUNIT_CMD} test_cluster_status "${KUBECONF_CLUSTER_C}" "${CLUSTER_C_NAME}"

    else

      check_if_cluster_is_active "${KUBECONF_CLUSTER_C}" || unset "KUBECONF_CLUSTER_C"

    fi

    if [[ ! -s "$KUBECONF_CLUSTER_B" ]] && [[ ! -s "$KUBECONF_CLUSTER_C" ]] ; then

      FATAL "Both cluster B and cluster C are down. \
      Multi-Cluster tests require at least one more cluster (beside cluster A)"
      
    fi

    ### Download subctl binary, even if not using subctl deploy and join (e.g. to uninstall Submariner) ###

    if [[ "$INSTALL_SUBMARINER" =~ ^(y|yes)$ ]] ; then

      ${JUNIT_CMD} download_and_install_subctl "$SUBM_VER_TAG"

      ${JUNIT_CMD} test_subctl_command

    fi

    ### Clusters Cleanup (of ACM and Submariner resources) - Only for existing clusters ###

    # Running cleanup on cluster A if requested
    if [[ "$CLEAN_CLUSTER_A" =~ ^(y|yes)$ ]] && [[ ! "$DESTROY_CLUSTER_A" =~ ^(y|yes)$ ]] ; then

      ${JUNIT_CMD} remove_acm_managed_cluster_from_hub "${KUBECONF_HUB}"

      ${JUNIT_CMD} remove_acm_resources_on_managed_cluster "${KUBECONF_HUB}"

      ${JUNIT_CMD} uninstall_submariner "${KUBECONF_HUB}"

      ${JUNIT_CMD} delete_old_submariner_images_from_cluster "${KUBECONF_HUB}"

      ${JUNIT_CMD} delete_all_evicted_pods_in_cluster "${KUBECONF_HUB}"

      # Cleaning ACM and MCE is required only for the Hub cluster A
      # TODO: Move to a separate flag, as it might not required for Submariner tests

      ${JUNIT_CMD} delete_acm_image_streams_and_tags

      ${JUNIT_CMD} clean_acm_namespace_and_resources

      ${JUNIT_CMD} remove_multicluster_engine "${KUBECONF_HUB}"

    fi
    # END of cluster A cleanup

    # Running cleanup on cluster B if requested
    if [[ -s "$CLUSTER_B_YAML" ]] && [[ -s "$KUBECONF_CLUSTER_B" ]] ; then

      if [[ "$CLEAN_CLUSTER_B" =~ ^(y|yes)$ ]] && [[ ! "$DESTROY_CLUSTER_B" =~ ^(y|yes)$ ]] ; then

        ${JUNIT_CMD} remove_acm_managed_cluster_from_hub "${KUBECONF_CLUSTER_B}"

        ${JUNIT_CMD} remove_acm_resources_on_managed_cluster "${KUBECONF_CLUSTER_B}"

        ${JUNIT_CMD} uninstall_submariner "${KUBECONF_CLUSTER_B}"

        ${JUNIT_CMD} delete_old_submariner_images_from_cluster "${KUBECONF_CLUSTER_B}"

        ${JUNIT_CMD} delete_all_evicted_pods_in_cluster "${KUBECONF_CLUSTER_B}"

        ${JUNIT_CMD} remove_multicluster_engine "${KUBECONF_CLUSTER_B}"

      fi
    fi
    # END of cluster B cleanup

    # Running cleanup on cluster C if requested
    if [[ -s "$CLUSTER_C_YAML" ]] && [[ -s "$KUBECONF_CLUSTER_C" ]] ; then

      if [[ "$CLEAN_CLUSTER_C" =~ ^(y|yes)$ ]] && [[ ! "$DESTROY_CLUSTER_C" =~ ^(y|yes)$ ]] ; then

        ${JUNIT_CMD} remove_acm_managed_cluster_from_hub "${KUBECONF_CLUSTER_C}"

        ${JUNIT_CMD} remove_acm_resources_on_managed_cluster "${KUBECONF_CLUSTER_C}"

        ${JUNIT_CMD} uninstall_submariner "${KUBECONF_CLUSTER_C}"

        ${JUNIT_CMD} delete_old_submariner_images_from_cluster "${KUBECONF_CLUSTER_C}"

        ${JUNIT_CMD} delete_all_evicted_pods_in_cluster "${KUBECONF_CLUSTER_C}"

        ${JUNIT_CMD} remove_multicluster_engine "${KUBECONF_CLUSTER_C}"

      fi
    fi
    # END of cluster C cleanup

    ### Clusters configurations ### 
    # Add OCP elevated user, Registry prune policy, Firewall ports, Gateway labels.
    # Add custom (downstream) registry mirrors, secrets and images.
    # TODO: Should rename flag "--skip-ocp-setup" to "--skip-ocp-config".
   
    if [[ "$REGISTRY_IMAGES" =~ ^(y|yes)$ && ! "$SKIP_OCP_SETUP" =~ ^(y|yes)$ ]]; then

      echo -e "\n# TODO: If installing without ADDON (when adding clusters with subctl join) -
      \n\# Then for AWS/GCP/AZURE/OSP run subctl cloud prepare command"
      # https://submariner.io/operations/deployment/subctl/#cloud-prepare

      # Cluster A configurations

      if [[ -s "$CLUSTER_A_YAML" ]] && [[ "$CLEAN_CLUSTER_A" =~ ^(y|yes)$ || "$CREATE_CLUSTER_A" =~ ^(y|yes)$ ]] ; then
       
        ${JUNIT_CMD} add_elevated_user "${KUBECONF_HUB}"

        # ${JUNIT_CMD} configure_ocp_garbage_collection_and_images_prune "${KUBECONF_HUB}"

        # ${JUNIT_CMD} remove_submariner_images_from_local_registry_with_podman

        ${JUNIT_CMD} configure_custom_registry_in_cluster "${KUBECONF_HUB}"

        ${JUNIT_CMD} upload_submariner_images_to_cluster_registry "${KUBECONF_HUB}"

      fi

      # Cluster B configurations (plus custom configurations for OpenStack)
      
      if [[ -s "$KUBECONF_CLUSTER_B" ]] && [[ "$CLEAN_CLUSTER_B" =~ ^(y|yes)$ || "$CREATE_CLUSTER_B" =~ ^(y|yes)$ ]] ; then

        ${JUNIT_CMD} add_elevated_user "${KUBECONF_CLUSTER_B}"

        # ${JUNIT_CMD} configure_ocp_garbage_collection_and_images_prune "${KUBECONF_CLUSTER_B}"

        ${JUNIT_CMD} configure_custom_registry_in_cluster "${KUBECONF_CLUSTER_B}"

        ${JUNIT_CMD} upload_submariner_images_to_cluster_registry "${KUBECONF_CLUSTER_B}"

        # Before ACM 2.5 - Need to open ports and label nodes on Openstack (cloud prepare was not supported)
        if ! check_version_greater_or_equal "$ACM_VER_TAG" "2.5" ; then

          echo -e "\n# TODO: Run only if it's an openstack (on-prem) cluster"

          ${JUNIT_CMD} open_firewall_ports_on_openstack_cluster_b

          ${JUNIT_CMD} label_first_gateway_cluster_b

        fi

      fi

      # Cluster C configurations

      if [[ -s "$KUBECONF_CLUSTER_C" ]] && [[ "$CLEAN_CLUSTER_C" =~ ^(y|yes)$ || "$CREATE_CLUSTER_C" =~ ^(y|yes)$ ]] ; then

        ${JUNIT_CMD} add_elevated_user "${KUBECONF_CLUSTER_C}"

        # ${JUNIT_CMD} configure_ocp_garbage_collection_and_images_prune "${KUBECONF_CLUSTER_C}"

        ${JUNIT_CMD} configure_custom_registry_in_cluster "${KUBECONF_CLUSTER_C}"

        ${JUNIT_CMD} upload_submariner_images_to_cluster_registry "${KUBECONF_CLUSTER_C}"

      fi
    
    fi
    ### END of all Clusters and Registry configurations

    ### Submariner system tests prerequisites ###
    # Following will NOT be executed if using "--skip-tests sys" (useful for deployment without system tests)

    if [[ ! "$SKIP_TESTS" =~ ((sys)(,|$))+ ]]; then

      ### Create namespace and services for submariner system tests ###

      ${JUNIT_CMD} configure_namespace_for_submariner_tests_on_cluster_a

      ${JUNIT_CMD} install_netshoot_app_on_cluster_a

      if [[ -s "$CLUSTER_B_YAML" ]] && [[ -s "$KUBECONF_CLUSTER_B" ]] ; then

        export KUBECONF_MANAGED="${KUBECONF_CLUSTER_B}"

      elif [[ -s "$CLUSTER_C_YAML" ]] && [[ -s "$KUBECONF_CLUSTER_C" ]] ; then

        export KUBECONF_MANAGED="${KUBECONF_CLUSTER_C}"

      fi

      ${JUNIT_CMD} configure_namespace_for_submariner_tests_on_managed_cluster

      ${JUNIT_CMD} install_nginx_svc_on_managed_cluster

      ${JUNIT_CMD} test_basic_cluster_connectivity_before_submariner

      ${JUNIT_CMD} test_clusters_disconnected_before_submariner

    # Following will NOT be executed if using "--skip-tests e2e" (useful for running pkg unit-tests only):
    elif [[ ! "$SKIP_TESTS" =~ ((e2e)(,|$))+ ]]; then

      # Verify clusters status even if system tests were skipped

      ${JUNIT_CMD} test_cluster_status "${KUBECONF_HUB}"

      if [[ -s "$CLUSTER_B_YAML" ]] && [[ -s "$KUBECONF_CLUSTER_B" ]] ; then

        test_cluster_status "${KUBECONF_CLUSTER_B}"
      
      else

        check_if_cluster_is_active "${KUBECONF_CLUSTER_B}" || unset "KUBECONF_CLUSTER_B"

      fi

      if [[ -s "$CLUSTER_C_YAML" ]] && [[ -s "$KUBECONF_CLUSTER_C" ]] ; then

        test_cluster_status "${KUBECONF_CLUSTER_C}"

      else

        check_if_cluster_is_active "${KUBECONF_CLUSTER_C}" || unset "KUBECONF_CLUSTER_C"

      fi

      if [[ ! -s "$KUBECONF_CLUSTER_B" ]] && [[ ! -s "$KUBECONF_CLUSTER_C" ]] ; then

        FATAL "Both cluster B and cluster C are down. \
        Multi-Cluster tests require at least one more cluster (beside cluster A)"
        
      fi

    fi
    ### END of prerequisites for Submariner system tests  ###

    TITLE "OCP clusters and environment setup is ready"

  fi
  ### END of OCP general preparations for ALL tests ###


  ### Install ACM Hub, and create cluster set of the manged clusters for Submariner ###

  if [[ "$INSTALL_ACM" =~ ^(y|yes)$ ]] ; then

    # Setup ACM Hub and MCE

    # For ACM > 2.5 it is required to pre-install MCE, before ACM
    if check_if_mce_is_required ; then
      export INSTALL_MCE=YES
    fi

    ${JUNIT_CMD} install_mce_operator_on_hub "$MCE_VER_TAG"

    ${JUNIT_CMD} install_acm_operator_on_hub "$ACM_VER_TAG"

    ${JUNIT_CMD} check_olm_in_current_cluster "${KUBECONF_HUB}"

    ${JUNIT_CMD} create_mce_subscription "$MCE_VER_TAG"

    ${JUNIT_CMD} create_acm_subscription "$ACM_VER_TAG"

    # Skip MCE creation, as ACM should take care of it
    [[ "$INSTALL_MCE" != "YES" ]] || ${JUNIT_CMD} create_multicluster_engine "$MCE_VER_TAG"

    # Create ACM Hub instance

    ${JUNIT_CMD} create_acm_multiclusterhub "$ACM_VER_TAG"

  fi
  ### END of ACM Install ###

  ### Create ACM cluster-set and add the managed clusters ### 

  ${JUNIT_CMD} create_clusterset_for_submariner_in_acm_hub

  # Add first managed cluster A (the Hub)
  if [[ "$JOIN_CLUSTER_A" =~ ^(y|yes)$ ]] ; then

    ${JUNIT_CMD} create_and_import_managed_cluster "${KUBECONF_HUB}"

  fi

  # Add second managed cluster B
  if [[ -s "$KUBECONF_CLUSTER_B" ]] && [[ "$JOIN_CLUSTER_B" =~ ^(y|yes)$ ]] ; then

    ${JUNIT_CMD} create_and_import_managed_cluster "${KUBECONF_CLUSTER_B}"

  fi

  # Add third managed cluster C
  if [[ -s "$KUBECONF_CLUSTER_C" ]] && [[ "$JOIN_CLUSTER_C" =~ ^(y|yes)$ ]] ; then

    ${JUNIT_CMD} create_and_import_managed_cluster "${KUBECONF_CLUSTER_C}"

  fi
  

  ### Install Submariner (if using --subctl-version) ###

  if [[ "$INSTALL_SUBMARINER" =~ ^(y|yes)$ ]] ; then

    ### Deploy Submariner on the clusters with subctl CLI tool (if using --subctl-install) ###

    if [[ "$INSTALL_WITH_SUBCTL" =~ ^(y|yes)$ ]]; then

      # Configure subctl join params
      ${JUNIT_CMD} set_join_parameters_for_cluster_a

      # Override custom images (if using --registry-images)
      [[ ! "$REGISTRY_IMAGES" =~ ^(y|yes)$ ]] || ${JUNIT_CMD} append_custom_images_to_join_cmd_cluster_a

      # Install and test Broker on Cluster A
      ${JUNIT_CMD} install_broker_via_subctl_on_cluster_a

      ${JUNIT_CMD} test_broker_before_join

      # Join Cluster A with subctl

      ${JUNIT_CMD} run_subctl_join_on_cluster_a

      # Join Cluster B with subctl

      if [[ -s "$KUBECONF_CLUSTER_B" ]] && [[ "$JOIN_CLUSTER_B" =~ ^(y|yes)$ ]] ; then

        ${JUNIT_CMD} set_join_parameters_for_cluster_b

        [[ ! "$REGISTRY_IMAGES" =~ ^(y|yes)$ ]] || ${JUNIT_CMD} append_custom_images_to_join_cmd_cluster_b

        ${JUNIT_CMD} run_subctl_join_on_cluster_b

      fi

      # Join Cluster C with subctl

      if [[ -s "$KUBECONF_CLUSTER_C" ]] && [[ "$JOIN_CLUSTER_C" =~ ^(y|yes)$ ]] ; then

        ${JUNIT_CMD} set_join_parameters_for_cluster_c

        [[ ! "$REGISTRY_IMAGES" =~ ^(y|yes)$ ]] || ${JUNIT_CMD} append_custom_images_to_join_cmd_cluster_c

        ${JUNIT_CMD} run_subctl_join_on_cluster_c

      fi 

    else
      ### Otherwise (if NOT using --subctl-install) - Deploy Submariner on the clusters via API ###

      ${JUNIT_CMD} install_broker_via_api_on_cluster "${KUBECONF_HUB}"

      ${JUNIT_CMD} install_submariner_operator_on_cluster "${KUBECONF_HUB}"

      ${JUNIT_CMD} configure_submariner_addon_for_acm_managed_cluster "${KUBECONF_HUB}"

      if [[ -s "$KUBECONF_CLUSTER_B" ]] && [[ "$JOIN_CLUSTER_B" =~ ^(y|yes)$ ]] ; then

        ${JUNIT_CMD} install_submariner_operator_on_cluster "${KUBECONF_CLUSTER_B}"

        ${JUNIT_CMD} configure_submariner_addon_for_acm_managed_cluster "${KUBECONF_CLUSTER_B}"

      fi

      if [[ -s "$KUBECONF_CLUSTER_C" ]] && [[ "$JOIN_CLUSTER_C" =~ ^(y|yes)$ ]] ; then

        ${JUNIT_CMD} install_submariner_operator_on_cluster "${KUBECONF_CLUSTER_C}"

        ${JUNIT_CMD} configure_submariner_addon_for_acm_managed_cluster "${KUBECONF_CLUSTER_C}"

      fi

    fi
    ### END of install with subctl / API ###

    TITLE "Once Submariner install is completed - \$TEST_STATUS_FILE is considered UNSTABLE.
    Tests will be reported to Polarion ($TEST_STATUS_FILE with exit code 2)"

    # Get test exit status (from file $TEST_STATUS_FILE)
    SCRIPT_EXIT_STATUS="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat "$TEST_STATUS_FILE")"

    # Update test exit status to 2, unless it is already 1 or 2
    [[ "$SCRIPT_EXIT_STATUS" == @(1|2) ]] || echo 2 > "$TEST_STATUS_FILE"

  fi
  ### END of INSTALL_SUBMARINER ###


  ### Running High-level / E2E / Unit Tests (if not requested to --skip-tests sys / all) ###

  if [[ ! "$SKIP_TESTS" =~ ((sys|all)(,|$))+ ]]; then

    ### Running High-level (System) tests of Submariner ###

    ${JUNIT_CMD} test_cluster_machines "${KUBECONF_CLUSTER_A}"

    [[ ! -s "$KUBECONF_CLUSTER_B" ]] || ${JUNIT_CMD} test_cluster_machines "${KUBECONF_CLUSTER_B}"

    [[ ! -s "$KUBECONF_CLUSTER_C" ]] || ${JUNIT_CMD} test_cluster_machines "${KUBECONF_CLUSTER_C}"

    # Testing the Submariner gateway disaster recovery just on the Broker cluster (using $KUBECONF_HUB)

    ${JUNIT_CMD} test_public_ip_on_gateway_node

    ${JUNIT_CMD} test_disaster_recovery_of_gateway_nodes

    ${JUNIT_CMD} test_renewal_of_gateway_and_public_ip

    ${JUNIT_CMD} test_submariner_resources_cluster_a

    # Testing Submariner resources on all clusters

    [[ ! -s "$KUBECONF_CLUSTER_B" ]] || ${JUNIT_CMD} test_submariner_resources_cluster_b

    [[ ! -s "$KUBECONF_CLUSTER_C" ]] || ${JUNIT_CMD} test_submariner_resources_cluster_c

    # Testing Submariner cable-driver on all clusters

    ${JUNIT_CMD} test_cable_driver_cluster_a

    [[ ! -s "$KUBECONF_CLUSTER_B" ]] || ${JUNIT_CMD} test_cable_driver_cluster_b

    [[ ! -s "$KUBECONF_CLUSTER_C" ]] || ${JUNIT_CMD} test_cable_driver_cluster_c

    # Testing Submariner HA (High Availability) status on all clusters

    ${JUNIT_CMD} test_ha_status_cluster_a

    [[ ! -s "$KUBECONF_CLUSTER_B" ]] || ${JUNIT_CMD} test_ha_status_cluster_b

    [[ ! -s "$KUBECONF_CLUSTER_C" ]] || ${JUNIT_CMD} test_ha_status_cluster_c

    # Testing Submariner connectivity status on all clusters

    ${JUNIT_CMD} test_submariner_connection_cluster_a

    [[ ! -s "$KUBECONF_CLUSTER_B" ]] || ${JUNIT_CMD} test_submariner_connection_cluster_b

    [[ ! -s "$KUBECONF_CLUSTER_C" ]] || ${JUNIT_CMD} test_submariner_connection_cluster_c

    # Testing SubCtl (Submariner CLI tool) info on all clusters

    ${JUNIT_CMD} test_subctl_show_on_merged_kubeconfigs

    # Testing IPSec status on all clusters

    ${JUNIT_CMD} test_ipsec_status_cluster_a

    [[ ! -s "$KUBECONF_CLUSTER_B" ]] || ${JUNIT_CMD} test_ipsec_status_cluster_b

    [[ ! -s "$KUBECONF_CLUSTER_C" ]] || ${JUNIT_CMD} test_ipsec_status_cluster_c

    # Testing GlobalNet connectivity (if enabled) on all clusters

    if [[ "$GLOBALNET" =~ ^(y|yes)$ ]] ; then

      ${JUNIT_CMD} test_globalnet_status_cluster_a

      [[ ! -s "$KUBECONF_CLUSTER_B" ]] || ${JUNIT_CMD} test_globalnet_status_cluster_b

      [[ ! -s "$KUBECONF_CLUSTER_C" ]] || ${JUNIT_CMD} test_globalnet_status_cluster_c
    fi

    # Test service-discovery (lighthouse) on all clusters

    ${JUNIT_CMD} test_lighthouse_status_cluster_a

    [[ ! -s "$KUBECONF_CLUSTER_B" ]] || ${JUNIT_CMD} test_lighthouse_status_cluster_b

    [[ ! -s "$KUBECONF_CLUSTER_C" ]] || ${JUNIT_CMD} test_lighthouse_status_cluster_c

    ### Running connectivity tests between the clusters ###
    # (Validating that now Submariner made the connection possible)

    if [[ -s "$KUBECONF_CLUSTER_B" ]] ; then

      export KUBECONF_MANAGED="${KUBECONF_CLUSTER_B}"

    elif [[ -s "$KUBECONF_CLUSTER_C" ]] ; then

      export KUBECONF_MANAGED="${KUBECONF_CLUSTER_C}"

    fi

    ${JUNIT_CMD} test_clusters_connected_by_service_ip

    ${JUNIT_CMD} install_new_netshoot_cluster_a

    ${JUNIT_CMD} install_nginx_headless_namespace_managed_cluster

    # Since Submariner 0.12, globalnet (v2) supports headless services, but not pod to pod connectivity
    if check_version_greater_or_equal "$SUBM_VER_TAG" "0.12" ; then
      export GN_VER=V2
    else
      export GN_VER=V1
    fi

    if [[ "$GLOBALNET" =~ ^(y|yes)$ ]] && [[ "$GN_VER" == "V1" ]] ; then

      ${JUNIT_CMD} test_new_netshoot_ip_cluster_a_globalnet_v1

      ${JUNIT_CMD} test_nginx_headless_ip_globalnet_v1

    else
      echo -e "\n# TODO: Need new system tests for GlobalNet V2 (Pod to Pod connectivity is not supported since Submariner 0.12)"
    fi

    # Test the default (pre-installed) netshoot and nginx with service-discovery

    ${JUNIT_CMD} export_nginx_default_namespace_managed_cluster

    ${JUNIT_CMD} test_clusters_connected_full_domain_name

    ${JUNIT_CMD} test_clusters_cannot_connect_short_service_name

    # Test the new netshoot and headless Nginx service-discovery
    if [[ "$GLOBALNET" =~ ^(y|yes)$ ]] && [[ "$GN_VER" == "V1" ]] ; then

      # In Submariner < 0.12, globalnet (v1) supports pod to pod connectivity
      ${JUNIT_CMD} test_clusters_connected_overlapping_cidrs_globalnet_v1

    else

      ${JUNIT_CMD} export_nginx_headless_namespace_managed_cluster

      ${JUNIT_CMD} test_clusters_connected_headless_service_on_new_namespace

      ${JUNIT_CMD} test_clusters_cannot_connect_headless_short_service_name
    fi


    ### Running diagnose and benchmark tests with subctl

    ${JUNIT_CMD} test_subctl_diagnose_on_merged_kubeconfigs

    ${JUNIT_CMD} test_subctl_benchmarks

    TITLE "Once System tests are completed - \$TEST_STATUS_FILE is considered UNSTABLE.
    Tests will be reported to Polarion ($TEST_STATUS_FILE with exit code 2)"

    # Get system tests status (from file $TEST_STATUS_FILE)
    sys_tests_status="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat "$TEST_STATUS_FILE")"

    # Update $TEST_STATUS_FILE to 2, unless it is already 1 or 2
    [[ "$sys_tests_status" == @(1|2) ]] || echo 2 > "$TEST_STATUS_FILE"

  fi # END of all System tests


  ### Running Submariner tests with Ginkgo or with subctl commands

  # Get system tests status (from file $TEST_STATUS_FILE), and run Golang tests only if system tests passed
  sys_tests_status="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat "$TEST_STATUS_FILE")"

  if [[ ! "$SKIP_TESTS" =~ all && "$sys_tests_status" != 1 ]]; then

    ### Compiling Submariner projects in order to run Ginkgo tests with GO

    if [[ "$BUILD_GO_TESTS" =~ ^(y|yes)$ ]] ; then
      verify_golang || FATAL "No Golang compiler found. Try to run again with option '--config-golang'"

      # BUG "Non-rootless Nginx in Submariner 0.12.0 brakes E2E tests" \
      # "Build Submariner repo from 'devel' branch instead" \
      # "https://bugzilla.redhat.com/show_bug.cgi?id=2083134"
      # ${JUNIT_CMD} build_submariner_repos "devel" # "$SUBM_VER_TAG"

      ${JUNIT_CMD} build_submariner_repos "$SUBM_VER_TAG"

    fi

    ### Running Unit-tests in Submariner project with Ginkgo

    if [[ ! "$SKIP_TESTS" =~ pkg ]] && [[ "$BUILD_GO_TESTS" =~ ^(y|yes)$ ]]; then
      ${JUNIT_CMD} test_submariner_packages

      tests_title="Submariner Unit-Tests"

      if tail -n 5 "$E2E_LOG" | grep 'FAIL' ; then
        ginkgo_tests_status=FAILED
        BUG "$tests_title FAILED"
      else
        TITLE "$tests_title PASSED"
      fi

    fi

    if [[ ! "$SKIP_TESTS" =~ e2e ]]; then

      if [[ "$BUILD_GO_TESTS" =~ ^(y|yes)$ ]] ; then

      ### Running E2E tests in Submariner and Lighthouse projects with Ginkgo

        ${JUNIT_CMD} test_submariner_e2e_with_go

        tests_title="Submariner End-to-End Ginkgo tests"

        if tail -n 5 "$E2E_LOG" | grep 'FAIL' ; then
          ginkgo_tests_status=FAILED
          BUG "$tests_title FAILED"
        else
          TITLE "$tests_title PASSED"
        fi

        ${JUNIT_CMD} test_lighthouse_e2e_with_go

        tests_title="Lighthouse End-to-End Ginkgo tests"

        if tail -n 5 "$E2E_LOG" | grep 'FAIL' ; then
          ginkgo_tests_status=FAILED
          BUG "$tests_title FAILED"
        else
          TITLE "$tests_title PASSED"
        fi

      else

      ### Running E2E tests with subctl

        ${JUNIT_CMD} test_submariner_e2e_with_subctl

        tests_title="SubCtl End-to-End tests"

        if tail -n 5 "$E2E_LOG" | grep 'FAIL' ; then
          ginkgo_tests_status=FAILED
          BUG "$tests_title FAILED"
        else
          TITLE "$tests_title PASSED"
        fi
      fi
    fi

    # If all E2E tests passed, update $TEST_STATUS_FILE to 0 (unless $sys_tests_status is already 1 or 2)
    if [[ "$ginkgo_tests_status" != FAILED && "$sys_tests_status" != @(1|2) ]] ; then
      echo 0 > "$TEST_STATUS_FILE"
    else
      FATAL "Submariner E2E or Unit-Tests have ended with failures, please investigate."
    fi
  
  elif [[ -z "$SCRIPT_EXIT_STATUS" ]]; then
    TITLE "No tests were required to be executed, but \$SCRIPT_EXIT_STATUS was not yet set - Changing $TEST_STATUS_FILE to UNSTABLE"

    # Update test exit status to 2
    echo 2 > "$TEST_STATUS_FILE"
  fi

  # Update $TEST_STATUS_FILE with current $SCRIPT_EXIT_STATUS value (if not null)
  if [[ -n "$SCRIPT_EXIT_STATUS" ]]; then
    echo "$SCRIPT_EXIT_STATUS" > "$TEST_STATUS_FILE"
  fi

) |& tee -a "$SYS_LOG"


#######################################################################################################
#   End (or exit) of Main - Now publishing to Polarion, Creating HTML report, and archive artifacts   #
#######################################################################################################

# Printing output both to stdout and to $SYS_LOG with tee
(
  set +e # To reach script end, even on error, to create report and save artifacts

  trap '' DEBUG # DONT trap_to_debug_commands

  cd "${SCRIPT_DIR}"

  # ------------------------------------------

  # Get test exit status (from file $TEST_STATUS_FILE)
  SCRIPT_EXIT_STATUS="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat "$TEST_STATUS_FILE")"

  if [[ "$SCRIPT_EXIT_STATUS" == 0 ]] ; then
    # If script got 0 SCRIPT_EXIT_STATUS here - All tests of Submariner have passed ;-)
    TITLE "SUBMARINER SYSTEM AND E2E TESTS PASSED"
  fi

  echo -e "\n# Publishing test results to Polarion = $UPLOAD_TO_POLARION"
  echo -e "\n# $TEST_STATUS_FILE includes: [${SCRIPT_EXIT_STATUS}]\n"

  ### Upload Junit xmls to Polarion - only if requested by user CLI, and $SCRIPT_EXIT_STATUS is either 0 (pass) or 2 (unstable) ###
  if [[ "$UPLOAD_TO_POLARION" =~ ^(y|yes)$ ]] && [[ "$SCRIPT_EXIT_STATUS" == @(0|2) ]] ; then
    create_all_test_results_in_polarion || :
  else
    echo -e "\n# Skip publishing test results to Polarion \n"
  fi

  # ------------------------------------------

  ### Creating HTML report from console output ###

  message="Creating HTML Report"

  # If $TEST_STATUS_FILE does not include 0 (0 = all Tests passed) or 2 (2 = some tests passed) - it means that system tests have failed (or not run at all)
  if [[ "$SCRIPT_EXIT_STATUS" != @(0|2) ]] ; then
    message="$message - System tests failed with exit status [$SCRIPT_EXIT_STATUS]"
    color="$RED"
  fi
  PROMPT "$message" "$color"

  TITLE "Creating HTML Report
  SCRIPT_EXIT_STATUS = $SCRIPT_EXIT_STATUS
  SYS_LOG = $SYS_LOG
  REPORT_NAME = $REPORT_NAME
  REPORT_FILE = $REPORT_FILE
  "

  if [[ -n "$REPORT_FILE" ]] ; then
    echo -e "\n# Remove path and replace all spaces from REPORT_FILE: '$REPORT_FILE'"
    REPORT_FILE="$(basename "${REPORT_FILE// /_}")"
  fi

) |& tee -a "$SYS_LOG"


# ------------------------------------------


echo -e "\n# Clean $SYS_LOG from sh2ju debug lines (+++), if CLI option: --debug was NOT used"
[[ "$SCRIPT_DEBUG_MODE" =~ ^(yes|y)$ ]] || sed -i 's/+++.*//' "$SYS_LOG"

TITLE "Set Html report headlines with important test and environment info"
html_report_headlines=""

if [[ -s "$POLARION_RESULTS" ]] ; then
  headline="Polarion results:"
  echo -e "\n# ${headline}"
  cat "$POLARION_RESULTS"

  html_report_headlines+="<b>${headline}</b>
  $(< "$POLARION_RESULTS")"
fi

# Loop on all *.info files and add them to report description:
info_files="${OUTPUT_DIR}/*.info"
for info in $info_files ; do
  if [[ -s "$info" ]] ; then
    echo -e "$info :
    $(< "$info") \n\n"

    # The first line of info file with bold font
    html_report_headlines+="$(sed -r '1 s/^(.*)$/<br> <b> \1 <\/b>/' "$info")" || :
  fi
done

if [[ -s "$PRODUCT_IMAGES" ]] ; then
  headline="Submariner images:"
  echo -e "\n# ${headline}"
  cat "$PRODUCT_IMAGES"

  html_report_headlines+="
  <br> <b>${headline}</b>
  $(< "$PRODUCT_IMAGES")"
fi


### Create REPORT_FILE (html) from $SYS_LOG using log_to_html()
# If REPORT_FILE was not set externally, set it as the latest html file that was created

log_to_html "$SYS_LOG" "$REPORT_NAME" "$REPORT_FILE" "$html_report_headlines" && \
REPORT_FILE="${REPORT_FILE:-$(ls -1 -tc *.html | head -1)}" || :

# ------------------------------------------

### Collecting artifacts and compressing to tar.gz archive ###

if [[ -n "${REPORT_FILE}" ]] ; then
   ARCHIVE_FILE="${OUTPUT_DIR}/${REPORT_FILE%.*}_${DATE_TIME}.tar.gz"
   cp -f "${REPORT_FILE}" "${OUTPUT_DIR}/$(basename "$REPORT_FILE")"
else
   ARCHIVE_FILE="${OUTPUT_DIR}/${PWD##*/}_${DATE_TIME}.tar.gz"
fi

TITLE "Compressing Report, Log, Kubeconfigs and other test artifacts into: ${ARCHIVE_FILE}"

# Artifact OCP clusters kubeconfigs and logs
if [[ -s "${CLUSTER_A_YAML}" ]] ; then
  echo -e "\n# Saving kubeconfig and OCP installer log of Cluster A"

  cp -f "${KUBECONF_HUB}" "${OUTPUT_DIR}/kubconf_${CLUSTER_A_NAME}" || :
  cp -f "${KUBECONF_HUB}.bak" "${OUTPUT_DIR}/kubconf_${CLUSTER_A_NAME}.bak" || :
  cp -f "${CLUSTER_A_DIR}/metadata.json" "${OUTPUT_DIR}/metadata_${CLUSTER_A_NAME}.json" || :

  find "${CLUSTER_A_DIR}" -type f -iname "*.log" -exec \
  sh -c 'cp "{}" "'${OUTPUT_DIR}'/cluster_a_$(basename "$(dirname "{}")")$(basename "{}")"' \; || :
fi

if [[ -s "${CLUSTER_B_YAML}" ]] ; then
  echo -e "\n# Saving kubeconfig and OCP installer log of Cluster B"

  cp -f "${KUBECONF_CLUSTER_B}" "${OUTPUT_DIR}/kubconf_${CLUSTER_B_NAME}" || :
  cp -f "${KUBECONF_CLUSTER_B}.bak" "${OUTPUT_DIR}/kubconf_${CLUSTER_B_NAME}.bak" || :
  cp -f "${CLUSTER_B_DIR}/metadata.json" "${OUTPUT_DIR}/metadata_${CLUSTER_B_NAME}.json" || :

  find "${CLUSTER_B_DIR}" -type f -iname "*.log" -exec \
  sh -c 'cp "{}" "'${OUTPUT_DIR}'/cluster_b_$(basename "$(dirname "{}")")$(basename "{}")"' \; || :
fi

if [[ -s "${CLUSTER_C_YAML}" ]] ; then
  echo -e "\n# Saving kubeconfig and OCP installer log of Cluster C"

  cp -f "${KUBECONF_CLUSTER_C}" "${OUTPUT_DIR}/kubconf_${CLUSTER_C_NAME}" || :
  cp -f "${KUBECONF_CLUSTER_C}.bak" "${OUTPUT_DIR}/kubconf_${CLUSTER_C_NAME}.bak" || :
  cp -f "${CLUSTER_C_DIR}/metadata.json" "${OUTPUT_DIR}/metadata_${CLUSTER_C_NAME}.json" || :

  find "${CLUSTER_C_DIR}" -type f -iname "*.log" -exec \
  sh -c 'cp "{}" "'${OUTPUT_DIR}'/cluster_c_$(basename "$(dirname "{}")")$(basename "{}")"' \; || :
fi

# Artifact ${OCP_USR}.sec file
find "${WORKDIR}" -maxdepth 1 -type f -iname "${OCP_USR}.sec" -exec cp -f "{}" ${OUTPUT_DIR}/ \; || :

# # Artifact broker.info file (if created with subctl deploy) - Depecated.
# find "${WORKDIR}" -maxdepth 1 -type f -iname "$SUBM_BROKER_INFO" -exec cp -f "{}" "${OUTPUT_DIR}/submariner_{}" \; || :

# Compress the required artifacts (either files or directories)

find "${OUTPUT_DIR}" -maxdepth 1 \( \
-iname "kubconf_*" -o \
-iname "submariner*" -o \
-iname "*.sec" -o \
-iname "*.xml" -o \
-iname "*.yaml" -o \
-iname "*.json" -o \
-iname "*.log" -o \
-iname "*.ver" -o \
-iname "*.html" \
\) -print0 | \
tar --transform 's/.*\///g' --dereference --hard-dereference -cvzf "${ARCHIVE_FILE}" --null -T - || :

# Compress "submariner-gather" directory (if it was created with subctl gather)
subm_gather_gz="${OUTPUT_DIR}/submariner-gather_${DATE_TIME}.tar.gz"

find "${WORKDIR}" -maxdepth 1 -type d -iname "submariner-gather*" -print0 | \
tar -cvzf "${subm_gather_gz}" --null -T - || :

TITLE "Archive \"$ARCHIVE_FILE\" now contains:"
tar tvf "$ARCHIVE_FILE"

TITLE "To view in your Browser, run:\n tar -xvf ${ARCHIVE_FILE}; firefox ${REPORT_FILE}"

# Get test exit status (from file $TEST_STATUS_FILE)
SCRIPT_EXIT_STATUS="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat "$TEST_STATUS_FILE")"

TITLE "Exiting script with \$TEST_STATUS_FILE return code: [$SCRIPT_EXIT_STATUS]"

if [[ -z "$SCRIPT_EXIT_STATUS" ]] ; then
  exit 3
else
  exit "$SCRIPT_EXIT_STATUS"
fi


# ------------------------------------------
