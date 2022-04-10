#!/bin/bash

#######################################################################################################
#                                                                                                     #
# Setup ACM with Submariner on public clouds (Amazon and Google) and On-premise (OpenStack)           #
# By Noam Manos, nmanos@redhat.com                                                                    #
#                                                                                                     #
# You can find latest script files here:                                                              #
# https://github.com/redhat-openshift/acm-submariner-tester                                           #
#                                                                                                     #
# It is assumed that you have existing Openshift configuration files (install-config.yaml)            #
# for both cluster A (AWS) and clusters B or C (OSP/GCP/AWS), in the current directory.               #
#                                                                                                     #
# For cluster A - use Openshift-installer config format. For example on Amazon cloud:                 #
# https://github.com/openshift/installer/blob/master/docs/user/aws/customization.md#examples          #
#                                                                                                     #
# For cluster B - use OCPUP config format:                                                            #
# https://github.com/redhat-openshift/ocpup#create-config-file                                        #
#                                                                                                     #
# For cluster C - use Openshift-installer config format. For example on Google cloud:                 #
# https://github.com/openshift/installer/blob/master/docs/user/gcp/customization.md#examples          #
#                                                                                                     #
# To create those config files, you need to supply your AWS pull secret, and SSH public key:          #
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
# (4) Your Red Hat Openshift pull secret, found in:                                                   #
# https://cloud.redhat.com/openshift/install/aws/installer-provisioned                                #
# It is used by Openshift-installer to download OCP images from Red Hat repositories.                 #
#                                                                                                     #
# (5) Your SSH Public Key, that you generated with " ssh-keygen -b 4096 "                             #
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

  * Create OCP cluster A:                              --create-cluster-a
  * Create OSP cluster B:                              --create-cluster-b
  * Create OCP cluster C:                              --create-cluster-c
  * Destroy existing OCP cluster A:                    --destroy-cluster-a
  * Destroy existing OSP cluster B:                    --destroy-cluster-b
  * Destroy existing OCP cluster C:                    --destroy-cluster-c
  * Reset (create & destroy) OCP cluster A:            --reset-cluster-a
  * Reset (create & destroy) OSP cluster B:            --reset-cluster-b
  * Reset (create & destroy) OCP cluster C:            --reset-cluster-c
  * Clean existing OCP cluster A:                      --clean-cluster-a
  * Clean existing OSP cluster B:                      --clean-cluster-b
  * Clean existing OCP cluster C:                      --clean-cluster-c
  * Download OCP Installer version:                    --get-ocp-installer [latest / x.y.z / nightly]
  * Download latest OCPUP Tool:                        --get-ocpup-tool
  * Install Golang if missing:                         --config-golang
  * Install AWS-CLI and configure access:              --config-aws-cli
  * Skip OCP clusters setup (destroy/create/clean):    --skip-ocp-setup

- Submariner installation options:

  * Install ACM operator version:                      --acm-version [x.y.z]
  * Install Submariner operator version:               --subctl-version [latest / x.y.z / {tag}]
  * Override images from a custom registry:            --registry-images
  * Configure and test GlobalNet:                      --globalnet
  * Install Submariner with SubCtl:                    --subctl-install

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

`./setup_subm.sh --clean-cluster-a --clean-cluster-b --acm-version 2.4.2 --subctl-version 0.11.2 --registry-images`

  * Reuse (clean) existing clusters
  * Install ACM 2.4.2 release
  * Install Submariner 0.11.2 release
  * Override Submariner images from a custom repository (configured in REGISTRY variables)
  * Run Submariner E2E tests (with subctl)


`./setup_subm.sh --get-ocp-installer nightly --reset-cluster-c --clean-cluster-a --subctl-version subctl-devel --build-tests --junit`

  * Download OCP installer pre-release (nightly)
  * Recreate new cluster C (e.g. on GCP)
  * Clean existing cluster A (e.g. on AWS)
  * Install "subctl-devel" (subctl development branch)
  * Build and run Submariner E2E and unit-tests with GO
  * Create Junit tests result (xml files)

----------------------------------------------------------------------'


####################################################################################
#               Global bash configurations and external sources                    #
####################################################################################

# Set $SCRIPT_DIR as current absolute path where this script runs in (e.g. Jenkins build directory)
# Note that files in $SCRIPT_DIR are not guaranteed to be permanently saved, as in $WORKDIR
SCRIPT_DIR="$(dirname "$(realpath -s $0)")"
export SCRIPT_DIR

### Import Submariner setup variables ###
source "$SCRIPT_DIR/subm_variables"

### Import Test and Helper functions ###
source "$SCRIPT_DIR/helper_functions"
source "$SCRIPT_DIR/test_functions"

### Import ACM Functions ###
source "$SCRIPT_DIR/acm/downstream_push_bundle_to_olm_catalog.sh"
source "$SCRIPT_DIR/acm/downstream_deploy_bundle_acm_operator.sh"

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


#####################################################################################################
#         Constant variables and files (overrides previous variables from sourced files)            #
#####################################################################################################

# Date-time signature for log and report files
DATE_TIME="$(date +%d%m%Y_%H%M)"
export DATE_TIME

# Global temp file
TEMP_FILE="`mktemp`_temp"
export TEMP_FILE

# JOB_NAME is a prefix for files, which is the name of current script directory
JOB_NAME="$(basename "$SCRIPT_DIR")"
export JOB_NAME
export SHELL_JUNIT_XML="$SCRIPT_DIR/${JOB_NAME}_sys_junit.xml"
export PKG_JUNIT_XML="$SCRIPT_DIR/${JOB_NAME}_pkg_junit.xml"
export E2E_JUNIT_XML="$SCRIPT_DIR/${JOB_NAME}_e2e_junit.xml"
export LIGHTHOUSE_JUNIT_XML="$SCRIPT_DIR/${JOB_NAME}_lighthouse_junit.xml"

export E2E_LOG="$SCRIPT_DIR/${JOB_NAME}_e2e_output.log"
: > "$E2E_LOG"

# Set SYS_LOG name according to REPORT_NAME (from subm_variables)
export REPORT_NAME="${REPORT_NAME:-Submariner Tests}"
# SYS_LOG="${REPORT_NAME// /_}" # replace all spaces with _
# SYS_LOG="${SYS_LOG}_${DATE_TIME}.log" # can also consider adding timestamps with: ts '%H:%M:%.S' -s
SYS_LOG="${SCRIPT_DIR}/${JOB_NAME}_${DATE_TIME}.log" # can also consider adding timestamps with: ts '%H:%M:%.S' -s
: > "$SYS_LOG"

# Common test variables
export NEW_NETSHOOT_CLUSTER_A="${NETSHOOT_CLUSTER_A}-new" # A NEW Netshoot pod on cluster A
export HEADLESS_TEST_NS="${TEST_NS}-headless" # Namespace for the HEADLESS $NGINX_CLUSTER_BC service


#################################################################################
#               Saving important test properties in local files                 #
#################################################################################

# File and variable to store test status. Resetting to empty - before running tests (i.e. don't publish to Polarion yet)
export TEST_STATUS_FILE="$SCRIPT_DIR/test_status.rc"
export EXIT_STATUS
: > $TEST_STATUS_FILE

# File to store SubCtl version
export SUBCTL_VERSION_FILE="$SCRIPT_DIR/subctl.ver"
: > $SUBCTL_VERSION_FILE

# File to store Submariner installed versions
export SUBMARINER_VERSIONS_FILE="$SCRIPT_DIR/submariner.ver"
: > $SUBMARINER_VERSIONS_FILE

# File to store SubCtl JOIN command for cluster A
export SUBCTL_JOIN_CLUSTER_A_FILE="$SCRIPT_DIR/subctl_join_cluster_a.cmd"
: > $SUBCTL_JOIN_CLUSTER_A_FILE

# File to store SubCtl JOIN command for cluster B
export SUBCTL_JOIN_CLUSTER_B_FILE="$SCRIPT_DIR/subctl_join_cluster_b.cmd"
: > $SUBCTL_JOIN_CLUSTER_B_FILE

# File to store SubCtl JOIN command for cluster C
export SUBCTL_JOIN_CLUSTER_C_FILE="$SCRIPT_DIR/subctl_join_cluster_c.cmd"
: > $SUBCTL_JOIN_CLUSTER_C_FILE

# File to store Polarion auth
export POLARION_AUTH="$SCRIPT_DIR/polarion.auth"
: > $POLARION_AUTH

# File to store Polarion test-run report link
export POLARION_RESULTS="$SCRIPT_DIR/polarion_${DATE_TIME}.results"
: > $POLARION_RESULTS

# File to store Submariner images version details
export SUBMARINER_IMAGES="$SCRIPT_DIR/submariner_images.ver"
: > $SUBMARINER_IMAGES


####################################################################################
#                             CLI Script arguments                                 #
####################################################################################

check_cli_args() {
  [[ -n "$1" ]] || ( echo -e "\n# Missing arguments. Please see Help with: -h" && exit 1 )
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  export got_user_input=TRUE
  # Consume next (1st) argument
  case $1 in
  -h|--help)
    echo -e "\n# ${disclosure}" && exit 0
    shift ;;
  -d|--debug)
    SCRIPT_DEBUG_MODE=YES
    shift ;;
  --get-ocp-installer)
    check_cli_args "$2"
    export OCP_VERSION="$2" # E.g as in https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
    GET_OCP_INSTALLER=YES
    shift 2 ;;
  --get-ocpup-tool)
    GET_OCPUP_TOOL=YES
    shift ;;
  --acm-version)
    check_cli_args "$2"
    export ACM_VER_TAG="$2"
    INSTALL_ACM=YES
    shift 2 ;;
  --subctl-version)
    check_cli_args "$2"
    export SUBM_VER_TAG="$2"
    INSTALL_SUBMARINER=YES
    shift 2 ;;
  --registry-images)
    REGISTRY_IMAGES=YES
    shift ;;
  --build-tests)
    BUILD_GO_TESTS=YES
    shift ;;
  --destroy-cluster-a)
    ocp_installer_required=YES
    DESTROY_CLUSTER_A=YES
    shift ;;
  --create-cluster-a)
    ocp_installer_required=YES
    CREATE_CLUSTER_A=YES
    shift ;;
  --reset-cluster-a)
    ocp_installer_required=YES
    RESET_CLUSTER_A=YES
    shift ;;
  --clean-cluster-a)
    CLEAN_CLUSTER_A=YES
    shift ;;
  --destroy-cluster-b)
    ocpup_tool_required=YES
    DESTROY_CLUSTER_B=YES
    shift ;;
  --create-cluster-b)
    ocpup_tool_required=YES
    CREATE_CLUSTER_B=YES
    shift ;;
  --reset-cluster-b)
    ocpup_tool_required=YES
    RESET_CLUSTER_B=YES
    shift ;;
  --clean-cluster-b)
    CLEAN_CLUSTER_B=YES
    shift ;;
  --destroy-cluster-c)
    ocp_installer_required=YES
    DESTROY_CLUSTER_C=YES
    shift ;;
  --create-cluster-c)
    ocp_installer_required=YES
    CREATE_CLUSTER_C=YES
    shift ;;
  --reset-cluster-c)
    ocp_installer_required=YES
    RESET_CLUSTER_C=YES
    shift ;;
  --clean-cluster-c)
    CLEAN_CLUSTER_C=YES
    shift ;;
  --subctl-install)
    INSTALL_WITH_SUBCTL=YES
    shift ;;
  --globalnet)
    GLOBALNET=YES
    shift ;;
  --cable-driver)
    check_cli_args "$2"
    subm_cable_driver="$2" # libreswan / strongswan [Deprecated]
    shift 2 ;;
  --skip-ocp-setup)
    SKIP_OCP_SETUP=YES
    shift ;;
  --skip-tests)
    check_cli_args "$2"
    SKIP_TESTS="$2" # sys,e2e,pkg,all
    shift 2 ;;
  --print-logs)
    PRINT_LOGS=YES
    shift ;;
  --config-golang)
    CONFIG_GOLANG=YES
    shift ;;
  --config-aws-cli)
    CONFIG_AWS_CLI=YES
    shift ;;
  --junit)
    CREATE_JUNIT_XML=YES
    export junit_cmd="record_junit $SHELL_JUNIT_XML"
    shift ;;
  --polarion)
    UPLOAD_TO_POLARION=YES
    shift ;;
  --import-vars)
    check_cli_args "$2"
    export GLOBAL_VARS="$2"
    TITLE "Importing additional variables from file:
    $GLOBAL_VARS"
    source "$GLOBAL_VARS"
    shift 2 ;;
  -*)
    echo -e "${disclosure} \n\n$0: Error - unrecognized option: $1" 1>&2
    exit 1 ;;
  *)
    break ;;
  esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters


####################################################################################
#               Get User input (only for missing CLI arguments)                    #
####################################################################################

if [[ -z "$got_user_input" ]]; then
  echo -e "\n# ${disclosure}"

  # User input: $SKIP_OCP_SETUP - to skip OCP clusters setup (destroy / create / clean)
  while [[ ! "$SKIP_OCP_SETUP" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to run without setting-up (destroy / create / clean) OCP clusters ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    SKIP_OCP_SETUP=${input:-NO}
  done

  if [[ ! "$SKIP_OCP_SETUP" =~ ^(yes|y)$ ]]; then

    # User input: $GET_OCP_INSTALLER - to download_ocp_installer
    while [[ ! "$GET_OCP_INSTALLER" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to download OCP Installer ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      GET_OCP_INSTALLER=${input:-no}
    done

    # User input: $OCP_VERSION - to download_ocp_installer with specific version
    if [[ "$GET_OCP_INSTALLER" =~ ^(yes|y)$ ]]; then
      while [[ ! "$OCP_VERSION" =~ ^[0-9a-Z]+$ ]]; do
        echo -e "\n${YELLOW}Which OCP Installer version do you want to download ? ${NO_COLOR}
        Enter version number, or nothing to install latest version: "
        read -r input
        OCP_VERSION=${input:-latest}
      done
    fi

    # User input: $GET_OCPUP_TOOL - to build_ocpup_tool_latest
    while [[ ! "$GET_OCPUP_TOOL" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to download OCPUP tool ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      GET_OCPUP_TOOL=${input:-no}
    done

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

    # User input: $RESET_CLUSTER_B - to destroy_osp_cluster AND create_osp_cluster
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
    echo -e "\n${YELLOW}Do you want to run without executing Submariner Tests (System, E2E, Unit-Tests, or all) ? ${NO_COLOR}
    Enter any \"sys,e2e,pkg,all\", or nothing to skip: "
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

  # User input: $CONFIG_AWS_CLI - to install latest aws-cli and configure aws access
  while [[ ! "$CONFIG_AWS_CLI" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to install aws-cli and configure AWS access ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    CONFIG_AWS_CLI=${input:-NO}
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

### Set script in debug/verbose mode, if used CLI option: --debug / -d ###
if [[ "$SCRIPT_DEBUG_MODE" =~ ^(yes|y)$ ]]; then
  # Extra verbosity for oc commands:
  # https://kubernetes.io/docs/reference/kubectl/cheatsheet/#kubectl-output-verbosity-and-debugging
  # export VERBOSE_FLAG="--v=2"
  # export OC="$OC $VERBOSE_FLAG"

  # Debug flag for ocpup and aws commands
  export DEBUG_FLAG="--debug"

else
  # Clear trap_to_debug_commands function
  trap_to_debug_commands() { :; }
fi

cd ${SCRIPT_DIR}


### Set missing user variables ###
TITLE "Set CLI/User inputs if missing (Default is 'NO' for any unset variable)"

export GET_OCP_INSTALLER=${GET_OCP_INSTALLER:-NO}
# export OCP_VERSION=${OCP_VERSION}
export GET_OCPUP_TOOL=${GET_OCPUP_TOOL:-NO}
# export BUILD_OPERATOR=${BUILD_OPERATOR:-NO} # [DEPRECATED]
export BUILD_GO_TESTS=${BUILD_GO_TESTS:-NO}
export INSTALL_ACM=${INSTALL_ACM:-NO}
export INSTALL_MCE=${INSTALL_MCE:-NO}
export INSTALL_SUBMARINER=${INSTALL_SUBMARINER:-NO}
export INSTALL_WITH_SUBCTL=${INSTALL_WITH_SUBCTL:-NO}
export REGISTRY_IMAGES=${REGISTRY_IMAGES:-NO}
export DESTROY_CLUSTER_A=${DESTROY_CLUSTER_A:-NO}
export CREATE_CLUSTER_A=${CREATE_CLUSTER_A:-NO}
export RESET_CLUSTER_A=${RESET_CLUSTER_A:-NO}
export CLEAN_CLUSTER_A=${CLEAN_CLUSTER_A:-NO}
export DESTROY_CLUSTER_B=${DESTROY_CLUSTER_B:-NO}
export CREATE_CLUSTER_B=${CREATE_CLUSTER_B:-NO}
export RESET_CLUSTER_B=${RESET_CLUSTER_B:-NO}
export CLEAN_CLUSTER_B=${CLEAN_CLUSTER_B:-NO}
export DESTROY_CLUSTER_C=${DESTROY_CLUSTER_C:-NO}
export CREATE_CLUSTER_C=${CREATE_CLUSTER_C:-NO}
export RESET_CLUSTER_C=${RESET_CLUSTER_C:-NO}
export CLEAN_CLUSTER_C=${CLEAN_CLUSTER_C:-NO}
export GLOBALNET=${GLOBALNET:-NO}
# export SUBM_CABLE_DRIVER=${SUBM_CABLE_DRIVER:-LIBRESWAN} [DEPRECATED]
export CONFIG_GOLANG=${CONFIG_GOLANG:-NO}
export CONFIG_AWS_CLI=${CONFIG_AWS_CLI:-NO}
export SKIP_OCP_SETUP=${SKIP_OCP_SETUP:-NO}
export SKIP_TESTS=${SKIP_TESTS:-NO}
export PRINT_LOGS=${PRINT_LOGS:-NO}
export CREATE_JUNIT_XML=${CREATE_JUNIT_XML:-NO}
export UPLOAD_TO_POLARION=${UPLOAD_TO_POLARION:-NO}
export SCRIPT_DEBUG_MODE=${SCRIPT_DEBUG_MODE:-NO}

# Exporting active clusters KUBECONFIGs
export_active_clusters_kubeconfig

# Set $SUBM_VER_TAG and $ACM_VER_TAG variables with the correct version (vX.Y.Z), branch name, or tag
set_versions_variables

# Printing output both to stdout and to $SYS_LOG with tee
echo -e "\n# TODO: consider adding timestamps with: ts '%H:%M:%.S' -s"
(

  ### Script debug calls (should be left as a comment) ###

    # ${junit_cmd} debug_test_polarion
    # ${junit_cmd} debug_test_pass "junit" "junit"
    # ${junit_cmd} debug_test_fail "path/with  double  spaces  /  and even back\\slashes"
    # rc=$?
    # BUG "debug_test_fail - Exit code: $rc" \
    # "If RC $rc = 5 - junit_cmd should continue execution"
    # ${junit_cmd} debug_test_pass 100 200 300
    # ${junit_cmd} debug_test_fatal

  ### END Script debug ###

  # Setup and verify environment
  setup_workspace

  # Set script trap functions
  set_trap_functions

  # Print planned steps according to CLI/User inputs
  ${junit_cmd} show_test_plan

  ### OCP Clusters Setups and preparations (if not requested to --skip-ocp-setup) ###

  if [[ ! "$SKIP_OCP_SETUP" =~ ^(y|yes)$ ]]; then

    ### Destroy / Create OCP Clusters ###

    # Running download_ocp_installer for cluster A

    if [[ "$GET_OCP_INSTALLER" =~ ^(y|yes)$ ]] && [[ "$ocp_installer_required" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} download_ocp_installer ${OCP_VERSION}

    fi

    ### Cluster A Setup (mandatory cluster)

    # Running destroy or create or both (reset) for cluster A
    if [[ "$RESET_CLUSTER_A" =~ ^(y|yes)$ ]] || [[ "$DESTROY_CLUSTER_A" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} destroy_ocp_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_NAME"

    fi

    if [[ "$RESET_CLUSTER_A" =~ ^(y|yes)$ ]] || [[ "$CREATE_CLUSTER_A" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} prepare_install_ocp_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_YAML" "$CLUSTER_A_NAME"

      ${junit_cmd} create_ocp_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_NAME"

    fi

    ### Cluster B Setup (if it is expected to be an active cluster) ###

    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      # Running build_ocpup_tool_latest if requested, for cluster B

      if [[ "$GET_OCPUP_TOOL" =~ ^(y|yes)$ ]] && [[ "$ocpup_tool_required" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} build_ocpup_tool_latest

      fi

      # Running destroy or create or both (reset) for cluster B

      if [[ "$RESET_CLUSTER_B" =~ ^(y|yes)$ ]] || [[ "$DESTROY_CLUSTER_B" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} destroy_osp_cluster "$CLUSTER_B_DIR" "$CLUSTER_B_NAME"

      fi

      if [[ "$RESET_CLUSTER_B" =~ ^(y|yes)$ ]] || [[ "$CREATE_CLUSTER_B" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} prepare_install_osp_cluster "$CLUSTER_B_YAML" "$CLUSTER_B_NAME"

        ${junit_cmd} create_osp_cluster "$CLUSTER_B_NAME"

      fi

    fi

    ### Cluster C Setup (if it is expected to be an active cluster) ###

    if [[ -s "$CLUSTER_C_YAML" ]] ; then

      # Running download_ocp_installer if requested, for cluster C

      if [[ "$GET_OCP_INSTALLER" =~ ^(y|yes)$ ]] && [[ "$ocp_installer_required" =~ ^(y|yes)$ ]] ; then

        echo -e "\n# TODO: Need to download specific OCP version for each OCP cluster (i.e. CLI flag for each cluster is required)"

        # ${junit_cmd} download_ocp_installer ${OCP_VERSION}

      fi

      # Running destroy or create or both (reset) for cluster C

      if [[ "$RESET_CLUSTER_C" =~ ^(y|yes)$ ]] || [[ "$DESTROY_CLUSTER_C" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} destroy_ocp_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_NAME"

      fi

      if [[ "$RESET_CLUSTER_C" =~ ^(y|yes)$ ]] || [[ "$CREATE_CLUSTER_C" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} prepare_install_ocp_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_YAML" "$CLUSTER_C_NAME"

        ${junit_cmd} create_ocp_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_NAME"

      fi

    fi

    echo 0 > $TEST_STATUS_FILE

  fi
  ### END of OCP Setup (Create or Destroy) ###


  ### OCP general preparations for ALL tests ###
  # Skipping if using "--skip-tests all", to run clusters create/destroy, without further tests ###

  if [[ ! "$SKIP_TESTS" =~ ((all)(,|$))+ ]]; then

    # Before starting tests, set the test exit status to 1 (instead of 0)
    echo 1 > $TEST_STATUS_FILE

  ### Verify clusters status after OCP reset/create, and add elevated user and context ###

    ${junit_cmd} update_kubeconfig_default_context "${KUBECONF_HUB}" "${CLUSTER_A_NAME}"

    ${junit_cmd} test_cluster_status "${KUBECONF_HUB}" "${CLUSTER_A_NAME}"

    # Verify cluster B (if it is expected to be an active cluster)
    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      ${junit_cmd} update_kubeconfig_default_context "${KUBECONF_CLUSTER_B}" "${CLUSTER_B_NAME}"

      ${junit_cmd} test_cluster_status "${KUBECONF_CLUSTER_B}" "${CLUSTER_B_NAME}"

    fi

    # Verify cluster C (if it is expected to be an active cluster)
    if [[ -s "$CLUSTER_C_YAML" ]] ; then

      ${junit_cmd} update_kubeconfig_default_context "${KUBECONF_CLUSTER_C}" "${CLUSTER_C_NAME}"

      ${junit_cmd} test_cluster_status "${KUBECONF_CLUSTER_C}" "${CLUSTER_C_NAME}"

    fi

    ### Download subctl binary, even if not using subctl deploy and join (e.g. to uninstall Submariner) ###

    if [[ "$INSTALL_SUBMARINER" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} download_and_install_subctl "$SUBM_VER_TAG"

      ${junit_cmd} test_subctl_command

    fi

    ### Clusters Cleanup (of ACM and Submariner resources) - Only for existing clusters ###

    # Running cleanup on cluster A if requested
    if [[ "$CLEAN_CLUSTER_A" =~ ^(y|yes)$ ]] && [[ ! "$DESTROY_CLUSTER_A" =~ ^(y|yes)$ ]] ; then

      # ${junit_cmd} clean_acm_namespace_and_resources  # Skipping ACM cleanup, as it might not be required for Submariner tests
      ${junit_cmd} remove_multicluster_engine # Required only for the Hub cluster

      ${junit_cmd} remove_acm_managed_cluster "${KUBECONF_HUB}"

      ${junit_cmd} uninstall_submariner "${KUBECONF_HUB}"

      ${junit_cmd} delete_old_submariner_images_from_cluster "${KUBECONF_HUB}"

    fi
    # END of cluster A cleanup

    # Running cleanup on cluster B if requested
    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      if [[ "$CLEAN_CLUSTER_B" =~ ^(y|yes)$ ]] && [[ ! "$DESTROY_CLUSTER_B" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} remove_acm_managed_cluster "${KUBECONF_CLUSTER_B}"

        ${junit_cmd} uninstall_submariner "${KUBECONF_CLUSTER_B}"

        ${junit_cmd} delete_old_submariner_images_from_cluster "${KUBECONF_CLUSTER_B}"

      fi
    fi
    # END of cluster B cleanup

    # Running cleanup on cluster C if requested
    if [[ -s "$CLUSTER_C_YAML" ]] ; then

      if [[ "$CLEAN_CLUSTER_C" =~ ^(y|yes)$ ]] && [[ ! "$DESTROY_CLUSTER_C" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} remove_acm_managed_cluster "${KUBECONF_CLUSTER_C}"

        ${junit_cmd} uninstall_submariner "${KUBECONF_CLUSTER_C}"

        ${junit_cmd} delete_old_submariner_images_from_cluster "${KUBECONF_CLUSTER_C}"

      fi
    fi
    # END of cluster C cleanup


    ### Clusters configurations (firewall ports, gateway labels, and images prune on all clusters) ###

    echo -e "\n# TODO: If installing without ADDON (when adding clusters with subctl join) -
    \n\# Then for AWS/GCP run subctl cloud prepare, and for OSP use terraform script"
    # https://submariner.io/operations/deployment/subctl/#cloud-prepare

    # Cluster A configurations

    ${junit_cmd} add_elevated_user_to_cluster_a

    ${junit_cmd} configure_images_prune_cluster_a

    # Cluster B custom configurations for OpenStack
    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      echo -e "\n# TODO: Run only if it's an openstack (on-prem) cluster"

      # ${junit_cmd} open_firewall_ports_on_cluster_a

      # ${junit_cmd} label_gateway_on_broker_nodes_with_external_ip

      # Since ACM 2.5 Openstack cloud prepare is supported
      if ! check_version_greater_or_equal "$ACM_VER_TAG" "2.5" ; then

        ${junit_cmd} open_firewall_ports_on_openstack_cluster_b

        ${junit_cmd} label_first_gateway_cluster_b

      fi

      ${junit_cmd} add_elevated_user_to_cluster_b

      ${junit_cmd} configure_images_prune_cluster_b

    fi

    # Cluster C configurations
    if [[ -s "$CLUSTER_C_YAML" ]] ; then

      echo -e "\n# TODO: If installing without ADDON (when adding clusters with subctl join) -
      \n\# Then for AWS/GCP run subctl cloud prepare, and for OSP use terraform script"
      # https://submariner.io/operations/deployment/subctl/#cloud-prepare
      #
      # ${junit_cmd} open_firewall_ports_on_cluster_c
      #
      # ${junit_cmd} label_first_gateway_cluster_c

      ${junit_cmd} add_elevated_user_to_cluster_c

      ${junit_cmd} configure_images_prune_cluster_c

    fi

    ### END of all Clusters configurations


    ### Adding custom (downstream) registry mirrors, secrets and images (if using --registry-images) ###

    if [[ "$REGISTRY_IMAGES" =~ ^(y|yes)$ ]] ; then

      # ${junit_cmd} remove_submariner_images_from_local_registry_with_podman

      ${junit_cmd} configure_custom_registry_cluster_a

      ${junit_cmd} upload_submariner_images_to_cluster_registry "${KUBECONF_HUB}"

      if [[ -s "$CLUSTER_B_YAML" ]] ; then

        ${junit_cmd} configure_custom_registry_cluster_b

        ${junit_cmd} upload_submariner_images_to_cluster_registry "${KUBECONF_CLUSTER_B}"

      fi

      if [[ -s "$CLUSTER_C_YAML" ]] ; then

        ${junit_cmd} configure_custom_registry_cluster_c

        ${junit_cmd} upload_submariner_images_to_cluster_registry "${KUBECONF_CLUSTER_C}"

      fi

    fi
    ### END of configure custom clusters registry


    ### Submariner system tests prerequisites ###
    # It will be skipped if using "--skip-tests sys" (useful for deployment without system tests, or if just running pkg unit-tests)

    if [[ ! "$SKIP_TESTS" =~ ((sys)(,|$))+ ]]; then

      ### Create namespace and services for submariner system tests ###

      ${junit_cmd} configure_namespace_for_submariner_tests_on_cluster_a

      ${junit_cmd} install_netshoot_app_on_cluster_a

      if [[ -s "$CLUSTER_B_YAML" ]] ; then

        export KUBECONF_MANAGED="${KUBECONF_CLUSTER_B}"

      elif [[ -s "$CLUSTER_C_YAML" ]] ; then

        export KUBECONF_MANAGED="${KUBECONF_CLUSTER_C}"

      fi

      ${junit_cmd} configure_namespace_for_submariner_tests_on_managed_cluster

      ${junit_cmd} install_nginx_svc_on_managed_cluster

      ${junit_cmd} test_basic_cluster_connectivity_before_submariner

      ${junit_cmd} test_clusters_disconnected_before_submariner

    else  # When using "--skip-tests sys" :

      # Verify clusters status even if system tests were skipped

      ${junit_cmd} test_cluster_status "${KUBECONF_HUB}"

      [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_cluster_status "${KUBECONF_CLUSTER_B}"

      [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_cluster_status "${KUBECONF_CLUSTER_C}"

    fi
    ### END of prerequisites for Submariner system tests  ###

    TITLE "OCP clusters and environment setup is ready.
    From this point, if script fails - \$TEST_STATUS_FILE is considered FAILED ($TEST_STATUS_FILE with exit code 1)"

    echo 1 > $TEST_STATUS_FILE

  fi
  ### END of OCP general preparations for ALL tests ###


  ### Install ACM Hub, and create cluster set of the manged clusters for Submariner ###

  if [[ "$INSTALL_ACM" =~ ^(y|yes)$ ]] ; then

    # Setup ACM Hub and MCE (for ACM > 2.5 it is required to pre-install MCE, before ACM)
    if check_version_greater_or_equal "$ACM_VER_TAG" "2.5" ; then
      export INSTALL_MCE=YES
    fi

    [[ "$INSTALL_MCE" != "YES" ]] || ${junit_cmd} install_mce_operator_on_hub "$MCE_VER_TAG"

    ${junit_cmd} install_acm_operator_on_hub "$ACM_VER_TAG"

    ${junit_cmd} check_olm_in_current_cluster "${KUBECONF_HUB}"

    [[ "$INSTALL_MCE" != "YES" ]] || ${junit_cmd} create_mce_subscription "$MCE_VER_TAG"

    ${junit_cmd} create_acm_subscription "$ACM_VER_TAG"

    [[ "$INSTALL_MCE" != "YES" ]] || ${junit_cmd} create_multicluster_engine

    ${junit_cmd} create_acm_multiclusterhub


    # Setup ACM Managed Clusters

    ${junit_cmd} create_clusterset_for_submariner_in_acm_hub

    ${junit_cmd} create_and_import_managed_cluster "${KUBECONF_HUB}"

    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      ${junit_cmd} create_and_import_managed_cluster "${KUBECONF_CLUSTER_B}"

    fi

    if [[ -s "$CLUSTER_C_YAML" ]] ; then

      ${junit_cmd} create_and_import_managed_cluster "${KUBECONF_CLUSTER_C}"

    fi
  fi
  ### END of ACM Install ###

  ### Install Submariner (if using --subctl-version) ###

  if [[ "$INSTALL_SUBMARINER" =~ ^(y|yes)$ ]] ; then

    ### Deploy Submariner on the clusters with subctl CLI tool (if using --subctl-install) ###

    if [[ "$INSTALL_WITH_SUBCTL" =~ ^(y|yes)$ ]]; then

      # Running build_operator_latest if requested  # [DEPRECATED]
      # [[ ! "$build_operator" =~ ^(y|yes)$ ]] || ${junit_cmd} build_operator_latest

      ${junit_cmd} set_join_parameters_for_cluster_a

      [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} set_join_parameters_for_cluster_b

      [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} set_join_parameters_for_cluster_c

      # Overriding Submariner images with custom images from registry
      if [[ "$REGISTRY_IMAGES" =~ ^(y|yes)$ ]]; then

        ${junit_cmd} append_custom_images_to_join_cmd_cluster_a

        [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} append_custom_images_to_join_cmd_cluster_b

        [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} append_custom_images_to_join_cmd_cluster_c

      fi

      ${junit_cmd} install_broker_via_subctl_on_cluster_a

      ${junit_cmd} test_broker_before_join

      ${junit_cmd} run_subctl_join_on_cluster_a

      [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} run_subctl_join_on_cluster_b

      [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} run_subctl_join_on_cluster_c

    else
      ### Otherwise (if NOT using --subctl-install) - Deploy Submariner on the clusters via API ###

      ${junit_cmd} install_broker_via_api_on_cluster "${KUBECONF_HUB}"

      ${junit_cmd} install_submariner_operator_on_cluster "${KUBECONF_HUB}"

      ${junit_cmd} configure_submariner_addon_for_acm_managed_cluster "${KUBECONF_HUB}"

      if [[ -s "$CLUSTER_B_YAML" ]] ; then

        ${junit_cmd} install_submariner_operator_on_cluster "${KUBECONF_CLUSTER_B}"

        ${junit_cmd} configure_submariner_addon_for_acm_managed_cluster "${KUBECONF_CLUSTER_B}"

      fi

      if [[ -s "$CLUSTER_C_YAML" ]] ; then

        ${junit_cmd} install_submariner_operator_on_cluster "${KUBECONF_CLUSTER_C}"

        ${junit_cmd} configure_submariner_addon_for_acm_managed_cluster "${KUBECONF_CLUSTER_C}"

      fi

    fi
    ### END of INSTALL_WITH_SUBCTL ###

    TITLE "Once Submariner install is completed - \$TEST_STATUS_FILE is considered UNSTABLE.
    Tests will be reported to Polarion ($TEST_STATUS_FILE with exit code 2)"

    echo 2 > $TEST_STATUS_FILE

  fi
  ### END of INSTALL_SUBMARINER ###


  ### Running High-level / E2E / Unit Tests (if not requested to --skip-tests sys / all) ###

  if [[ ! "$SKIP_TESTS" =~ ((sys|all)(,|$))+ ]]; then

    ### Running High-level (System) tests of Submariner ###

    # Testing the Submariner gateway disaster recovery just on the Broker cluster (using $KUBECONF_HUB)

    ${junit_cmd} test_public_ip_on_gateway_node

    ${junit_cmd} test_disaster_recovery_of_gateway_nodes

    ${junit_cmd} test_renewal_of_gateway_and_public_ip

    ${junit_cmd} test_submariner_resources_cluster_a

    # Testing Submariner resources on all clusters

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_submariner_resources_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_submariner_resources_cluster_c

    # Testing Submariner cable-driver on all clusters

    ${junit_cmd} test_cable_driver_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_cable_driver_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_cable_driver_cluster_c

    # Testing Submariner HA (High Availability) status on all clusters

    ${junit_cmd} test_ha_status_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_ha_status_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_ha_status_cluster_c

    # Testing Submariner connectivity status on all clusters

    ${junit_cmd} test_submariner_connection_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_submariner_connection_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_submariner_connection_cluster_c

    # Testing SubCtl (Submariner CLI tool) info on all clusters

    ${junit_cmd} test_subctl_show_on_merged_kubeconfigs

    # Testing IPSec status on all clusters

    ${junit_cmd} test_ipsec_status_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_ipsec_status_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_ipsec_status_cluster_c

    # Testing GlobalNet connectivity (if enabled) on all clusters

    if [[ "$GLOBALNET" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} test_globalnet_status_cluster_a

      [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_globalnet_status_cluster_b

      [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_globalnet_status_cluster_c
    fi

    # Test service-discovery (lighthouse) on all clusters

    ${junit_cmd} test_lighthouse_status_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_lighthouse_status_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_lighthouse_status_cluster_c

    ### Running connectivity tests between the clusters ###
    # (Validating that now Submariner made the connection possible)

    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      export KUBECONF_MANAGED="${KUBECONF_CLUSTER_B}"

    elif [[ -s "$CLUSTER_C_YAML" ]] ; then

      export KUBECONF_MANAGED="${KUBECONF_CLUSTER_C}"

    fi

    ${junit_cmd} test_clusters_connected_by_service_ip

    ${junit_cmd} install_new_netshoot_cluster_a

    ${junit_cmd} install_nginx_headless_namespace_managed_cluster

    # Since Submariner 0.12, globalnet (v2) supports headless services, but not pod to pod connectivity
    if check_version_greater_or_equal "$SUBM_VER_TAG" "0.12" ; then
      export GN_VER=V2
    else
      export GN_VER=V1
    fi

    if [[ "$GLOBALNET" =~ ^(y|yes)$ ]] && [[ "$GN_VER" = "V1" ]] ; then

      ${junit_cmd} test_new_netshoot_ip_cluster_a_globalnet_v1

      ${junit_cmd} test_nginx_headless_ip_globalnet_v1

    else
      echo -e "\n# TODO: Need new system tests for GlobalNet V2 (Pod to Pod connectivity is not supported since Submariner 0.12)"
    fi

    # Test the default (pre-installed) netshoot and nginx with service-discovery

    ${junit_cmd} export_nginx_default_namespace_managed_cluster

    ${junit_cmd} test_clusters_connected_full_domain_name

    ${junit_cmd} test_clusters_cannot_connect_short_service_name

    # Test the new netshoot and headless Nginx service-discovery
    if [[ "$GLOBALNET" =~ ^(y|yes)$ ]] && [[ "$GN_VER" = "V1" ]] ; then

      # In Submariner < 0.12, globalnet (v1) supports pod to pod connectivity
      ${junit_cmd} test_clusters_connected_overlapping_cidrs_globalnet_v1

    else

      ${junit_cmd} export_nginx_headless_namespace_managed_cluster

      ${junit_cmd} test_clusters_connected_headless_service_on_new_namespace

      ${junit_cmd} test_clusters_cannot_connect_headless_short_service_name
    fi


    ### Running diagnose and benchmark tests with subctl

    ${junit_cmd} test_subctl_diagnose_on_merged_kubeconfigs

    ${junit_cmd} test_subctl_benchmarks

    TITLE "Once System tests are completed - \$TEST_STATUS_FILE is considered UNSTABLE.
    Tests will be reported to Polarion ($TEST_STATUS_FILE with exit code 2)"

    echo 2 > $TEST_STATUS_FILE

  fi # END of all System tests


  ### Running Submariner tests with Ginkgo or with subctl commands

  if [[ ! "$SKIP_TESTS" =~ all ]]; then

    ### Compiling Submariner projects in order to run Ginkgo tests with GO

    if [[ "$BUILD_GO_TESTS" =~ ^(y|yes)$ ]] ; then
      verify_golang || FATAL "No Golang compiler found. Try to run again with option '--config-golang'"

      ${junit_cmd} build_submariner_repos "$SUBM_VER_TAG"
    fi

    ### Running Unit-tests in Submariner project with Ginkgo

    if [[ ! "$SKIP_TESTS" =~ pkg ]] && [[ "$BUILD_GO_TESTS" =~ ^(y|yes)$ ]]; then
      ${junit_cmd} test_submariner_packages

      if tail -n 5 "$E2E_LOG" | grep 'FAIL' ; then
        ginkgo_tests_status=FAILED
        BUG "Submariner Unit-Tests FAILED"
      else
        echo "### Submariner Unit-Tests PASSED ###"
      fi

    fi

    if [[ ! "$SKIP_TESTS" =~ e2e ]]; then

      if [[ "$BUILD_GO_TESTS" =~ ^(y|yes)$ ]] ; then

      ### Running E2E tests in Submariner and Lighthouse projects with Ginkgo

        ${junit_cmd} test_submariner_e2e_with_go

        if tail -n 5 "$E2E_LOG" | grep 'FAIL' ; then
          ginkgo_tests_status=FAILED
          BUG "Submariner End-to-End Ginkgo tests FAILED"
        else
          echo "### Submariner End-to-End Ginkgo tests PASSED ###"
        fi

        ${junit_cmd} test_lighthouse_e2e_with_go

        if tail -n 5 "$E2E_LOG" | grep 'FAIL' ; then
          ginkgo_tests_status=FAILED
          BUG "Lighthouse End-to-End Ginkgo tests FAILED"
        else
          echo "### Lighthouse End-to-End Ginkgo tests PASSED ###"
        fi

      else

      ### Running E2E tests with subctl

        ${junit_cmd} test_submariner_e2e_with_subctl

        if tail -n 5 "$E2E_LOG" | grep 'FAIL' ; then
          ginkgo_tests_status=FAILED
          BUG "SubCtl End-to-End tests FAILED"
        else
          echo "### SubCtl End-to-End tests PASSED ###"
        fi
      fi

      if [[ "$ginkgo_tests_status" = FAILED ]] ; then
        FATAL "Submariner E2E or Unit-Tests have ended with failures, please investigate."
      fi

    fi
  fi


  # If script got to here - all tests of Submariner has passed ;-)
  echo 0 > $TEST_STATUS_FILE

) |& tee -a "$SYS_LOG"


#######################################################################################################
#   End (or exit) of Main - Now publishing to Polarion, Creating HTML report, and archive artifacts   #
#######################################################################################################

# Printing output both to stdout and to $SYS_LOG with tee
(
  set +e # To reach script end, even on error, to create report and save artifacts

  trap '' DEBUG # DONT trap_to_debug_commands

  cd ${SCRIPT_DIR}

  # ------------------------------------------

  # Get test exit status (from file $TEST_STATUS_FILE)
  EXIT_STATUS="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat $TEST_STATUS_FILE)"
  echo -e "\n# Publishing to Polarion should be run only If $TEST_STATUS_FILE does not include empty: [${EXIT_STATUS}] \n"

  ### Upload Junit xmls to Polarion - only if requested by user CLI, and $EXIT_STATUS is set ###
  if [[ -n "$EXIT_STATUS" ]] && [[ "$UPLOAD_TO_POLARION" =~ ^(y|yes)$ ]] ; then
      create_all_test_results_in_polarion || :
  fi

  # ------------------------------------------

  ### Creating HTML report from console output ###

  message="Creating HTML Report"

  # If $TEST_STATUS_FILE does not include 0 (0 = all Tests passed) or 2 (2 = some tests passed) - it means that system tests have failed (or not run at all)
  if [[ "$EXIT_STATUS" != @(0|2) ]] ; then
    message="$message - System tests failed with exit status [$EXIT_STATUS]"
    color="$RED"
  fi
  PROMPT "$message" "$color"

  TITLE "Creating HTML Report
  EXIT_STATUS = $EXIT_STATUS
  SYS_LOG = $SYS_LOG
  REPORT_NAME = $REPORT_NAME
  REPORT_FILE = $REPORT_FILE
  "

  if [[ -n "$REPORT_FILE" ]] ; then
    echo -e "\n# Remove path and replace all spaces from REPORT_FILE: '$REPORT_FILE'"
    REPORT_FILE="$(basename ${REPORT_FILE// /_})"
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
info_files="${SCRIPT_DIR}/*.info"
for info in $info_files ; do
  if [[ -s "$info" ]] ; then
    echo -e "$info :
    $(< "$info") \n\n"

    # The first line of info file with bold font
    html_report_headlines+="$(sed -r '1 s/^(.*)$/<br> <b> \1 <\/b>/' "$info")" || :
  fi
done

if [[ -s "$SUBMARINER_IMAGES" ]] ; then
  headline="Submariner images:"
  echo -e "\n# ${headline}"
  cat "$SUBMARINER_IMAGES"

  html_report_headlines+="
  <br> <b>${headline}</b>
  $(< "$SUBMARINER_IMAGES")"
fi


### Create REPORT_FILE (html) from $SYS_LOG using log_to_html()
{
  log_to_html "$SYS_LOG" "$REPORT_NAME" "$REPORT_FILE" "$html_report_headlines"

  # If REPORT_FILE was not passed externally, set it as the latest html file that was created
  REPORT_FILE="${REPORT_FILE:-$(ls -1 -tc *.html | head -1)}"

} || :

# ------------------------------------------

### Collecting artifacts and compressing to tar.gz archive ###

if [[ -n "${REPORT_FILE}" ]] ; then
   ARCHIVE_FILE="${REPORT_FILE%.*}_${DATE_TIME}.tar.gz"
else
   ARCHIVE_FILE="${PWD##*/}_${DATE_TIME}.tar.gz"
fi

TITLE "Compressing Report, Log, Kubeconfigs and other test artifacts into: ${ARCHIVE_FILE}"

# Artifact OCP clusters kubeconfigs and logs
if [[ -s "${CLUSTER_A_YAML}" ]] ; then
  echo -e "\n# Saving kubeconfig and OCP installer log of Cluster A"

  cp -f "${KUBECONF_HUB}" "kubconf_${CLUSTER_A_NAME}" || :
  cp -f "${KUBECONF_HUB}.bak" "kubconf_${CLUSTER_A_NAME}.bak" || :

  find ${CLUSTER_A_DIR} -type f -name "*.log" -exec \
  sh -c 'cp "{}" "cluster_a_$(basename "$(dirname "{}")")$(basename "{}")"' \; || :
fi

if [[ -s "${CLUSTER_B_YAML}" ]] ; then
  echo -e "\n# Saving kubeconfig and OCP installer log of Cluster B"

  cp -f "${KUBECONF_CLUSTER_B}" "kubconf_${CLUSTER_B_NAME}" || :
  cp -f "${KUBECONF_CLUSTER_B}.bak" "kubconf_${CLUSTER_B_NAME}.bak" || :

  find ${CLUSTER_B_DIR} -type f -name "*.log" -exec \
  sh -c 'cp "{}" "cluster_b_$(basename "$(dirname "{}")")$(basename "{}")"' \; || :
fi

if [[ -s "${CLUSTER_C_YAML}" ]] ; then
  echo -e "\n# Saving kubeconfig and OCP installer log of Cluster C"

  cp -f "${KUBECONF_CLUSTER_C}" "kubconf_${CLUSTER_C_NAME}" || :
  cp -f "${KUBECONF_CLUSTER_C}.bak" "kubconf_${CLUSTER_C_NAME}" || :

  find ${CLUSTER_C_DIR} -type f -name "*.log" -exec \
  sh -c 'cp "{}" "cluster_c_$(basename "$(dirname "{}")")$(basename "{}")"' \; || :
fi

# Artifact ${OCP_USR}.sec file
find ${WORKDIR} -maxdepth 1 -type f -name "${OCP_USR}.sec" -exec cp -f "{}" . \; || :

# Artifact broker.info file (if created with subctl deploy)
find ${WORKDIR} -maxdepth 1 -type f -name "$BROKER_INFO" -exec cp -f "{}" "submariner_{}" \; || :

# Artifact "submariner" directory (if created with subctl gather)
find ${WORKDIR} -maxdepth 1 -type d -name "submariner*" -exec cp -R "{}" . \; || :

# Compress the required artifacts (either files or directories)

find . -maxdepth 1 \( \
-name "$REPORT_FILE" -o \
-name "$SYS_LOG" -o \
-name "kubconf_*" -o \
-name "submariner*" -o \
-name "*.sec" -o \
-name "*.xml" -o \
-name "*.yaml" -o \
-name "*.log" -o \
-name "*.ver" \
\) -print0 | \
tar --dereference --hard-dereference -cvzf $ARCHIVE_FILE --null -T - || :


TITLE "Archive \"$ARCHIVE_FILE\" now contains:"
tar tvf $ARCHIVE_FILE

TITLE "To view in your Browser, run:\n tar -xvf ${ARCHIVE_FILE}; firefox ${REPORT_FILE}"

# Get test exit status (from file $TEST_STATUS_FILE)
EXIT_STATUS="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat $TEST_STATUS_FILE)"

TITLE "Exiting script with \$TEST_STATUS_FILE return code: [$EXIT_STATUS]"

if [[ -z "$EXIT_STATUS" ]] ; then
  exit 3
else
  exit $EXIT_STATUS
fi


# ------------------------------------------
