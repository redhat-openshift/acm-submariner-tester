#!/bin/bash
#######################################################################################################
#                                                                                                     #
# Setup Submariner on AWS and OSP (Upshift)                                                           #
# By Noam Manos, nmanos@redhat.com                                                                    #
#                                                                                                     #
# You can find latest script here:                                                                    #
# https://github.com/redhat-openshift/acm-submariner-tester                                           #
#                                                                                                     #
# It is assumed that you have existing Openshift configuration files (install-config.yaml)            #
# for both cluster A (AWS) and cluster B (OSP), in the current directory.                             #
#                                                                                                     #
# For cluster A, use Openshift-installer config format:                                               #
# https://github.com/openshift/installer/blob/master/docs/user/aws/customization.md#examples          #
#                                                                                                     #
# For cluster B, use OCPUP config format:                                                             #
# https://github.com/dimaunx/ocpup#create-config-file                                                 #
#                                                                                                     #
# To create those config files, you need to supply your AWS pull secret, and SSH public key:          #
#                                                                                                     #
# (1) Get access to Upshift account.                                                                  #
# - Follow PnT Resource Workflow:                                                                     #
# https://docs.engineering.redhat.com/display/HSSP/PnT+Resource+Request+Workflow+including+PSI        #
# - PSI Resource (Openstack, Upshift) request form:                                                   #
# https://docs.google.com/forms/d/e/1FAIpQLScxbNCO1fNFeIeFUghlCSr9uqVZncYwYmgSR2CLNIQv5AUTaw/viewform #
# - OpenShift on OpenStack (using PSI) Mojo page:                                                     #
# https://mojo.redhat.com/docs/DOC-1207953                                                            #
# - Make sure your user is included in the Rover group with the same OSP project name:                #
# https://rover.redhat.com/groups/group/{your-rover-group-name}                                       #
# - Login to Openstack Admin with your kerberos credentials (and your company domain.com):            #
# https://rhos-d.infra.prod.upshift.rdu2.redhat.com/dashboard/project/                                #
# - Support email: psi-openstack-users@redhat.com                                                     #
# - Support IRC: #psi , #ops-escalation                                                               #
# - Support Google-Chat: exd-infra-escalation                                                         #
#                                                                                                     #
# (2) Get access to AWS account.                                                                      #
# - To get it, please fill AWS request form:                                                          #
# https://docs.google.com/forms/d/e/1FAIpQLSeBi_walgnC4555JEHk5rw-muFUiOf2VCWa1yuEgSl0vDeyQw/viewform #
# - Once you get approved, login to AWS openshift-dev account via the web console:                    #
# https://{AWS Account ID}.signin.aws.amazon.com/console                                              #
#                                                                                                     #
# (3) Your Red Hat Openshift pull secret, found in:                                                   #
# https://cloud.redhat.com/openshift/install/aws/installer-provisioned                                #
# It is used by Openshift-installer to download OCP images from Red Hat repositories.                 #
#                                                                                                     #
# (4) Your SSH Public Key, that you generated with " ssh-keygen -b 4096 "                             #
# cat ~/.ssh/id_rsa.pub                                                                               #
# It is required by Openshift-installer for authentication.                                           #
#                                                                                                     #
#                                                                                                     #
#######################################################################################################

# Script description
disclosure='----------------------------------------------------------------------

Interactive script to create Openshift multi-clusters on private and public clouds, and test inter-connectivity with Submariner.

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

`./setup_subm.sh --clean-cluster-a --clean-cluster-b --acm-version 2.4.0 --subctl-version 0.11.0 --registry-images --globalnet`

  * Reuse (clean) existing clusters
  * Install ACM 2.4.0 release
  * Install Submariner 0.11.0 release
  * Override Submariner images from a custom repository (configured in REGISTRY variables)
  * Configure GlobalNet (for overlapping clusters CIDRs)
  * Run Submariner E2E tests (with subctl)


`./setup_subm.sh --get-ocp-installer 4.5.1 --reset-cluster-a --clean-cluster-b --subctl-version subctl-devel --build-tests --junit`

  * Download OCP installer version 4.5.1
  * Recreate new cluster on OCP (cluster A)
  * Clean existing cluster on OSP (cluster B)
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

### Import General Helpers Function ###
source "$SCRIPT_DIR/helper_functions"

### Import ACM Functions ###
source "$SCRIPT_DIR/acm/debug.sh"
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

# File to store test status. Resetting to empty - before running tests (i.e. don't publish to Polarion yet)
export TEST_STATUS_FILE="$SCRIPT_DIR/test_status.rc"
: > $TEST_STATUS_FILE

# File to store SubCtl version
export SUBCTL_VERSION_FILE="$SCRIPT_DIR/subctl.ver"
: > $SUBCTL_VERSION_FILE

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
  [[ -n "$1" ]] || ( echo "# Missing arguments. Please see Help with: -h" && exit 1 )
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  export got_user_input=TRUE
  # Consume next (1st) argument
  case $1 in
  -h|--help)
    echo "# ${disclosure}" && exit 0
    shift ;;
  -d|--debug)
    script_debug_mode=YES
    shift ;;
  --get-ocp-installer)
    check_cli_args "$2"
    export OCP_VERSION="$2" # E.g as in https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
    get_ocp_installer=YES
    shift 2 ;;
  --get-ocpup-tool)
    get_ocpup_tool=YES
    shift ;;
  --acm-version)
    check_cli_args "$2"
    export ACM_VER_TAG="$2"
    install_acm=YES
    shift 2 ;;
  --subctl-version)
    check_cli_args "$2"
    export SUBM_VER_TAG="$2"
    download_subctl=YES
    shift 2 ;;
  --registry-images)
    registry_images=YES
    shift ;;
  --build-tests)
    build_go_tests=YES
    shift ;;
  --destroy-cluster-a)
    ocp_installer_required=YES
    destroy_cluster_a=YES
    shift ;;
  --create-cluster-a)
    ocp_installer_required=YES
    create_cluster_a=YES
    shift ;;
  --reset-cluster-a)
    ocp_installer_required=YES
    reset_cluster_a=YES
    shift ;;
  --clean-cluster-a)
    clean_cluster_a=YES
    shift ;;
  --destroy-cluster-b)
    ocpup_tool_required=YES
    destroy_cluster_b=YES
    shift ;;
  --create-cluster-b)
    ocpup_tool_required=YES
    create_cluster_b=YES
    shift ;;
  --reset-cluster-b)
    ocpup_tool_required=YES
    reset_cluster_b=YES
    shift ;;
  --clean-cluster-b)
    clean_cluster_b=YES
    shift ;;
  --destroy-cluster-c)
    ocp_installer_required=YES
    destroy_cluster_c=YES
    shift ;;
  --create-cluster-c)
    ocp_installer_required=YES
    create_cluster_c=YES
    shift ;;
  --reset-cluster-c)
    ocp_installer_required=YES
    reset_cluster_c=YES
    shift ;;
  --clean-cluster-c)
    clean_cluster_c=YES
    shift ;;
  --subctl-install)
    install_with_subctl=YES
    shift ;;
  --globalnet)
    globalnet=YES
    shift ;;
  --cable-driver)
    check_cli_args "$2"
    subm_cable_driver="$2" # libreswan / strongswan [Deprecated]
    shift 2 ;;
  --skip-ocp-setup)
    skip_ocp_setup=YES
    shift ;;
  --skip-tests)
    check_cli_args "$2"
    skip_tests="$2" # sys,e2e,pkg,all
    shift 2 ;;
  --print-logs)
    print_logs=YES
    shift ;;
  --config-golang)
    config_golang=YES
    shift ;;
  --config-aws-cli)
    config_aws_cli=YES
    shift ;;
  --junit)
    create_junit_xml=YES
    export junit_cmd="record_junit $SHELL_JUNIT_XML"
    shift ;;
  --polarion)
    upload_to_polarion=YES
    shift ;;
  --import-vars)
    check_cli_args "$2"
    export GLOBAL_VARS="$2"
    TITLE "Importing additional variables from file: $GLOBAL_VARS"
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
  echo "# ${disclosure}"

  # User input: $skip_ocp_setup - to skip OCP clusters setup (destroy / create / clean)
  while [[ ! "$skip_ocp_setup" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to run without setting-up (destroy / create / clean) OCP clusters ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    skip_ocp_setup=${input:-NO}
  done

  if [[ ! "$skip_ocp_setup" =~ ^(yes|y)$ ]]; then

    # User input: $get_ocp_installer - to download_ocp_installer
    while [[ ! "$get_ocp_installer" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to download OCP Installer ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      get_ocp_installer=${input:-no}
    done

    # User input: $OCP_VERSION - to download_ocp_installer with specific version
    if [[ "$get_ocp_installer" =~ ^(yes|y)$ ]]; then
      while [[ ! "$OCP_VERSION" =~ ^[0-9a-Z]+$ ]]; do
        echo -e "\n${YELLOW}Which OCP Installer version do you want to download ? ${NO_COLOR}
        Enter version number, or nothing to install latest version: "
        read -r input
        OCP_VERSION=${input:-latest}
      done
    fi

    # User input: $get_ocpup_tool - to build_ocpup_tool_latest
    while [[ ! "$get_ocpup_tool" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to download OCPUP tool ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      get_ocpup_tool=${input:-no}
    done

    # User input: $reset_cluster_a - to destroy_ocp_cluster AND create_ocp_cluster
    while [[ ! "$reset_cluster_a" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to destroy & create OpenShift cluster A ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      reset_cluster_a=${input:-no}
    done

    # User input: $clean_cluster_a - to clean cluster A
    if [[ "$reset_cluster_a" =~ ^(no|n)$ ]]; then
      while [[ ! "$clean_cluster_a" =~ ^(yes|no)$ ]]; do
        echo -e "\n${YELLOW}Do you want to clean OpenShift cluster A ? ${NO_COLOR}
        Enter \"yes\", or nothing to skip: "
        read -r input
        clean_cluster_a=${input:-no}
      done
    fi

    # User input: $reset_cluster_b - to destroy_osp_cluster AND create_osp_cluster
    while [[ ! "$reset_cluster_b" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to destroy & create OSP cluster B ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      reset_cluster_b=${input:-no}
    done

    # User input: $clean_cluster_b - to clean cluster B
    if [[ "$reset_cluster_b" =~ ^(no|n)$ ]]; then
      while [[ ! "$clean_cluster_b" =~ ^(yes|no)$ ]]; do
        echo -e "\n${YELLOW}Do you want to clean OSP cluster B ? ${NO_COLOR}
        Enter \"yes\", or nothing to skip: "
        read -r input
        clean_cluster_b=${input:-no}
      done
    fi

    # User input: $reset_cluster_c - to destroy_ocp_cluster AND create_cluster_c
    while [[ ! "$reset_cluster_c" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to destroy & create OCP cluster C ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      reset_cluster_c=${input:-no}
    done

    # User input: $clean_cluster_c - to clean cluster C
    if [[ "$reset_cluster_c" =~ ^(no|n)$ ]]; then
      while [[ ! "$clean_cluster_c" =~ ^(yes|no)$ ]]; do
        echo -e "\n${YELLOW}Do you want to clean OCP cluster C ? ${NO_COLOR}
        Enter \"yes\", or nothing to skip: "
        read -r input
        clean_cluster_c=${input:-no}
      done
    fi

  fi # End of skip_ocp_setup options

  # User input: $globalnet - to deploy with --globalnet
  while [[ ! "$globalnet" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to install Global Net ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    globalnet=${input:-no}
  done

  # User input: $build_operator - to build_operator_latest # [DEPRECATED]
  # while [[ ! "$build_operator" =~ ^(yes|no)$ ]]; do
  #   echo -e "\n${YELLOW}Do you want to pull Submariner-Operator repository (\"devel\" branch) and build subctl ? ${NO_COLOR}
  #   Enter \"yes\", or nothing to skip: "
  #   read -r input
  #   build_operator=${input:-no}
  # done

  # User input: $install_acm and ACM_VER_TAG - to install_acm_operator
  if [[ "$install_acm" =~ ^(yes|y)$ ]]; then
    while [[ ! "$ACM_VER_TAG" =~ ^[0-9a-Z]+ ]]; do
      echo -e "\n${YELLOW}Which ACM version do you want to install ? ${NO_COLOR}
      Enter version number, or nothing to install \"latest\" version: "
      read -r input
      ACM_VER_TAG=${input:-latest}
    done
  fi

  # User input: $download_subctl and SUBM_VER_TAG - to download_and_install_subctl
  if [[ "$download_subctl" =~ ^(yes|y)$ ]]; then
    while [[ ! "$SUBM_VER_TAG" =~ ^[0-9a-Z]+ ]]; do
      echo -e "\n${YELLOW}Which Submariner version (or tag) do you want to install ? ${NO_COLOR}
      Enter version number, or nothing to install \"latest\" version: "
      read -r input
      SUBM_VER_TAG=${input:-latest}
    done
  fi

  # User input: $registry_images - to configure_cluster_custom_registry
  while [[ ! "$registry_images" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to override Submariner images with those from custom registry (as configured in REGISTRY variables) ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    registry_images=${input:-no}
  done

  # User input: $build_go_tests - to build and run ginkgo tests from all submariner repos
  while [[ ! "$build_go_tests" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to run E2E and unit tests from all Submariner repositories ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    build_go_tests=${input:-YES}
  done

  # User input: $install_with_subctl - to install using SUBCTL tool
  while [[ ! "$install_with_subctl" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to install Submariner with SubCtl tool ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    install_with_subctl=${input:-NO}
  done

  # User input: $skip_tests - to skip tests: sys / e2e / pkg / all ^((sys|e2e|pkg)(,|$))+
  while [[ ! "$skip_tests" =~ ((sys|e2e|pkg|all)(,|$))+ ]]; do
    echo -e "\n${YELLOW}Do you want to run without executing Submariner Tests (System, E2E, Unit-Tests, or all) ? ${NO_COLOR}
    Enter any \"sys,e2e,pkg,all\", or nothing to skip: "
    read -r input
    skip_tests=${input:-NO}
  done

  while [[ ! "$print_logs" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to print full Submariner diagnostics (Pods logs, etc.) on failure ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    print_logs=${input:-NO}
  done

  # User input: $config_golang - to install latest golang if missing
  while [[ ! "$config_golang" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to install latest Golang on the environment ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    config_golang=${input:-NO}
  done

  # User input: $config_aws_cli - to install latest aws-cli and configure aws access
  while [[ ! "$config_aws_cli" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to install aws-cli and configure AWS access ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    config_aws_cli=${input:-NO}
  done

  # User input: $create_junit_xml - to record shell results into Junit xml output
  while [[ ! "$create_junit_xml" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to record shell results into Junit xml output ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    create_junit_xml=${input:-NO}
  done

  # User input: $upload_to_polarion - to upload junit xml results to Polarion
  while [[ ! "$upload_to_polarion" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to upload junit xml results to Polarion ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    upload_to_polarion=${input:-NO}
  done

fi


### Set missing user variable ###
TITLE "Set CLI/User inputs if missing (Default is 'NO' for any unset value)"

get_ocp_installer=${get_ocp_installer:-NO}
# OCP_VERSION=${OCP_VERSION}
get_ocpup_tool=${get_ocpup_tool:-NO}
# build_operator=${build_operator:-NO} # [DEPRECATED]
build_go_tests=${build_go_tests:-NO}
install_acm=${install_acm:-NO}
download_subctl=${download_subctl:-NO}
registry_images=${registry_images:-NO}
destroy_cluster_a=${destroy_cluster_a:-NO}
create_cluster_a=${create_cluster_a:-NO}
reset_cluster_a=${reset_cluster_a:-NO}
clean_cluster_a=${clean_cluster_a:-NO}
destroy_cluster_b=${destroy_cluster_b:-NO}
create_cluster_b=${create_cluster_b:-NO}
reset_cluster_b=${reset_cluster_b:-NO}
clean_cluster_b=${clean_cluster_b:-NO}
destroy_cluster_c=${destroy_cluster_c:-NO}
create_cluster_c=${create_cluster_c:-NO}
reset_cluster_c=${reset_cluster_c:-NO}
clean_cluster_c=${clean_cluster_c:-NO}
install_with_subctl=${install_with_subctl:-NO}
globalnet=${globalnet:-NO}
# subm_cable_driver=${subm_cable_driver:-libreswan} [Deprecated]
config_golang=${config_golang:-NO}
config_aws_cli=${config_aws_cli:-NO}
skip_ocp_setup=${skip_ocp_setup:-NO}
skip_tests=${skip_tests:-NO}
print_logs=${print_logs:-NO}
create_junit_xml=${create_junit_xml:-NO}
upload_to_polarion=${upload_to_polarion:-NO}
script_debug_mode=${script_debug_mode:-NO}


####################################################################################
#                             Define script functions                                #
####################################################################################

# ------------------------------------------

function show_test_plan() {
  PROMPT "Input parameters and Test Plan steps"

  if [[ "$skip_ocp_setup" =~ ^(y|yes)$ ]]; then
    echo -e "\n# Skipping OCP clusters setup (destroy / create / clean): $skip_ocp_setup \n"
  else
    echo "### Execution plan: Openshift clusters creation/cleanup before Submariner deployment:

    - download_ocp_installer: $get_ocp_installer $OCP_VERSION

    AWS cluster A (public):
    - destroy_cluster_a: $destroy_cluster_a
    - create_cluster_a: $create_cluster_a
    - reset_cluster_a: $reset_cluster_a
    - clean_cluster_a: $clean_cluster_a

    OSP cluster B (on-prem):
    - destroy_cluster_b: $destroy_cluster_b
    - create_cluster_b: $create_cluster_b
    - reset_cluster_b: $reset_cluster_b
    - clean_cluster_b: $clean_cluster_b

    AWS/GCP cluster C:
    - destroy_cluster_c: $destroy_cluster_c
    - create_cluster_c: $create_cluster_c
    - reset_cluster_c: $reset_cluster_c
    - clean_cluster_c: $clean_cluster_c
    "
  fi

  TITLE "Execution plan: Submariner deployment and environment preparations"

  echo -e "# OCP and Submariner setup and test tools:
  - config_golang: $config_golang
  - config_aws_cli: $config_aws_cli
  - build_ocpup_tool_latest: $get_ocpup_tool
  - build_operator_latest: \$build_operator # [DEPRECATED]
  - build_submariner_repos: $build_go_tests
  "

  echo -e "# Submariner deployment and environment setup for the tests:

  - update_kubeconfig_context_cluster_a
  - update_kubeconfig_context_cluster_b / c
  - test_kubeconfig_cluster_a
  - test_kubeconfig_cluster_b / c
  - add_elevated_user_to_cluster_a
  - add_elevated_user_to_cluster_b / c
  - clean_submariner_namespace_and_resources_cluster_a
  - clean_submariner_labels_and_machine_sets_cluster_a
  - delete_old_submariner_images_from_cluster_a
  - clean_submariner_namespace_and_resources_cluster_b / c
  - clean_submariner_labels_and_machine_sets_cluster_b / c
  - delete_old_submariner_images_from_cluster_b / c
  - open_firewall_ports_on_cluster_a
  - configure_images_prune_cluster_a
  - open_firewall_ports_on_openstack_cluster_b
  - label_gateway_on_broker_nodes_with_external_ip
  - open_firewall_ports_on_cluster_c
  - label_first_gateway_cluster_b / c
  - configure_images_prune_cluster_b / c
  - configure_custom_registry_cluster_a: $registry_images
  - configure_custom_registry_cluster_b / c: $registry_images
  - upload_submariner_images_to_registry_cluster_a: $registry_images
  - upload_submariner_images_to_registry_cluster_b / c: $registry_images
  - configure_namespace_for_submariner_tests_on_cluster_a
  - configure_namespace_for_submariner_tests_on_managed_cluster
  - test_kubeconfig_cluster_a
  - test_kubeconfig_cluster_b / c
  - install_netshoot_app_on_cluster_a
  - install_nginx_svc_on_managed_cluster
  - test_basic_cluster_connectivity_before_submariner
  - test_clusters_disconnected_before_submariner
  - install_acm_operator $ACM_VER_TAG
  - download_and_install_subctl $SUBM_VER_TAG
  "

  if [[ "$install_with_subctl" =~ ^(y|yes)$ ]]; then
    TITLE "Installing Submariner with SubCtl tool"

    echo -e "
    - test_subctl_command
    - set_join_parameters_for_cluster_a
    - set_join_parameters_for_cluster_b / c
    - append_custom_images_to_join_cmd_cluster_a
    - append_custom_images_to_join_cmd_cluster_b / c
    - install_broker_cluster_a
    - test_broker_before_join
    - run_subctl_join_on_cluster_a
    - run_subctl_join_on_cluster_b / c
    $([[ ! "$globalnet" =~ ^(y|yes)$ ]] || echo "- test globalnet") \
    "
  fi

  echo -e "\n# TODO: Should add function to manipulate opetshift clusters yamls, to have overlapping CIDRs"

  if [[ "$skip_tests" =~ ((sys|all)(,|$))+ ]]; then
    echo -e "\n# Skipping high-level (system) tests: $skip_tests \n"
  else
  TITLE "Execution plan: High-level (System) tests of Submariner"
  echo -e "
    - test_submariner_resources_cluster_a
    - test_submariner_resources_cluster_b / c
    - test_public_ip_on_gateway_node
    - test_disaster_recovery_of_gateway_nodes
    - test_renewal_of_gateway_and_public_ip
    - test_cable_driver_cluster_a
    - test_cable_driver_cluster_b / c
    - test_subctl_show_on_merged_kubeconfigs
    - test_ha_status_cluster_a
    - test_ha_status_cluster_b / c
    - test_submariner_connection_cluster_a
    - test_submariner_connection_cluster_b / c
    - test_globalnet_status_cluster_a: $globalnet
    - test_globalnet_status_cluster_b / c: $globalnet
    - export_nginx_default_namespace_managed_cluster
    - export_nginx_headless_namespace_managed_cluster
    - test_lighthouse_status_cluster_a
    - test_lighthouse_status_cluster_b / c
    - test_clusters_connected_by_service_ip
    - install_new_netshoot_cluster_a
    - install_nginx_headless_namespace_managed_cluster
    - test_clusters_connected_overlapping_cidrs: $globalnet
    - test_new_netshoot_global_ip_cluster_a: $globalnet
    - test_nginx_headless_global_ip_managed_cluster: $globalnet
    - test_clusters_connected_full_domain_name
    - test_clusters_cannot_connect_short_service_name
    - test_clusters_connected_headless_service_on_new_namespace
    - test_clusters_cannot_connect_headless_short_service_name
    "
  fi

  if [[ "$skip_tests" =~ ((pkg|all)(,|$))+ ]]; then
    echo -e "\n# Skipping Submariner unit-tests: $skip_tests \n"
  else
    echo -e "\n### Execution plan: Unit-tests (Ginkgo Packages) of Submariner:

    - test_submariner_packages
    "
  fi

  if [[ "$skip_tests" =~ ((e2e|all)(,|$))+ ]]; then
    echo -e "\n# Skipping Submariner E2E tests: $skip_tests \n"
  else
    echo -e "\n### Execution plan: End-to-End (Ginkgo E2E) tests of Submariner:

    - test_submariner_e2e_with_go: $([[ "$build_go_tests" =~ ^(y|yes)$ ]] && echo 'YES' || echo 'NO' )
    - test_submariner_e2e_with_subctl: $([[ ! "$build_go_tests" =~ ^(y|yes)$ ]] && echo 'YES' || echo 'NO' )
    "
  fi

  TITLE "All environment variables"
  # List all variables
  compgen -v | sort | \
  while read var_name; do
    # Get each variable value
    var_value="${!var_name}"
    # If variable is not null or contains "key" / "sec"ret / "pas"sword
    if ! [[ -z "$var_value" || "$var_name" =~ (key|sec|pas|pwd) ]] ; then
      # Trim value (string), if it is longer than 500 char
      (( ${#var_value} < 500 )) || var_value="${var_value:0:500}..."
      # Print the value without non-ascii chars
      echo -e "$var_name = $var_value" | tr -dC '[:print:]\t\n'
    fi
  done

}

# ------------------------------------------

function setup_workspace() {
  PROMPT "Configuring workspace (Golang, AWS-CLI, GCP-CLI, Terraform, Polarion) in: ${WORKDIR}"
  trap '' DEBUG # DONT trap_to_debug_commands

  # Create WORKDIR and local BIN dir (if not yet exists)
  mkdir -p ${WORKDIR}
  mkdir -p $HOME/.local/bin

  # Add local BIN dir to PATH
  [[ ":$PATH:" = *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"

  # # CD to main working directory
  # cd ${WORKDIR}

  TITLE "Installing Anaconda (virtual environment)"
  install_anaconda "${WORKDIR}"

  # Installing GoLang with Anaconda, if $config_golang = yes/y
  if [[ "$config_golang" =~ ^(y|yes)$ ]] ; then
    TITLE "Installing GoLang with Anaconda"
    install_local_golang "${WORKDIR}"

    # Set GOBIN to local directory in ${WORKDIR}
    export GOBIN="${WORKDIR}/GOBIN"
    mkdir -p "$GOBIN"

    # Verify GO installation
    verify_golang

    if [[ -e ${GOBIN} ]] ; then
      echo "# Re-exporting global variables"
      export OC="${GOBIN}/oc $VERBOSE_FLAG"
    fi
  fi

  TITLE "Installing Terraform with Anaconda"
  # # Installing Terraform
  # install_local_terraform "${WORKDIR}"
  BUG "Terraform v0.13.x is not supported when using Submariner Terraform scripts" \
  "Use Terraform v0.12.29" \
  "https://github.com/submariner-io/submariner/issues/847"
  # Workaround:
  install_local_terraform "${WORKDIR}" "0.12.29"

  TITLE "Installing JQ (JSON processor) with Anaconda"
  install_local_jq "${WORKDIR}"

  # Set Polarion access if $upload_to_polarion = yes/y
  if [[ "$upload_to_polarion" =~ ^(y|yes)$ ]] ; then
    TITLE "Set Polarion access for the user [$POLARION_USR]"
    ( # subshell to hide commands
      local polauth
      polauth=$(echo "${POLARION_USR}:${POLARION_PWD}" | base64 --wrap 0)
      echo "--header \"Authorization: Basic ${polauth}\"" > "$POLARION_AUTH"
    )
  fi

  # Trim trailing and leading spaces from $TEST_NS
  TEST_NS="$(echo "$TEST_NS" | xargs)"

  # Installing AWS-CLI if $config_aws_cli = yes/y
  if [[ "$config_aws_cli" =~ ^(y|yes)$ ]] ; then
    TITLE "Installing and configuring AWS-CLI for profile [$AWS_PROFILE_NAME] and region [$AWS_REGION]"
    ( # subshell to hide commands
    configure_aws_access \
    "${AWS_PROFILE_NAME}" "${AWS_REGION}" "${AWS_KEY}" "${AWS_SECRET}" "${WORKDIR}" "${GOBIN}"
    )

    # TODO: need to add script CLI flag for $config_gcp_cli = yes/y
    if [[ -s "$GCP_CRED_JSON" ]] ; then
      TITLE "Installing and configuring GCP-CLI"
      configure_gcp_access "${GCP_CRED_JSON}"
    fi

  fi

}

# ------------------------------------------

function set_trap_functions() {
  PROMPT "Configuring trap functions on script exit"

  TITLE "Will run env_teardown() when exiting the script"
  trap 'env_teardown' EXIT

  if [[ "$print_logs" =~ ^(y|yes)$ ]]; then
    TITLE "Will collect Submariner information on test failure (CLI option --print-logs)"
    trap_function_on_error collect_submariner_info
  fi

}

# ------------------------------------------

function download_ocp_installer() {
### Download OCP installer ###
  PROMPT "Downloading OCP Installer $1"
  trap_to_debug_commands;

  # Optional param: $OCP_VERSION
  local ocp_installer_version="${1:-latest}" # default version to download is latest formal release

  local ocp_major_version
  ocp_major_version="$(echo $ocp_installer_version | cut -s -d '.' -f 1)" # Get the major digit of OCP version

  local ocp_major_version="${ocp_major_version:-4}" # if no numerical version was requested (e.g. "latest"), the default OCP major version is 4
  local oc_version_path="ocp/${ocp_installer_version}"

  # Get the nightly (ocp-dev-preview) build, if requested by user input
  if [[ "$oc_version_path" =~ nightly ]] ; then
    oc_version_path="ocp-dev-preview/latest"
    # Also available at: https://openshift-release-artifacts.svc.ci.openshift.org/
  fi

  local oc_installer_url="https://mirror.openshift.com/pub/openshift-v${ocp_major_version}/clients/${oc_version_path}/"

  cd ${WORKDIR}

  local ocp_install_gz
  ocp_install_gz=$(curl $oc_installer_url | grep -Eoh "openshift-install-linux-.+\.tar\.gz" | cut -d '"' -f 1)

  local oc_client_gz
  oc_client_gz=$(curl $oc_installer_url | grep -Eoh "openshift-client-linux-.+\.tar\.gz" | cut -d '"' -f 1)

  [[ -n "$ocp_install_gz" && -n "$oc_client_gz" ]] || FATAL "Failed to retrieve OCP installer [${ocp_installer_version}] from $oc_installer_url"

  TITLE "Deleting previous OCP installer and client, and downloading: \n# $ocp_install_gz \n# $oc_client_gz"
  # find -type f -maxdepth 1 -name "openshift-*.tar.gz" -mtime +1 -exec rm -rf {} \;
  delete_old_files_or_dirs "openshift-*.tar.gz"

  download_file ${oc_installer_url}${ocp_install_gz}
  download_file ${oc_installer_url}${oc_client_gz}

  TITLE "Extracting OCP installer and client into ${WORKDIR}: \n $ocp_install_gz \n $oc_client_gz"

  ocp_install_gz="${ocp_install_gz%%$'\n'*}"
  oc_client_gz="${oc_client_gz%%$'\n'*}"

  tar -xvf "$ocp_install_gz" -C ${WORKDIR}
  tar -xvf "$oc_client_gz" -C ${WORKDIR}

  TITLE "Install OC (Openshift Client tool) into ${GOBIN}:"
  mkdir -p $GOBIN
  /usr/bin/install ./oc $GOBIN/oc

  echo "# Install OC into user HOME bin:"
  /usr/bin/install ./oc ~/.local/bin/oc

  echo "# Add user HOME bin to system PATH:"
  export PATH="$HOME/.local/bin:$PATH"

  ${OC} -h
}

# ------------------------------------------

function build_ocpup_tool_latest() {
### Download OCPUP tool ###
  PROMPT "Downloading latest OCP-UP tool, and installing it to $GOBIN/ocpup"
  trap_to_debug_commands;

  verify_golang || FATAL "No Golang compiler found. Try to run again with option '--config-golang'"

  echo -e "\n# TODO: Need to fix ocpup alias"

  cd ${WORKDIR}
  # rm -rf ocpup # We should not remove directory, as it may included previous install config files
  git clone https://github.com/dimaunx/ocpup || echo "# OCPUP directory already exists"
  cd ocpup

  # To cleanup GOLANG mod files:
    # go clean -cache -modcache -i -r

  git_reset_local_repo "master" "https://github.com/redhat-openshift/ocpup.git"

  echo -e "\n# Build OCPUP and install it to $GOBIN/"
  export GO111MODULE=on
  go mod vendor
  go install -mod vendor # Compile binary and moves it to $GOBIN
  # go build -mod vendor # Saves binary in current directory

  echo "# Check OCPUP command:"
  [[ -x "$(command -v ocpup)" ]] || FATAL "OCPUP tool installation error occurred."
  which ocpup

  ocpup -h
      # Create multiple OCP4 clusters and resources
      #
      # Usage:
      #   ocpup [command]
      #
      # Available Commands:
      #   create      Create resources
      #   deploy      deploy resources
      #   destroy     Destroy resources
      #   help        Help about any command
      #
      # Flags:
      #       --config string   config file location(default is ocpup.yaml in the root of the project.)
      #   -v, --debug           debug mode
      #   -h, --help            help for ocpup
      #
      # Use "ocpup [command] --help" for more information about a command.
}

# ------------------------------------------

function destroy_ocp_cluster() {
### Destroy your previous OCP cluster (public) ###
  trap_to_debug_commands;
  local ocp_install_dir="$1"
  local cluster_name="$2"

  PROMPT "Destroying previous OCP cluster: $cluster_name"
  trap_to_debug_commands;

  # Temp - CD to main working directory
  cd ${WORKDIR}

  [[ -f openshift-install ]] || FATAL "OCP Installer is missing. Try to run again with option '--get-ocp-installer [latest / x.y.z]'"

  # Only if your AWS cluster still exists (less than 48 hours passed) - run destroy command:
  echo -e "\n# TODO: should first check if it was not already purged, because it can save a lot of time."
  if [[ -d "${ocp_install_dir}" ]]; then
    TITLE "Previous OCP Installation found: ${ocp_install_dir}"
    # cd "${ocp_install_dir}"
    if [[ -f "${ocp_install_dir}/metadata.json" ]] ; then
      echo "# Destroying OCP cluster ${cluster_name}:"
      timeout 10m ./openshift-install destroy cluster --log-level debug --dir "${ocp_install_dir}" || \
      ( [[ $? -eq 124 ]] && \
        BUG "WARNING: OCP destroy timeout exceeded - loop state while destroying cluster" \
        "Force exist OCP destroy process" \
        "Please submit a new bug for OCP installer (in Bugzilla)"
      )
    fi
    # cd ..

    TITLE "Backup previous OCP install-config directory of cluster ${cluster_name}"
    parent_dir=$(dirname -- "$ocp_install_dir")
    base_dir=$(basename -- "$ocp_install_dir")
    backup_and_remove_dir "$ocp_install_dir" "${parent_dir}/_${base_dir}_${DATE_TIME}"

    # Remove existing OCP install-config directory:
    #rm -r "_${ocp_install_dir}/" || echo "# Old config dir removed."
    TITLE "Deleting all previous ${ocp_install_dir} config directories (older than 1 day):"
    # find -maxdepth 1 -type d -name "_*" -mtime +1 -exec rm -rf {} \;
    delete_old_files_or_dirs "${parent_dir}/_${base_dir}_*" "d" 1
  else
    TITLE "OCP cluster config (metadata.json) was not found in ${ocp_install_dir}. Skipping cluster Destroy."
  fi

  BUG "WARNING: OCP destroy command does not remove the previous DNS record sets from AWS Route53" \
  "Delete previous DNS record sets from AWS Route53" \
  "---"
  # Workaround:

  # set AWS DNS record sets to be deleted
  AWS_DNS_ALIAS1="api.${cluster_name}.${AWS_ZONE_NAME}."
  AWS_DNS_ALIAS2="\052.apps.${cluster_name}.${AWS_ZONE_NAME}."

  TITLE "Deleting AWS DNS record sets from Route53"
  echo -e "# $AWS_DNS_ALIAS1
  # $AWS_DNS_ALIAS2
  "

  # curl -LO https://github.com/manosnoam/shift-stack-helpers/raw/master/delete_aws_dns_alias_zones.sh
  # chmod +x delete_aws_dns_alias_zones.sh
  # ./delete_aws_dns_alias_zones.sh "${cluster_name}"
  delete_aws_dns_records "$AWS_ZONE_ID" "$AWS_DNS_ALIAS1"
  delete_aws_dns_records "$AWS_ZONE_ID" "$AWS_DNS_ALIAS2"

  # Or Manually in https://console.aws.amazon.com/route53/home#hosted-zones:
    # https://console.aws.amazon.com/route53/home#resource-record-sets
    #
    # api.user-cluster-a.devcluster.openshift.com.
    # *.apps.user-cluster-a.devcluster.openshift.com.
    #
    # DO NOT REMOVE OTHER DNSs !!!!
}

# ------------------------------------------

function destroy_osp_cluster() {
### If Required - Destroy your previous Openstack cluster B (on-prem) ###
  trap_to_debug_commands;
  local ocp_install_dir="$1"
  local cluster_name="$2"

  PROMPT "Destroying previous Openstack cluster: $cluster_name"

  cd "${OCPUP_DIR}"
  [[ -x "$(command -v ocpup)" ]] || FATAL "OCPUP tool is missing. Try to run again with option '--get-ocpup-tool'"

  if [[ -f "${ocp_install_dir}/metadata.json" ]] ; then
    TITLE "Using last created OCPUP yaml configuration file"
    local ocpup_yml
    ocpup_yml="$(ls -1 -tu *ocpup*.yaml | head -1 )" || :

    ls -l "$ocpup_yml" || FATAL "OCPUP yaml configuration file is missing."

    local ocpup_cluster_name
    ocpup_cluster_name="$(awk '/clusterName:/ {print $NF}' $ocpup_yml)"

    local ocp_cmd="ocpup destroy clusters ${DEBUG_FLAG} --config $ocpup_yml"
    local ocp_log="${OCPUP_DIR}/.config/${ocpup_cluster_name}/.openshift_install.log"

    run_and_tail "$ocp_cmd" "$ocp_log" 5m || BUG "OCP destroy cluster B did not complete as expected"

    # To tail all OpenShift Installer logs (in a new session):
      # find . -name "*openshift_install.log" | xargs tail --pid=$pid -f # tail ocpup/.config/${ocpup_cluster_name}/.openshift_install.log

    TITLE "Backup previous OCP install-config directory of cluster ${cluster_name}"
    backup_and_remove_dir ".config"
  else
    TITLE "OCP cluster config (metadata.json) was not found in ${ocp_install_dir}. Skipping cluster Destroy."
  fi
}

# ------------------------------------------

function prepare_install_ocp_cluster() {
### Prepare installation files for OCP cluster (public) ###
  trap_to_debug_commands;

  local ocp_install_dir="$1"
  local installer_yaml_source="$2"
  local cluster_name="$3"

  PROMPT "Preparing installation files for OCP cluster $cluster_name"

  cd ${WORKDIR}
  [[ -f openshift-install ]] || FATAL "OCP Installer is missing. Try to run again with option '--get-ocp-installer [latest / x.y.z]'"

  # To manually create new OCP install-config.yaml:
  # ./openshift-install create install-config --dir user-cluster-a
  #
  # $ cluster_name=user-cluster-a
  # $ mkdir ${cluster_name}
  # $ cd ${cluster_name}
  # $ ../openshift-install create install-config

    # ? SSH Public Key ~/.ssh/id_rsa.pub
    # ? Platform aws
    # ? Region us-east-1
    # ? Base Domain devcluster.openshift.com
    # ? cluster Name user-cluster-a
    # ? Pull Secret

  mkdir -p "${ocp_install_dir}"
  local installer_yaml_new="${ocp_install_dir}/install-config.yaml"

  TITLE "Using OCP install-config.yaml - make sure to have it in the workspace: ${installer_yaml_source}"
  cp -f "${installer_yaml_source}" "$installer_yaml_new"
  chmod 777 "$installer_yaml_new"

  echo "# Update OCP installer configuration (${installer_yaml_new}) of OCP cluster $cluster_name"
  [[ -z "$cluster_name" ]] || change_yaml_key_value "$installer_yaml_new" "name" "$cluster_name" "metadata"

  # Set the same region for ALL clusters (even on different clouds)
  # [[ -z "$AWS_REGION" ]] || change_yaml_key_value "$installer_yaml_new" "region" "$AWS_REGION"

  echo -e "\n# TODO: change more {keys : values} in $installer_yaml_new, from the global variables file"

}

# ------------------------------------------

function create_ocp_cluster() {
### Create OCP cluster A (public) with OCP installer ###
  trap_to_debug_commands;
  local ocp_install_dir="$1"
  local cluster_name="$2"

  PROMPT "Creating OCP cluster (public): $cluster_name"

  if [[ ! -d "$ocp_install_dir" ]] ; then
    FATAL "OCP install directory [$ocp_install_dir] does not exist"
  else
    cd ${ocp_install_dir}
  fi

  # Continue previous OCP installation
  if [[ -s "metadata.json" ]] ; then
    TITLE "$ocp_install_dir directory contains previous OCP installer files. Will attempt to continue previous installation"

    local ocp_cmd="../openshift-install wait-for install-complete --log-level=debug" # --dir="$CLUSTER_DIR"
    local ocp_log=".openshift_install.log"

    run_and_tail "$ocp_cmd" "$ocp_log" 100m "Access the OpenShift web-console" \
    || FATAL "OCP installer failed to continue previous installation for $cluster_name"

  # Start new OCP installation
  else
    TITLE "Run OCP installer from scratch using install-config.yaml"

    local ocp_cmd="../openshift-install create cluster --log-level debug"
    local ocp_log=".openshift_install.log"

    run_and_tail "$ocp_cmd" "$ocp_log" 100m "Access the OpenShift web-console" \
    || FATAL "OCP installer failed to create $cluster_name"
  fi

}

# ------------------------------------------

function prepare_install_osp_cluster() {
### Prepare installation files for OSP cluster (on-prem) ###
  trap_to_debug_commands;

  local installer_yaml_source="$1"
  local cluster_name="$2"

  PROMPT "Preparing installation files for OSP cluster $cluster_name"

  cd "${OCPUP_DIR}"
  [[ -x "$(command -v ocpup)" ]] || FATAL "OCPUP tool is missing. Try to run again with option '--get-ocpup-tool'"

#   local terraform_osp_provider="./tf/osp-sg/versions.tf"
#
#   cat <<-EOF > $terraform_osp_provider
#   terraform {
#     required_version = ">= 0.12, <= 0.12.12"
#
#     required_providers {
#       openstack = {
#         source  = "terraform-provider-openstack/openstack"
#         version = "~> 1.41"
#       }
#     }
#   }
# EOF
#
#   echo -e "# Setting terraform-provider-openstack version into $terraform_osp_provider: \n$(< $terraform_osp_provider)"

  local installer_yaml_new="${OCPUP_DIR}/ocpup.yaml"
  echo -e "# Copy $cluster_name installer configuration: ${installer_yaml_source} \n# To OCPUP directory: ${installer_yaml_new}"
  cp -f "${installer_yaml_source}" "${installer_yaml_new}" || FATAL "$cluster_name installer configuration file for OCPUP is missing."

  ls -l "$installer_yaml_new"
  chmod 777 "$installer_yaml_new"

  TITLE "Update $installer_yaml_new with OSP cloud info, before installing $cluster_name"
  ( # subshell to hide commands
    [[ -z "$OS_AUTH_URL" ]] || change_yaml_key_value "$installer_yaml_new" "authUrl" "$OS_AUTH_URL" "openstack"
    [[ -z "$OS_USERNAME" ]] || change_yaml_key_value "$installer_yaml_new" "userName" "$OS_USERNAME" "openstack"
    [[ -z "$OS_PROJECT_DOMAIN_ID" ]] || change_yaml_key_value "$installer_yaml_new" "projectId" "$OS_PROJECT_DOMAIN_ID" "openstack"
    [[ -z "$OS_PROJECT_NAME" ]] || change_yaml_key_value "$installer_yaml_new" "projectName" "$OS_PROJECT_NAME" "openstack"
    [[ -z "$OS_USER_DOMAIN_NAME" ]] || change_yaml_key_value "$installer_yaml_new" "userDomainName" "$OS_USER_DOMAIN_NAME" "openstack"
  )

}

# ------------------------------------------

function create_osp_cluster() {
### Create Openstack cluster B (on-prem) with OCPUP tool ###
  trap_to_debug_commands;

  local cluster_name="$1"

  PROMPT "Creating Openstack cluster $cluster_name (on-prem) with OCP-UP tool"

  cd ${OCPUP_DIR}

  local ocpup_yml=${cluster_name}_ocpup.yaml # $(basename -- "$installer_yaml_source")

  echo -e "# Renaming ocpup.yaml configuration file to: ${ocpup_yml}"
  mv -f ocpup.yaml ${ocpup_yml} || FATAL "ocpup.yaml configuration was not found in ${OCPUP_DIR}"

  ls -l "$ocpup_yml"

  # Due to OCPUP limitation, $ocpup_cluster_name != $CLUSTER_B_NAME
  local ocpup_cluster_name
  ocpup_cluster_name="$(awk '/clusterName:/ {print $NF}' $ocpup_yml)"
  local ocpup_project_name
  ocpup_project_name="$(awk '/projectName:/ {print $NF}' $ocpup_yml)"
  local ocpup_user_name
  ocpup_user_name="$(awk '/userName:/ {print $NF}' $ocpup_yml)"

  echo -e "# Running OCPUP to create OpenStack cluster B (on-prem):
  \n# Cluster name: $ocpup_cluster_name
  \n# OSP Project: $ocpup_project_name
  \n# OSP User: $ocpup_user_name"

  # ocpup create clusters ${DEBUG_FLAG} --config "$ocpup_yml" &
  # pid=$!
  # tail --pid=$pid -f --retry .config/${ocpup_cluster_name}/.openshift_install.log &
  # tail --pid=$pid -f /dev/null

  local ocp_cmd="ocpup create clusters ${DEBUG_FLAG} --config $ocpup_yml"
  local ocp_log=".config/${ocpup_cluster_name}/.openshift_install.log"

  run_and_tail "$ocp_cmd" "$ocp_log" 100m "Access the OpenShift web-console" \
  || FATAL "OCP create cluster B did not complete as expected"

  # To tail all OpenShift Installer logs (in a new session):
    # find . -name "*openshift_install.log" | xargs tail --pid=$pid -f # tail ocpup/.config/${ocpup_cluster_name}/.openshift_install.log

  # Login to the new created cluster:
  # $ grep "Access the OpenShift web-console" -r . --include='*.log' -A 1
    # "Access the OpenShift web-console here: https://console-openshift-console.apps..."
    # "Login to the console with user: kubeadmin, password: ..."
}

# ------------------------------------------

function export_active_clusters_kubeconfig() {
### Helper function to unset inactive clusters kubeconfig ###
  trap_to_debug_commands;

  # TODO: Need to re-factor so any cluster A/B/C have same function to export its name, dir, etc.

  local ocp_yaml_platform
  local ocp_yaml_base_dns

  TITLE "Exporting all active clusters kubeconfig (and unset inactive kubeconfigs)"

  # Setting HUB (Cluster A) config ($WORKDIR and $CLUSTER_A_NAME were set in subm_variables file)

  # Get cluster platform and base domain from OCP installer yaml, and append it to the cluster name
  ocp_yaml_platform="$(grep -Poz 'platform:\s*\K\w+' ${CLUSTER_A_YAML} | awk -F'\0' '{print $1; exit}' || :)"
  # ocp_yaml_base_dns="$(grep -Poz 'baseDomain:\s*\K\w+' ${CLUSTER_A_NAME} | awk -F'\0' '{print $1; exit}}' || :)"
  export CLUSTER_A_NAME="${CLUSTER_A_NAME}${ocp_yaml_base_dns:+-$ocp_yaml_base_dns}${ocp_yaml_platform:+-$ocp_yaml_platform}"

  echo "# Exporting \$KUBECONF_HUB for $CLUSTER_A_NAME (Cluster A is also the ACM Hub)"
  export CLUSTER_A_DIR=${WORKDIR}/${CLUSTER_A_NAME}
  export KUBECONF_HUB=${CLUSTER_A_DIR}/auth/kubeconfig

  # Setting Cluster B config ($OCPUP_DIR and $CLUSTER_B_YAML were set in subm_variables file)
  if [[ -s "$CLUSTER_B_YAML" ]] ; then
    echo "# Exporting \$KUBECONF_CLUSTER_B for $CLUSTER_B_NAME"
    CLUSTER_B_DIR=${OCPUP_DIR}/.config/$(awk '/clusterName:/ {print $NF}' "${CLUSTER_B_YAML}")
    export CLUSTER_B_DIR
    KUBECONF_CLUSTER_B=${CLUSTER_B_DIR}/auth/kubeconfig
    export KUBECONF_CLUSTER_B
    export KUBECONF_MANAGED="${KUBECONF_CLUSTER_B}"
  else
    echo "# Cluster B was not installed - Unset \$KUBECONF_CLUSTER_B"
    unset KUBECONF_CLUSTER_B
    unset CLUSTER_B_NAME
  fi

  # Setting Cluster C config ($WORKDIR and $CLUSTER_C_NAME were set in subm_variables file)
  if [[ -s "$CLUSTER_C_YAML" ]] ; then
    echo "# Exporting \$KUBECONF_CLUSTER_C for $CLUSTER_C_NAME"

    # Get cluster platform and base domain from OCP installer yaml, and append it to the cluster name
    ocp_yaml_platform="$(grep -Poz 'platform:\s*\K\w+' ${CLUSTER_C_YAML} | awk -F'\0' '{print $1; exit}' || :)"
    # ocp_yaml_base_dns="$(grep -Poz 'baseDomain:\s*\K\w+' ${CLUSTER_C_YAML} | awk -F'\0' '{print $1; exit}}' || :)"
    export CLUSTER_C_NAME="${CLUSTER_C_NAME}${ocp_yaml_base_dns:+-$ocp_yaml_base_dns}${ocp_yaml_platform:+-$ocp_yaml_platform}"

    export CLUSTER_C_DIR=${WORKDIR}/${CLUSTER_C_NAME}
    export KUBECONF_CLUSTER_C=${CLUSTER_C_DIR}/auth/kubeconfig
    export KUBECONF_MANAGED="${KUBECONF_CLUSTER_C}"
  else
    echo "# Cluster C was not installed - Unset \$KUBECONF_CLUSTER_C"
    unset KUBECONF_CLUSTER_C
    unset CLUSTER_C_NAME
  fi

}

# ------------------------------------------

function update_kubeconfig_context_cluster_a() {
  PROMPT "Updating kubeconfig to the default context on cluster A"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  update_kubeconfig_default_context "${CLUSTER_A_NAME}"

}

# ------------------------------------------

function update_kubeconfig_context_cluster_b() {
  PROMPT "Updating kubeconfig to the default context on cluster B"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  update_kubeconfig_default_context "${CLUSTER_B_NAME}"

}

# ------------------------------------------

function update_kubeconfig_context_cluster_c() {
  PROMPT "Updating kubeconfig to the default context on cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  update_kubeconfig_default_context "${CLUSTER_C_NAME}"

}

# ------------------------------------------

function update_kubeconfig_default_context() {
  # Backup kubeconfig of the cluster, and update its context name
  trap_to_debug_commands;

  local cluster_name
  cluster_name="$1"

  [[ -f ${KUBECONFIG} ]] || FATAL "Openshift deployment configuration for cluster '$cluster_name' is missing: ${KUBECONFIG}"

  echo "# Backup current KUBECONFIG to: ${KUBECONFIG}.bak (if it doesn't exists already)"
  [[ -s ${KUBECONFIG}.bak ]] || cp -f "${KUBECONFIG}" "${KUBECONFIG}.bak"

  TITLE "Set current context of cluster '$cluster_name' to the first context with master (or admin) user"

  local master_context
  local master_user="master"

  master_context=$(${OC} config view -o json | jq -r "[.contexts[] | select(.context.user | test(\"${master_user}\")).name][0] // empty")

  if [[ -z "$master_context" ]] ; then
    master_user="admin"
    master_context=$(${OC} config view -o json | jq -r "[.contexts[] | select(.context.user | test(\"${master_user}\")).name][0] // empty")
  fi

  echo "# Switch to the cluster of the '$master_user' user"
  ${OC} config use-context "$master_context"

  local cur_context
  cur_context="$(${OC} config current-context)"

  local cur_username
  cur_username="$(${OC} config view -o jsonpath="{.contexts[?(@.name == '${cur_context}')].context.user}")"

  local cluster_url
  # cluster_url="$(${OC} config get-clusters | tail -1)"
  cluster_url="$(${OC} config view -o jsonpath="{.contexts[?(@.name == '${cur_context}')].context.cluster}")"

  BUG "If using managed cluster-id with long name or special characters (from current kubeconfig context),
  Submariner Gateway resource will not be created using Submariner Addon" \
  "Replace all special characters in kubeconfig current context before running subctl deploy" \
  "https://bugzilla.redhat.com/show_bug.cgi?id=2036325"
  # Workaround:
  local renamed_context="${cluster_name//[^a-z0-9]/-}" # Replace anything but letters and numbers with "-"

  if [[ ! "$cur_context" = "${renamed_context}" ]] ; then

    TITLE "Renaming kubeconfig current-context to '$renamed_context'"

    BUG "E2E will fail if clusters have same name (default is \"admin\")" \
    "Modify KUBECONFIG cluster context name on both clusters to be unique" \
    "https://github.com/submariner-io/submariner/issues/245"

    if ${OC} config get-contexts -o name | grep "${renamed_context}" 2>/dev/null ; then
      echo "# Rename existing kubeconfig context '${renamed_context}' to: ${renamed_context}_old"
      ${OC} config delete-context "${renamed_context}_old" || :
      ${OC} config rename-context "${renamed_context}" "${renamed_context}_old" || :
    fi

    ${OC} config rename-context "${cur_context}" "${renamed_context}" || :
    # ${OC} config use-context "$renamed_context" || :
  fi

  TITLE "Updating KUBECONFIG current context '$renamed_context' to use:
  Cluster url: $cluster_url
  Auth user: $cur_username
  Namespace: default
  "

  # ${OC} config set "contexts.${renamed_context}.namespace" "default"
  ${OC} config set-context "$renamed_context" --cluster "$cluster_url" --user "${cur_username}" --namespace "default"
  ${OC} config use-context "$renamed_context"

  ${OC} config get-contexts

  # ${OC} set env dc/dcname TZ=Asia/Jerusalem

}

# ------------------------------------------

function test_kubeconfig_cluster_a() {
# Check that OCP cluster A (public) is up and running
  trap_to_debug_commands;
  export KUBECONFIG="${KUBECONF_HUB}"

  test_cluster_status "$CLUSTER_A_NAME"
}

# ------------------------------------------

function test_kubeconfig_cluster_b() {
# Check that OSP cluster B (on-prem) is up and running
  trap_to_debug_commands;
  export KUBECONFIG="${KUBECONF_CLUSTER_B}"

  test_cluster_status "$CLUSTER_B_NAME"
}

# ------------------------------------------

function test_kubeconfig_cluster_c() {
# Check that OCP cluster C (public) is up and running
  trap_to_debug_commands;
  export KUBECONFIG="${KUBECONF_CLUSTER_C}"

  test_cluster_status "$CLUSTER_C_NAME"
}

# ------------------------------------------

function test_cluster_status() {
  # Verify that current kubeconfig cluster is up and healthy
  trap_to_debug_commands;

  local cluster_name="$1"

  # Get OCP cluster version
  local cluster_version
  cluster_version="$(${OC} version | awk '/Server Version/ { print $3 }' )" || :

  PROMPT "Testing status of cluster $cluster_name ${cluster_version:+(OCP Version $cluster_version)}"

  [[ -f ${KUBECONFIG} ]] || FATAL "Openshift deployment configuration for '$cluster_name' is missing: ${KUBECONFIG}"

  local kubeconfig_copy="${SCRIPT_DIR}/kubconf_${cluster_name}"
  echo "# Copy '${KUBECONFIG}' of ${cluster_name} to current workspace: ${kubeconfig_copy}"
  cp -f "$KUBECONFIG" "${kubeconfig_copy}" || :

  ${OC} config view
  ${OC} status -n default || FATAL "Openshift cluster is not installed, or using wrong context for '$cluster_name' in kubeconfig: ${KUBECONFIG}"
  ${OC} version
  ${OC} get all -n default
    # NAME                 TYPE           CLUSTER-IP   EXTERNAL-IP                            PORT(S)   AGE
    # service/kubernetes   clusterIP      172.30.0.1   <none>                                 443/TCP   39m
    # service/openshift    ExternalName   <none>       kubernetes.default.svc.cluster.local   <none>    32m

  wait_for_all_nodes_ready
}

# ------------------------------------------

function add_elevated_user_to_cluster_a() {
  PROMPT "Adding elevated user to cluster A"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  add_elevated_user

}

# ------------------------------------------

function add_elevated_user_to_cluster_b() {
  PROMPT "Adding elevated user to cluster B"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  add_elevated_user

}

# ------------------------------------------

function add_elevated_user_to_cluster_c() {
  PROMPT "Adding elevated user to cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  add_elevated_user

}

# ------------------------------------------

function add_elevated_user() {
  # Add new elevated user to OCP cluster
  # Ref: https://docs.openshift.com/container-platform/latest/authentication/identity_providers/configuring-htpasswd-identity-provider.html

  trap_to_debug_commands;

  local http_sec_name="http.sec"

  TITLE "Create an HTPasswd file for OCP user '$OCP_USR'"

  # Update ${OCP_USR}.sec and http.sec - Only if http.sec is empty or older than 1 day
  touch -a "${WORKDIR}/${http_sec_name}"
  if find "${WORKDIR}/${http_sec_name}" \( -mtime +1 -o -empty \) | grep . ; then
    echo "# Create random secret for ${OCP_USR}.sec (since ${http_sec_name} is empty or older than 1 day)"
    ( # subshell to hide commands
      openssl rand -base64 12 > "${WORKDIR}/${OCP_USR}.sec"
      local ocp_pwd
      ocp_pwd="$(< ${WORKDIR}/${OCP_USR}.sec)"
      printf "%s:%s\n" "${OCP_USR}" "$(openssl passwd -apr1 ${ocp_pwd})" > "${WORKDIR}/${http_sec_name}"
    )
  fi

  ${OC} delete secret $http_sec_name -n openshift-config --ignore-not-found || :

  ${OC} create secret generic ${http_sec_name} --from-file=htpasswd=${WORKDIR}/${http_sec_name} -n openshift-config

  TITLE "Add the HTPasswd identity provider to the registry"

  local cluster_auth="${WORKDIR}/cluster_auth.yaml"

  cat <<-EOF > $cluster_auth
  apiVersion: config.openshift.io/v1
  kind: OAuth
  metadata:
   name: cluster
  spec:
   identityProviders:
   - name: htpasswd_provider
     mappingMethod: claim
     type: HTPasswd
     htpasswd:
       fileData:
         name: ${http_sec_name}
EOF

  ${OC} apply set-last-applied --create-annotation=true -f $cluster_auth || :

  ${OC} apply -f $cluster_auth

  ${OC} describe oauth.config.openshift.io/cluster

  TITLE "Adding the new user '${OCP_USR}' to OCP cluster roles"

  ### Give user admin privileges
  # ${OC} create clusterrolebinding registry-controller --clusterrole=cluster-admin --user=${OCP_USR}
  ${OC} adm policy add-cluster-role-to-user cluster-admin ${OCP_USR} --rolebinding-name cluster-admin

  ${OC} describe clusterrolebindings system:${OCP_USR}

  ${OC} describe clusterrole system:${OCP_USR}

  local cmd="${OC} get clusterrolebindings --no-headers -o custom-columns='USER:subjects[].name'"
  watch_and_retry "$cmd | grep 'system:${OCP_USR}\$'" 5m || BUG "WARNING: User \"${OCP_USR}\" may not be cluster admin"

  ${OC} get clusterrolebindings

  ocp_login "${OCP_USR}" "$(< ${WORKDIR}/${OCP_USR}.sec)"

  local cur_context
  cur_context="$(${OC} config current-context)"
  TITLE "Kubeconfig current-context is: $cur_context"

  # BUG "subctl deploy can fail later on \"Error deploying the operator: timed out waiting for the condition\"" \
  # "Replace all special characters in kubeconfig current context before running subctl deploy" \
  # "https://bugzilla.redhat.com/show_bug.cgi?id=1973288"
  #
  # # Workaround:
  # local renamed_context="${cur_context//[^a-z0-9]/-}" # Replace anything but letters and numbers with "-"
  # if ${OC} config get-contexts -o name | grep "${renamed_context}" 2>/dev/null ; then
  #   echo "# Rename existing kubeconfig context '${renamed_context}' to: ${renamed_context}_old"
  #   ${OC} config delete-context "${renamed_context}_old" || :
  #   ${OC} config rename-context "${renamed_context}" "${renamed_context}_old" || :
  # fi
  # ${OC} config rename-context "${cur_context}" "${renamed_context}" || :
  # ${OC} config use-context "$renamed_context" || :

}


# ------------------------------------------

function clean_submariner_namespace_and_resources_cluster_a() {
### Run cleanup of previous Submariner on OCP cluster A (public) ###
  PROMPT "Cleaning previous Submariner (Namespaces, OLM, CRDs, Cluster Roles, ServiceExports) on OCP cluster A (public)"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  clean_submariner_namespace_and_resources
}

# ------------------------------------------

function clean_submariner_namespace_and_resources_cluster_b() {
### Run cleanup of previous Submariner on OSP cluster B (on-prem) ###
  PROMPT "Cleaning previous Submariner (Namespaces, OLM, CRDs, Cluster Roles, ServiceExports) on OSP cluster B (on-prem)"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  clean_submariner_namespace_and_resources
}

# ------------------------------------------

function clean_submariner_namespace_and_resources_cluster_c() {
### Run cleanup of previous Submariner on cluster C ###
  PROMPT "Cleaning previous Submariner (Namespaces, OLM, CRDs, Cluster Roles, ServiceExports) on cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  clean_submariner_namespace_and_resources
}

# ------------------------------------------

function clean_submariner_namespace_and_resources() {
  trap_to_debug_commands;

  BUG "Deploying broker will fail if previous submariner-operator namespaces and CRDs already exist" \
  "Run cleanup (oc delete) of any existing resource of submariner-operator" \
  "https://github.com/submariner-io/submariner-operator/issues/88
  https://github.com/submariner-io/submariner-website/issues/272"

  delete_submariner_namespace_and_crds

  delete_submariner_cluster_roles

  delete_lighthouse_dns_list

  delete_submariner_test_namespaces

  BUG "Low disk-space on OCP cluster that was running for few weeks" \
  "Delete old E2E namespaces" \
  "https://github.com/submariner-io/submariner-website/issues/341
  https://github.com/submariner-io/shipyard/issues/355"

  delete_e2e_namespaces

}

# ------------------------------------------

function delete_submariner_namespace_and_crds() {
### Run cleanup of previous Submariner namespace and CRDs ###
  trap_to_debug_commands;

  # force_delete_namespace "${SUBM_NAMESPACE}"

  delete_crds_by_name "submariner"

  ${OC} delete namespace ${SUBM_NAMESPACE} --wait || :
  ${OC} wait --for=delete namespace ${SUBM_NAMESPACE} || :

  # Required if Broker cluster is not a Dataplane cluster as well:
  force_delete_namespace "${BROKER_NAMESPACE}"

}

# ------------------------------------------

function delete_submariner_cluster_roles() {
### Run cleanup of previous Submariner ClusterRoles and ClusterRoleBindings ###
  trap_to_debug_commands;

  TITLE "Deleting Submariner ClusterRoles and ClusterRoleBindings"

  local roles="submariner-operator submariner-operator-globalnet submariner-lighthouse submariner-networkplugin-syncer"

  ${OC} delete clusterrole,clusterrolebinding $roles --ignore-not-found || :

}

# ------------------------------------------

function delete_lighthouse_dns_list() {
### Run cleanup of previous Lighthouse ServiceExport DNS list ###
  trap_to_debug_commands;

  TITLE "Clean Lighthouse ServiceExport DNS list:"

  ${OC} apply -f - <<EOF
  apiVersion: operator.openshift.io/v1
  kind: DNS
  metadata:
    finalizers:
    - dns.operator.openshift.io/dns-controller
    name: default
  spec:
    servers: []
EOF

}

# ------------------------------------------

function delete_submariner_test_namespaces() {
### Delete previous Submariner test namespaces from current cluster ###
  trap_to_debug_commands;

  TITLE "Deleting Submariner test namespaces: '$TEST_NS' '$HEADLESS_TEST_NS'"

  for ns in "$TEST_NS" "$HEADLESS_TEST_NS" ; do
    if [[ -n "$ns" ]]; then
      force_delete_namespace "$ns"
      # create_namespace "$ns"
    fi
  done

  TITLE "Unset Submariner test namespaces from kubeconfig current context"
  local cur_context
  cur_context="$(${OC} config current-context)"
  ${OC} config unset "contexts.${cur_context}.namespace"

}

# ------------------------------------------

function delete_e2e_namespaces() {
### Delete previous Submariner E2E namespaces from current cluster ###
  trap_to_debug_commands;

  local e2e_namespaces
  e2e_namespaces="$(${OC} get ns -o=custom-columns=NAME:.metadata.name | grep e2e-tests | cat )"

  if [[ -n "$e2e_namespaces" ]] ; then
    TITLE "Deleting all 'e2e-tests' namespaces: $e2e_namespaces"
    # ${OC} delete --timeout=30s ns $e2e_namespaces

    for ns_name in $e2e_namespaces ; do
      force_delete_namespace "$ns_name"
    done
  else
    echo "No 'e2e-tests' namespaces exist to be deleted"
  fi

}

# ------------------------------------------

function clean_submariner_labels_and_machine_sets_cluster_a() {
### Remove previous Submariner Gateway Node's Labels and MachineSets from OCP cluster A (public) ###
  PROMPT "Remove previous Submariner Gateway Node's Labels and MachineSets from OCP cluster A (public)"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"

  remove_submariner_gateway_labels

  remove_submariner_machine_sets
}

# ------------------------------------------

function clean_submariner_labels_and_machine_sets_cluster_b() {
### Remove previous Submariner Gateway Node's Labels and MachineSets from OSP cluster B (on-prem) ###
  PROMPT "Remove previous Submariner Gateway Node's Labels and MachineSets from OSP cluster B (on-prem)"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"

  remove_submariner_gateway_labels

  remove_submariner_machine_sets
}

# ------------------------------------------

function clean_submariner_labels_and_machine_sets_cluster_c() {
### Remove previous Submariner Gateway Node's Labels and MachineSets from cluster C ###
  PROMPT "Remove previous Submariner Gateway Node's Labels and MachineSets from cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"

  remove_submariner_gateway_labels

  remove_submariner_machine_sets
}

# ------------------------------------------

function remove_submariner_gateway_labels() {
  trap_to_debug_commands;

  TITLE "Remove previous submariner gateway labels from all node in the cluster:"

  ${OC} label --all node submariner.io/gateway- || :
}

# ------------------------------------------

function remove_submariner_machine_sets() {
  trap_to_debug_commands;

  TITLE "Remove previous machineset (if it has a template with submariner gateway label)"

  local subm_machineset
  subm_machineset="`${OC} get machineset -A -o jsonpath='{.items[?(@.spec.template.spec.metadata.labels.submariner\.io\gateway=="true")].metadata.name}'`"
  local ns
  ns="`${OC} get machineset -A -o jsonpath='{.items[?(@.spec.template.spec.metadata.labels.submariner\.io\gateway=="true")].metadata.namespace}'`"

  if [[ -n "$subm_machineset" && -n "$ns" ]] ; then
    ${OC} delete machineset $subm_machineset -n $ns || :
  fi

  ${OC} get machineset -A -o wide || :
}

# ------------------------------------------

# function remove_submariner_images_from_local_registry_with_podman() {
#   trap_to_debug_commands;
#
#   PROMPT "Remove previous Submariner images from local Podman registry"
#
#   [[ -x "$(command -v subctl)" ]] || FATAL "No SubCtl installation found. Try to run again with option '--subctl-version'"
#   # Get SubCtl version (from file $SUBCTL_VERSION_FILE)
#
#   # install_local_podman "${WORKDIR}"
#
#   local VERSION="$(subctl version | awk '{print $3}')"
#
#   for img in \
#     $SUBM_IMG_GATEWAY \
#     $SUBM_IMG_ROUTE \
#     $SUBM_IMG_NETWORK \
#     $SUBM_IMG_LIGHTHOUSE \
#     $SUBM_IMG_COREDNS \
#     $SUBM_IMG_GLOBALNET \
#     $SUBM_IMG_OPERATOR \
#     $SUBM_IMG_BUNDLE \
#     ; do
#       echo -e "# Removing Submariner image from local Podman registry: $SUBM_SNAPSHOT_REGISTRY/$SUBM_IMG_PREFIX-$img:$VERSION \n"
#
#       podman image rm -f $SUBM_SNAPSHOT_REGISTRY/$SUBM_IMG_PREFIX-$img:$VERSION # > /dev/null 2>&1
#       podman pull $SUBM_SNAPSHOT_REGISTRY/$SUBM_IMG_PREFIX-$img:$VERSION
#       podman image inspect $SUBM_SNAPSHOT_REGISTRY/$SUBM_IMG_PREFIX-$img:$VERSION # | jq '.[0].Config.Labels'
#   done
# }

# ------------------------------------------

function delete_old_submariner_images_from_cluster_a() {
  PROMPT "Delete previous Submariner images in OCP cluster A"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  delete_old_submariner_images_from_current_cluster
}

# ------------------------------------------

function delete_old_submariner_images_from_cluster_b() {
  PROMPT "Delete previous Submariner images in OSP cluster B"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  delete_old_submariner_images_from_current_cluster
}

# ------------------------------------------

function delete_old_submariner_images_from_cluster_c() {
  PROMPT "Delete previous Submariner images in cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  delete_old_submariner_images_from_current_cluster
}

# ------------------------------------------

function delete_old_submariner_images_from_current_cluster() {
### Configure a mirror server on the cluster registry
  trap_to_debug_commands

  TITLE "Deleting old Submariner images, tags, and image streams (if exist)"

  for node in $(${OC} get nodes -o name) ; do
    echo -e "\n### Delete Submariner images in $node ###"
    ${OC} debug $node -n default -- chroot /host /bin/bash -c "\
    crictl images | awk '\$1 ~ /submariner|lighthouse/ {print \$3}' | xargs -n1 crictl rmi" || :
  done

  # # Delete images
  # ${OC} get images | grep "${BREW_REGISTRY}" | while read -r line ; do
  #   set -- $(echo $line | awk '{ print $1, $2 }')
  #   local img_sha="$1"
  #   local img_name="$2"
  #
  #   echo "# Deleting registry image: $(echo $img_name | sed -r 's|.*/([^@]+).*|\1|')"
  #   ${OC} delete image $img_sha --ignore-not-found
  # done
  #
  # # Delete image-stream tags
  # ${OC} get istag -n ${SUBM_NAMESPACE} | awk '{print $1}' | while read -r img_tag ; do
  #   echo "# Deleting image stream tag: $img_tag"
  #   ${OC} delete istag $img_tag -n ${SUBM_NAMESPACE} --ignore-not-found
  # done

  # Delete image-stream
  for img_stream in \
    $SUBM_IMG_GATEWAY \
    $SUBM_IMG_ROUTE \
    $SUBM_IMG_NETWORK \
    $SUBM_IMG_LIGHTHOUSE \
    $SUBM_IMG_COREDNS \
    $SUBM_IMG_GLOBALNET \
    $SUBM_IMG_OPERATOR \
    $SUBM_IMG_BUNDLE \
    ; do
    TITLE "Deleting image stream: $img_stream"
    ${OC} delete imagestream "${img_stream}" -n ${SUBM_NAMESPACE} --ignore-not-found || :
    # ${OC} tag -d submariner-operator/${img_stream}
  done

}

# ------------------------------------------

function configure_namespace_for_submariner_tests_on_cluster_a() {
  PROMPT "Configure namespace '${TEST_NS:-default}' for running tests on OCP cluster A (public)"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  configure_namespace_for_submariner_tests

}

# ------------------------------------------

function configure_namespace_for_submariner_tests_on_managed_cluster() {
  PROMPT "Configure namespace '${TEST_NS:-default}' for running tests on managed cluster"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_MANAGED}"

  configure_namespace_for_submariner_tests

}

# ------------------------------------------

function configure_namespace_for_submariner_tests() {
  trap_to_debug_commands;

  TITLE "Set the default namespace to '${TEST_NS}' (if TEST_NS parameter was set in variables file)"
  if [[ -n "$TEST_NS" ]] ; then
    TITLE "Create namespace for Submariner tests: ${TEST_NS}"
    create_namespace "${TEST_NS}"
  else
    TITLE "Using the 'default' namespace for Submariner tests"
    export TEST_NS=default
  fi

  BUG "On OCP version < 4.4.6 : If running inside different cluster, OC can use wrong project name by default" \
  "Set the default namespace to \"${TEST_NS}\"" \
  "https://bugzilla.redhat.com/show_bug.cgi?id=1826676"
  # Workaround:
  echo "# Change the default namespace in [${KUBECONFIG}] to: ${TEST_NS:-default}"
  cur_context="$(${OC} config current-context)"
  ${OC} config set "contexts.${cur_context}.namespace" "${TEST_NS:-default}"

}

# ------------------------------------------

function install_netshoot_app_on_cluster_a() {
  PROMPT "Install Netshoot application on OCP cluster A (public)"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"

  [[ -z "$TEST_NS" ]] || create_namespace "${TEST_NS}"

  ${OC} delete pod ${NETSHOOT_CLUSTER_A} --ignore-not-found ${TEST_NS:+-n $TEST_NS} || :

  # NETSHOOT_CLUSTER_A=netshoot-cl-a # Already exported in global subm_variables

  # Deployment is terminated after netshoot is loaded - need to "oc run" with infinite loop
  # ${OC} delete deployment ${NETSHOOT_CLUSTER_A}  --ignore-not-found ${TEST_NS:+-n $TEST_NS}
  # ${OC} create deployment ${NETSHOOT_CLUSTER_A}  --image ${NETSHOOT_IMAGE} ${TEST_NS:+-n $TEST_NS}
  ${OC} run ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --image ${NETSHOOT_IMAGE} -- sleep infinity

  TITLE "Wait up to 3 minutes for Netshoot pod [${NETSHOOT_CLUSTER_A}] to be ready:"
  ${OC} wait --timeout=3m --for=condition=ready pod -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
  ${OC} describe pod ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
}

# ------------------------------------------

function install_nginx_svc_on_managed_cluster() {
  trap_to_debug_commands;
  local cluster_name

  export KUBECONFIG="${KUBECONF_MANAGED}"
  cluster_name="$(print_current_cluster_name || :)"
  PROMPT "Install Nginx service on managed cluster $cluster_name ${TEST_NS:+ (Namespace $TEST_NS)}"

  TITLE "Creating ${NGINX_CLUSTER_BC}:${NGINX_PORT} in ${TEST_NS}, using ${NGINX_IMAGE}, and disabling it's cluster-ip (with '--cluster-ip=None'):"

  install_nginx_service "${NGINX_CLUSTER_BC}" "${NGINX_IMAGE}" "${TEST_NS}" "--port=${NGINX_PORT}" || :
}

# ------------------------------------------

function test_basic_cluster_connectivity_before_submariner() {
### Pre-test - Demonstrate that the clusters aren’t connected without Submariner ###
  trap_to_debug_commands;
  local cluster_name

  export KUBECONFIG="${KUBECONF_MANAGED}"
  cluster_name="$(print_current_cluster_name || :)"
  PROMPT "Before Submariner is installed: Verifying IP connectivity on the SAME cluster ($cluster_name)"

  # Trying to connect from cluster A to cluster B/C will fail (after 5 seconds).
  # It’s also worth looking at the clusters to see that Submariner is nowhere to be seen.

  echo -e "\n# Get IP of ${NGINX_CLUSTER_BC} on managed cluster $cluster_name ${TEST_NS:+(Namespace: $TEST_NS)} to verify connectivity:\n"

  ${OC} get svc -l app=${NGINX_CLUSTER_BC} ${TEST_NS:+-n $TEST_NS}
  nginx_IP_cluster_bc=$(${OC} get svc -l app=${NGINX_CLUSTER_BC} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')
    # nginx_cluster_b_ip: 100.96.43.129

  local netshoot_pod=netshoot-cl-bc-new # A new Netshoot pod on cluster B/C
  TITLE "Install $netshoot_pod on OSP managed cluster, and verify connectivity in the SAME cluster, to ${nginx_IP_cluster_bc}:${NGINX_PORT}"

  [[ -z "$TEST_NS" ]] || create_namespace "${TEST_NS}"

  ${OC} delete pod ${netshoot_pod} --ignore-not-found ${TEST_NS:+-n $TEST_NS} || :

  ${OC} run ${netshoot_pod} --attach=true --restart=Never --pod-running-timeout=3m --request-timeout=3m --rm -i \
  ${TEST_NS:+-n $TEST_NS} --image ${NETSHOOT_IMAGE} -- /bin/bash -c "curl --max-time 180 --verbose ${nginx_IP_cluster_bc}:${NGINX_PORT}"
}

# ------------------------------------------

function test_clusters_disconnected_before_submariner() {
### Pre-test - Demonstrate that the clusters aren’t connected without Submariner ###
  PROMPT "Before Submariner is installed:
  Verifying that Netshoot pod on OCP cluster A (public), cannot reach Nginx service on managed cluster"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_MANAGED}"

  # Trying to connect from cluster A to cluster B, will fails (after 5 seconds).
  # It’s also worth looking at the clusters to see that Submariner is nowhere to be seen.

  # nginx_IP_cluster_bc=$(${OC} get svc -l app=${NGINX_CLUSTER_BC} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')
  ${OC} get svc -l app=${NGINX_CLUSTER_BC} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}' > "$TEMP_FILE"
  nginx_IP_cluster_bc="$(< $TEMP_FILE)"
    # nginx_cluster_bc_ip: 100.96.43.129

  export KUBECONFIG="${KUBECONF_HUB}"
  # ${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --field-selector status.phase=Running | awk 'FNR == 2 {print $1}' > "$TEMP_FILE"
  # netshoot_pod_cluster_a="$(< $TEMP_FILE)"
  netshoot_pod_cluster_a="`get_running_pod_by_label "run=${NETSHOOT_CLUSTER_A}" "$TEST_NS" `"

  msg="# Negative Test - Clusters should NOT be able to connect without Submariner."

  ${OC} exec $netshoot_pod_cluster_a ${TEST_NS:+-n $TEST_NS} -- \
  curl --output /dev/null --max-time 20 --verbose ${nginx_IP_cluster_bc}:${NGINX_PORT} \
  |& (! highlight "command terminated with exit code" && FATAL "$msg") || echo -e "$msg"
    # command terminated with exit code 28
}

# ------------------------------------------

function download_and_install_subctl() {
  ### Download SubCtl - Submariner installer - Latest RC release ###
    PROMPT "Testing \"getsubctl.sh\" to download and use SubCtl version $SUBM_VER_TAG"

    local subctl_version="${1:-$SUBM_VER_TAG}"

    # Fix the $subctl_version value for custom images
    set_subm_version_tag_var "subctl_version"

    download_subctl_by_tag "$subctl_version"

}

# ------------------------------------------

function set_subm_version_tag_var() {
# update the variable value of $SUBM_VER_TAG (or the $1 input var name)
  trap_to_debug_commands;

  # Get variable name (default is "SUBM_VER_TAG")
  local tag_var_name="${1:-SUBM_VER_TAG}"

  # Set subm_version_tag as the actual value of tag_var_name
  local subm_version_tag="${!tag_var_name}"

  [[ -n "${subm_version_tag}" ]] || FATAL "Submariner version to use was not defined. Try to run again with option '--subctl-version x.y.z'"

  TITLE "Retrieve correct tag for SubCtl version \$${tag_var_name} : $subm_version_tag"
  if [[ "$subm_version_tag" =~ latest|devel ]]; then
    subm_version_tag=$(get_subctl_branch_tag)
  elif [[ "$subm_version_tag" =~ ^[0-9] ]]; then
    echo "# Version ${subm_version_tag} is considered as 'v${subm_version_tag}' tag"
    subm_version_tag=v${subm_version_tag}
  fi

  # export REGISTRY_TAG_MATCH='[0-9]+\.[0-9]+' # Regex for required image tag (X.Y.Z ==> X.Y)
  # echo "# REGISTRY_TAG_MATCH variable was set to extract from '$subm_version_tag' the regex match: $REGISTRY_TAG_MATCH"
  # subm_version_tag=v$(echo $subm_version_tag | grep -Po "$REGISTRY_TAG_MATCH")
  # echo "# New \$${tag_var_name} for registry images: $subm_version_tag"

  # Reevaluate $tag_var_name value
  local eval_cmd="export ${tag_var_name}=${subm_version_tag}"
  eval $eval_cmd
}

# ------------------------------------------

function download_subctl_by_tag() {
  ### Download SubCtl - Submariner installer ###
    trap_to_debug_commands;

    # Optional param: $1 => SubCtl version by tag to download
    # If not specifying a tag - it will download latest version released (not latest subctl-devel)
    local subctl_branch_tag="${1:-v[0-9]}"

    cd ${WORKDIR}

    # Downloading SubCtl from VPN_REGISTRY (downstream)
    # if using --registry-images and if $subctl_branch_tag is not devel
    if [[ ! "$subctl_branch_tag" =~ devel ]] && \
        [[ "$registry_images" =~ ^(y|yes)$ ]] && \
        [[ -n "$SUBM_IMG_SUBCTL" ]] ; then

      TITLE "Backup previous subctl archive (if exists)"
      local subctl_xz="subctl-${subctl_branch_tag}-linux-amd64.tar.xz"
      [[ ! -e "$subctl_xz" ]] || mv -f ${subctl_xz} ${subctl_xz}.bak

      TITLE "Downloading SubCtl from $SUBM_IMG_SUBCTL"

      # Fix the $subctl_branch_tag value for custom images
      set_subm_version_tag_var "subctl_branch_tag"

      local subctl_image_url="${VPN_REGISTRY}/${REGISTRY_IMAGE_IMPORT_PATH}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}-${SUBM_IMG_SUBCTL}:${subctl_branch_tag}"
      # e.g. subctl_image_url="registry-proxy.engineering.redhat.com/rh-osbs/rhacm2-tech-preview-subctl-rhel8:0.9"

      # Check if $subctl_xz exists in $subctl_image_url
      ${OC} image extract $subctl_image_url --path=/dist/subctl*:./ --dry-run \
      |& highlight "$subctl_xz" || BUG "SubCtl binary with tag '$subctl_branch_tag' was not found in $subctl_image_url"

      ${OC} image extract $subctl_image_url --path=/dist/subctl-*-linux-amd64.tar.xz:./ --confirm

      echo -e "# Getting last downloaded subctl archive filename"
      subctl_xz="$(ls -1 -tu subctl-*-linux-amd64.tar.xz | head -1 )" || :
      ls -l "${subctl_xz}" || FATAL "subctl archive was not downloaded"

      echo "# SubCtl binary will be extracted from [${subctl_xz}]"
      tar -xvf ${subctl_xz} --strip-components 1 --wildcards --no-anchored  "subctl*"

      echo "# Rename last extracted file to subctl"
      local extracted_file
      extracted_file="$(ls -1 -tu subctl* | head -1)"
      [[ -f "$extracted_file" ]] || FATAL "subctl binary was not found in ${subctl_xz}"
      ls -l "${extracted_file}"

      mv "$extracted_file" subctl
      chmod +x subctl

      echo "# Install subctl into ${GOBIN}:"
      mkdir -p $GOBIN
      # cp -f ./subctl $GOBIN/
      /usr/bin/install ./subctl $GOBIN/subctl

      echo "# Install subctl into user HOME bin:"
      # cp -f ./subctl ~/.local/bin/
      /usr/bin/install ./subctl ~/.local/bin/subctl

    else
      # Downloading SubCtl from Github (upstream)

      local repo_tag
      repo_tag=$(get_subctl_branch_tag "${subctl_branch_tag}")

      TITLE "Downloading SubCtl '${repo_tag}' with getsubctl.sh from: https://get.submariner.io/"

      # curl https://get.submariner.io/ | VERSION=${subctl_branch_tag} bash -x
      BUG "getsubctl.sh fails on an unexpected argument, since the local 'install' is not the default" \
      "set 'PATH=/usr/bin:$PATH' for the execution of 'getsubctl.sh'" \
      "https://github.com/submariner-io/submariner-operator/issues/473"
      # Workaround:
      PATH="/usr/bin:$PATH" which install

      #curl https://get.submariner.io/ | VERSION=${subctl_branch_tag} PATH="/usr/bin:$PATH" bash -x
      BUG "getsubctl.sh sometimes fails on error 403 (rate limit exceeded)" \
      "If it has failed - Set 'getsubctl_status=FAILED' in order to download with wget instead" \
      "https://github.com/submariner-io/submariner-operator/issues/526"
      # Workaround:
      curl https://get.submariner.io/ | VERSION="${repo_tag}" PATH="/usr/bin:$PATH" bash -x || getsubctl_status=FAILED

      if [[ "$getsubctl_status" = FAILED ]] ; then

        TITLE "Download subctl directly, since 'getsubctl.sh' (https://get.submariner.io) failed"
        # For example, download: https://github.com/submariner-io/submariner-operator/releases/tag/subctl-release-0.8

        local subctl_releases_url
        subctl_releases_url="https://github.com/submariner-io/submariner-operator"
        releases_url="${subctl_releases_url}/releases"
        TITLE "Downloading SubCtl from upstream repository tag: ${releases_url}/tag/${repo_tag}"

        local file_path
        file_path="$(curl "${releases_url}/tag/${repo_tag}" | grep -Eoh 'download\/.*\/subctl-.*-linux-amd64[^"]+' -m 1)"

        download_file "${releases_url}/${file_path}"

        file_name=$(basename -- "$file_path")
        tar -xvf ${file_name} --strip-components 1 --wildcards --no-anchored  "subctl*"

        # Rename last extracted file to subctl
        extracted_file="$(ls -1 -tu subctl* | head -1)"

        [[ ! -e "$extracted_file" ]] || mv "$extracted_file" subctl
        chmod +x subctl

        echo "# Install subctl into ${GOBIN}:"
        mkdir -p $GOBIN
        # cp -f ./subctl $GOBIN/
        /usr/bin/install ./subctl $GOBIN/subctl

        echo "# Install subctl into user HOME bin:"
        # cp -f ./subctl ~/.local/bin/
        /usr/bin/install ./subctl ~/.local/bin/subctl
      fi

    fi

    echo "# Copy subctl from user HOME bin into ${GOBIN}:"
    mkdir -p $GOBIN
    # cp -f ./subctl $GOBIN/
    /usr/bin/install "$HOME/.local/bin/subctl" $GOBIN/subctl

    echo "# Add user HOME bin to system PATH:"
    export PATH="$HOME/.local/bin:$PATH"

    echo "# Store SubCtl version in $SUBCTL_VERSION_FILE"
    subctl version | awk '{print $3}' > "$SUBCTL_VERSION_FILE"

}

# ------------------------------------------

function get_subctl_branch_tag() {
  ### Print the tag of latest subctl version released ###
  # Do not echo more info, since the output is the returned value

  local subctl_tag_to_search=
  subctl_tag_to_search="${1:-v[0-9]}" # any tag that starts with v{NUMBER}
  local subctl_repo_url
  subctl_repo_url="https://github.com/submariner-io/submariner-operator"

  get_latest_repository_version_by_tag "$subctl_repo_url" "$subctl_tag_to_search"
}

# ------------------------------------------

function test_subctl_command() {
  trap_to_debug_commands;
  local subctl_version
  subctl_version="$(subctl version | awk '{print $3}' )" || :

  PROMPT "Verifying Submariner CLI tool ${subctl_version:+ ($subctl_version)}"

  [[ -x "$(command -v subctl)" ]] || FATAL "No SubCtl installation found. Try to run again with option '--subctl-version'"
  subctl version

  subctl --help

}

# ------------------------------------------

function set_join_parameters_for_cluster_a() {
  PROMPT "Set parameters of SubCtl Join command for OCP cluster A (public)"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  create_subctl_join_file "${SUBCTL_JOIN_CLUSTER_A_FILE}"
}

# ------------------------------------------

function set_join_parameters_for_cluster_b() {
  PROMPT "Set parameters of SubCtl Join command for OSP cluster B (on-prem)"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  create_subctl_join_file "${SUBCTL_JOIN_CLUSTER_B_FILE}"
}

# ------------------------------------------

function set_join_parameters_for_cluster_c() {
  PROMPT "Set parameters of SubCtl Join command for cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  create_subctl_join_file "${SUBCTL_JOIN_CLUSTER_C_FILE}"
}

# ------------------------------------------

function create_subctl_join_file() {
# Join Submariner member - of current cluster kubeconfig
  trap_to_debug_commands;

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"
  local join_cmd_file="$1"

  TITLE "Adding Broker file and IPSec ports to subctl join command on cluster ${cluster_name}"

  JOIN_CMD="subctl join \
  ./${BROKER_INFO} ${subm_cable_driver:+--cable-driver $subm_cable_driver} \
  --ikeport ${IPSEC_IKE_PORT} --nattport ${IPSEC_NATT_PORT}"

  TITLE "Adding '--health-check' to subctl join command (to enable Gateway health check)"

  JOIN_CMD="${JOIN_CMD} --health-check"

  local pod_debug_flag="--pod-debug"
  # For SubCtl <= 0.8 : '--enable-pod-debugging' is expected as the debug flag for the join command"
  [[ $(subctl version | grep --invert-match "v0.8") ]] || pod_debug_flag="--enable-pod-debugging"

  TITLE "Adding '${pod_debug_flag}' and '--ipsec-debug' to subctl join command (for tractability)"
  JOIN_CMD="${JOIN_CMD} ${pod_debug_flag} --ipsec-debug"

  BUG "SubCtl fails to join cluster, since it cannot auto-generate a valid cluster id" \
  "Add '--clusterid <ID>' to $join_cmd_file" \
  "https://bugzilla.redhat.com/show_bug.cgi?id=1972703"
  # Workaround
  ${OC} config view
  local cluster_id
  cluster_id=$(${OC} config current-context)

  BUG "SubCtl join of a long clusterid - No IPsec connections will be loaded later" \
  "Add '--clusterid <SHORT ID>' (e.g. of cluster id of the admin context) to $join_cmd_file" \
  "https://bugzilla.redhat.com/show_bug.cgi?id=1988797"
  # Workaround
  cluster_id=$(${OC} config view -o jsonpath='{.contexts[?(@.context.user == "admin")].context.cluster}' | awk '{print $1}')

  echo "# Write the join parameters into the join command file: $join_cmd_file"
  JOIN_CMD="${JOIN_CMD} --clusterid ${cluster_id//[^a-z0-9]/-}" # Replace anything but letters and numbers with "-"

  echo "$JOIN_CMD" > "$join_cmd_file"

}

# ------------------------------------------

function append_custom_images_to_join_cmd_cluster_a() {
# Append custom images to the join cmd file, for cluster A
  PROMPT "Append custom images to the join command of cluster A"
  trap_to_debug_commands;

  append_custom_images_to_join_cmd_file "${SUBCTL_JOIN_CLUSTER_A_FILE}"
}

# ------------------------------------------

function append_custom_images_to_join_cmd_cluster_b() {
# Append custom images to the join cmd file, for cluster B
  PROMPT "Append custom images to the join command of cluster B"
  trap_to_debug_commands;

  append_custom_images_to_join_cmd_file "${SUBCTL_JOIN_CLUSTER_B_FILE}"
}

# ------------------------------------------

function append_custom_images_to_join_cmd_cluster_c() {
# Append custom images to the join cmd file, for cluster C
  PROMPT "Append custom images to the join command of cluster C"
  trap_to_debug_commands;

  append_custom_images_to_join_cmd_file "${SUBCTL_JOIN_CLUSTER_C_FILE}"
}

# ------------------------------------------

function append_custom_images_to_join_cmd_file() {
# Join Submariner member - of current cluster kubeconfig
  trap_to_debug_commands;

  local join_cmd_file="$1"
  echo "# Read subctl join command from file: $join_cmd_file"
  local JOIN_CMD
  JOIN_CMD="$(< $join_cmd_file)"

  # # Fix the $SUBM_VER_TAG value for custom images
  # set_subm_version_tag_var
  # local image_tag=${SUBM_VER_TAG}"

  [[ -x "$(command -v subctl)" ]] || FATAL "No SubCtl installation found. Try to run again with option '--subctl-version'"
  local image_tag
  image_tag="$(subctl version | awk '{print $3}')"

  BUG "Overriding images with wrong keys should fail first in join command" \
  "No workaround" \
  "https://github.com/submariner-io/submariner-operator/issues/1018"

  # To be deprecated:
  export REGISTRY_IMAGE_PREFIX="rh-osbs/rhacm2-tech-preview-"

  TITLE "Append \"--image-override\" for custom images to subctl join command"
  JOIN_CMD="${JOIN_CMD} --image-override submariner-operator=${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}/${SUBM_IMG_OPERATOR}:${image_tag}"

  # BUG ? : this is a potential bug - overriding with comma separated:
  # JOIN_CMD="${JOIN_CMD} --image-override \
  # submariner=${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}/${SUBM_IMG_GATEWAY}:${image_tag},\
  # submariner-route-agent=${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}/${SUBM_IMG_ROUTE}:${image_tag}, \
  # submariner-networkplugin-syncer=${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}/${SUBM_IMG_NETWORK}:${image_tag},\
  # lighthouse-agent=${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}/${SUBM_IMG_LIGHTHOUSE}:${image_tag},\
  # lighthouse-coredns=${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}/${SUBM_IMG_COREDNS}:${image_tag},\
  # submariner-globalnet=${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}/${SUBM_IMG_GLOBALNET}:${image_tag},\
  # submariner-operator=${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}/${SUBM_IMG_OPERATOR}:${image_tag},\
  # submariner-bundle=${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}/${SUBM_IMG_BUNDLE}:${image_tag}"

  echo -e "# Write into the join command file [${join_cmd_file}]: \n${JOIN_CMD}"
  echo "$JOIN_CMD" > "$join_cmd_file"

}

# ------------------------------------------

function install_broker_cluster_a() {
### Installing Submariner Broker on OCP cluster A (public) ###
  echo -e "\n# TODO: Should test broker deployment also on different Public cluster (C), rather than on Public cluster A."
  echo -e "\n# TODO: Call kubeconfig of broker cluster"
  trap_to_debug_commands;

  local DEPLOY_CMD="subctl deploy-broker"

  if [[ "$globalnet" =~ ^(y|yes)$ ]]; then
    echo -e "\n# TODO: Move to a separate function"
    PROMPT "Adding GlobalNet to Submariner Deploy command"

    BUG "Running subctl with GlobalNet can fail if glabalnet_cidr address is already assigned" \
    "Define a new and unique globalnet-cidr for this cluster" \
    "https://github.com/submariner-io/submariner/issues/544"

    # DEPLOY_CMD="${DEPLOY_CMD} --globalnet --globalnet-cidr 169.254.0.0/19"
    DEPLOY_CMD="${DEPLOY_CMD} --globalnet"
  fi

  PROMPT "Deploying Submariner Broker on OCP cluster A (public)"
  # Deploys Submariner CRDs, creates the SA for the broker, the role and role bindings

  export KUBECONFIG="${KUBECONF_HUB}"
  DEPLOY_CMD="${DEPLOY_CMD} --kubecontext $(${OC} config current-context)"

  cd ${WORKDIR}
  #cd $GOPATH/src/github.com/submariner-io/submariner-operator

  TITLE "Remove previous ${BROKER_INFO} (if exists)"
  [[ ! -e "${BROKER_INFO}" ]] || rm "${BROKER_INFO}"

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"
  TITLE "Executing SubCtl Deploy command on $cluster_name: \n# ${DEPLOY_CMD}"

  BUG "For Submariner 0.9+ operator image should be accessible before broker deploy" \
  "Run broker deployment after uploading custom images to the cluster registry" \
  "https://github.com/submariner-io/submariner-website/issues/483"

  $DEPLOY_CMD
}

# ------------------------------------------

function test_broker_before_join() {
  PROMPT "Verify Submariner resources on the Broker cluster"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"

  # Now looking at Broker cluster, it should show that CRDs, but no pods in namespace
  ${OC} get crds | grep 'submariner.io'

  ${OC} describe crds \
  clusters.submariner.io \
  endpoints.submariner.io \
  serviceimports.multicluster.x-k8s.io || FAILURE "Expected to find CRD 'serviceimports.multicluster.x-k8s.io'"

  # serviceexports.lighthouse.submariner.io \
  # servicediscoveries.submariner.io \
  # submariners.submariner.io \
  # gateways.submariner.io \

  local regex="submariner-operator"
  # For SubCtl <= 0.8 : "No resources found" is expected on the broker after deploy command
  [[ $(subctl version | grep --invert-match "v0.8") ]] || regex="No resources found"

  if [[ ! "$skip_ocp_setup" =~ ^(y|yes)$ ]]; then
    ${OC} get pods -n ${SUBM_NAMESPACE} --show-labels |& highlight "$regex" \
     || FATAL "Submariner Broker which was created with $(subctl version) deploy command (before join) \
      should have \"$regex\" in the Broker namespace '${SUBM_NAMESPACE}'"
  fi
}

# ------------------------------------------

function open_firewall_ports_on_cluster_a() {
  PROMPT "Open firewall ports for the gateway node on OCP cluster A"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  open_firewall_ports_on_aws_gateway_nodes "$CLUSTER_A_DIR"
}

# ------------------------------------------

function open_firewall_ports_on_cluster_c() {
  PROMPT "Open firewall ports for the gateway node on OCP cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  open_firewall_ports_on_aws_gateway_nodes "$CLUSTER_C_DIR"
}

# ------------------------------------------

function open_firewall_ports_on_aws_gateway_nodes() {
### Open firewall ports for the gateway node with terraform (prep_for_subm.sh) on AWS cluster ###
  # Old readme: https://github.com/submariner-io/submariner/tree/devel/tools/openshift/ocp-ipi-aws
  echo -e "\n# TODO: subctl cloud prepare as: https://submariner.io/getting-started/quickstart/openshift/aws/#prepare-aws-clusters-for-submariner"
  trap_to_debug_commands;

  TITLE "Using \"prep_for_subm.sh\" - to add External IP and open ports on AWS cluster nodes for Submariner gateway"
  command -v terraform || FATAL "Terraform is required in order to run 'prep_for_subm.sh'"

  local ocp_install_dir="$1"

  local git_user="submariner-io"
  local git_project="submariner"
  local commit_or_branch="release-0.8"
  local github_dir="tools/openshift/ocp-ipi-aws"
  local target_path="${ocp_install_dir}/${github_dir}"
  local terraform_script="prep_for_subm.sh"

  mkdir -p "${git_project}_scripts"
  cd "${git_project}_scripts"

  download_github_file_or_dir "$git_user" "$git_project" "$commit_or_branch" "${github_dir}"

  BUG "'${terraform_script}' ignores local yamls and always download from devel branch" \
  "Copy '${github_dir}' directory (including '${terraform_script}') into OCP install dir" \
  "https://github.com/submariner-io/submariner/issues/880"
  # Workaround:

  TITLE "Copy '${github_dir}' directory (including '${terraform_script}') to ${target_path}"
  mkdir -p "${target_path}"
  cp -rf "${github_dir}"/* "${target_path}"
  cd "${target_path}/"

  # Fix bug in terraform version
  sed -r 's/0\.12\.12/0\.12\.29/g' -i versions.tf || :

  # Workaround for Terraform provider permission denied
  local terraform_plugins_dir="./.terraform/plugins/linux_amd64"
  if [[ -d "${terraform_plugins_dir}" ]] && [[ "$(ls -A "$terraform_plugins_dir")" ]] ; then
    chmod -R a+x $terraform_plugins_dir/* || :
  fi

  # Fix bug of using non-existing kubeconfig conext "admin"
  sed -e 's/--context=admin //g' -i "${terraform_script}"

  BUG "'prep_for_subm.sh' downloads remote 'ocp-ipi-aws', even if local 'ocp-ipi-aws' already exists" \
  "Modify 'prep_for_subm.sh' so it will download all 'ocp-ipi-aws/*' and do not change directory" \
  "----"
  # Workaround:
  sed 's/.*submariner_prep.*/# \0/' -i "${terraform_script}"

  BUG "Using the same IPSEC port numbers multiple times in one project, may be blocked on firewall" \
  "Make sure to use different IPSEC_NATT_PORT and IPSEC_IKE_PORT across clusters on same project" \
  "https://github.com/submariner-io/submariner-operator/issues/1047"
  # Workaround:
  # Do not use the same IPSEC port numbers multiple times in one project
  # Add in global submariner_variables
  # export IPSEC_NATT_PORT=${IPSEC_NATT_PORT:-4501}
  # export IPSEC_IKE_PORT=${IPSEC_IKE_PORT:-501}

  export GW_INSTANCE_TYPE=${GW_INSTANCE_TYPE:-m4.xlarge}

  TITLE "Running '${terraform_script} ${ocp_install_dir} -auto-approve' script to apply Terraform 'ec2-resources.tf'"
  # Use variables: -var region=”eu-west-2” -var region=”eu-west-1” or with: -var-file=newvariable.tf
  # bash -x ...
  ./${terraform_script} "${ocp_install_dir}" -auto-approve |& highlight "Apply complete| already exists" \
  || FATAL "./${terraform_script} did not complete successfully"

  # Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
  # OR
  # Security group rule already exists.
  #

}

# ------------------------------------------

function open_firewall_ports_on_openstack_cluster_b() {
  PROMPT "Open firewall ports for the gateway node on OSP cluster B"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  open_firewall_ports_on_osp_gateway_nodes "$CLUSTER_B_DIR"
}

# ------------------------------------------

function open_firewall_ports_on_osp_gateway_nodes() {
### Open OSP firewall ports on the gateway node with terraform (configure_osp.sh) ###
  # Readme: https://github.com/sridhargaddam/configure-osp-for-subm
  trap_to_debug_commands;

  TITLE "Using \"configure_osp.sh\" - to open firewall ports on all nodes in OSP cluster (on-prem)"
  command -v terraform || FATAL "Terraform is required in order to run 'configure_osp.sh'"

  local ocp_install_dir="$1"
  local git_user="redhat-openshift"
  local git_project="configure-osp-for-subm"
  local commit_or_branch="main"
  local github_dir="osp-scripts"
  local target_path="${ocp_install_dir}/${github_dir}"
  local terraform_script="configure_osp.sh"

  mkdir -p "${git_project}_scripts"
  cd "${git_project}_scripts"

  # Temporary, until merged to upstream
  # download_github_file_or_dir "$git_user" "$git_project" "$commit_or_branch" "${github_dir}"
  download_github_file_or_dir "$git_user" "$git_project" "$commit_or_branch" # "${github_dir}"

  # echo "# Copy '${github_dir}' directory (including '${terraform_script}') to ${target_path}"
  # mkdir -p "${target_path}"
  # cp -rf "${github_dir}"/* "${target_path}"
  # cd "${target_path}/"

  TITLE "Copy '${git_project}_scripts' directory (including '${terraform_script}') to ${target_path}_scripts"
  mkdir -p "${target_path}_scripts"
  cp -rf * "${target_path}_scripts"
  cd "${target_path}_scripts/"
  ### Temporary end

  # Fix bug in terraform version
  sed -r 's/0\.12\.12/0\.12\.29/g' -i versions.tf || :

  # Fix bug in terraform provider permission denied
  chmod -R a+x ./.terraform/plugins/linux_amd64/* || :

  # export IPSEC_NATT_PORT=${IPSEC_NATT_PORT:-4501}
  # export IPSEC_IKE_PORT=${IPSEC_IKE_PORT:-501}

  TITLE "Running '${terraform_script} ${ocp_install_dir} -auto-approve' script to apply open OSP required ports:"

  chmod a+x ./${terraform_script}
  # Use variables: -var region=”eu-west-2” -var region=”eu-west-1” or with: -var-file=newvariable.tf
  # bash -x ...
  ./${terraform_script} "${ocp_install_dir}" -auto-approve |& highlight "Apply complete| already exists" \
  || FATAL "./${terraform_script} did not complete successfully"

  # Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
  # OR
  # Security group rule already exists.
  #

}

# ------------------------------------------

function label_gateway_on_broker_nodes_with_external_ip() {
### Label a Gateway node on OCP cluster A (public) ###
  PROMPT "Adding Gateway label to all worker nodes with an External-IP on OCP cluster A (public)"
  trap_to_debug_commands;

  BUG "If one of the gateway nodes does not have External-IP, submariner will fail to connect later" \
  "Make sure one node with External-IP has a gateway label" \
  "https://github.com/submariner-io/submariner-operator/issues/253"

  export KUBECONFIG="${KUBECONF_HUB}"
  echo -e "\n# TODO: Check that the Gateway label was created with prep_for_subm.sh on OCP cluster A (public) ?"
  gateway_label_all_nodes_external_ip
}

# ------------------------------------------

function label_first_gateway_cluster_b() {
### Label a Gateway node on cluster B ###
  PROMPT "Adding Gateway label to the first worker node on cluster B"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  gateway_label_first_worker_node
}

# ------------------------------------------

function label_first_gateway_cluster_c() {
### Label a Gateway node on cluster C ###
  PROMPT "Adding Gateway label to the first worker node on cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"

  BUG "Having 2 nodes with GW label, can cause connection failure" \
  "Skip labeling another node with Submariner gateway" \
  "TODO: Report bug"
  # Workaround: Skip:
  # gateway_label_first_worker_node
}

# ------------------------------------------

function gateway_label_first_worker_node() {
### Adding submariner gateway label to the first worker node ###
  trap_to_debug_commands;

  # gw_node1=$(${OC} get nodes -l node-role.kubernetes.io/worker | awk 'FNR == 2 {print $1}')
  ${OC} get nodes -l node-role.kubernetes.io/worker | awk 'FNR == 2 {print $1}' > "$TEMP_FILE"
  gw_node1="$(< $TEMP_FILE)"

  [[ -n "$gw_node1" ]] || FATAL "Failed to list worker nodes in current cluster"

  TITLE "Adding submariner gateway labels to first worker node: $gw_node1"
    # gw_node1: user-cl1-bbmkg-worker-8mx4k

  echo -e "\n# TODO: Run only If there's no Gateway label already"
  ${OC} label node $gw_node1 "submariner.io/gateway=true" --overwrite
    # node/user-cl1-bbmkg-worker-8mx4k labeled

  # ${OC} get nodes -l "submariner.io/gateway=true" |& highlight "Ready"
      # NAME                          STATUS   ROLES    AGE     VERSION
      # ip-10-0-89-164.ec2.internal   Ready    worker   5h14m   v1.14.6+c07e432da
  wait_for_all_nodes_ready

  echo -e "\n# Show Submariner Gateway Nodes: \n"
  ${OC} describe nodes -l submariner.io/gateway=true

}

# ------------------------------------------

function gateway_label_all_nodes_external_ip() {
### Adding submariner gateway label to all worker nodes with an External-IP ###
  trap_to_debug_commands;

  local external_ips
  external_ips="`mktemp`_external_ips"

  ${OC} wait --timeout=3m --for=condition=ready nodes -l node-role.kubernetes.io/worker

  watch_and_retry "get_worker_nodes_with_external_ip" 5m || external_ips=NONE

  ${OC} get nodes -o wide

  if [[ "$external_ips" = NONE ]] ; then
    failed_machines=$(${OC} get Machine -A -o jsonpath='{.items[?(@.status.phase!="Running")].metadata.name}')

    FATAL "EXTERNAL-IP was not created yet. Please check if \"prep_for_subm.sh\" script had errors.
    ${failed_machines:+ Failed Machines: \n$(${OC} get Machine -A -o wide)}"
  fi

  local gw_nodes
  gw_nodes=$(get_worker_nodes_with_external_ip)

  TITLE "Adding submariner gateway label to all worker nodes with an External-IP: $gw_nodes"
    # gw_nodes: user-cl1-bbmkg-worker-8mx4k

  for node in $gw_nodes; do
    echo -e "\n# TODO: Run only If there's no Gateway label already"
    ${OC} label node $node "submariner.io/gateway=true" --overwrite
      # node/user-cl1-bbmkg-worker-8mx4k labeled
  done

  #${OC} get nodes -l "submariner.io/gateway=true" |& highlight "Ready"
    # NAME                          STATUS   ROLES    AGE     VERSION
    # ip-10-0-89-164.ec2.internal   Ready    worker   5h14m   v1.14.6+c07e432da
  wait_for_all_nodes_ready

  echo -e "\n# Show Submariner Gateway Nodes: \n"
  ${OC} describe nodes -l submariner.io/gateway=true
}

# ------------------------------------------

function configure_images_prune_cluster_a() {
  PROMPT "Configure Garbage Collection and Registry Images Prune on OCP cluster A"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  configure_ocp_garbage_collection_and_images_prune
}

# ------------------------------------------

function configure_images_prune_cluster_b() {
  PROMPT "Configure Garbage Collection and Registry Images Prune on OSP cluster B"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  configure_ocp_garbage_collection_and_images_prune
}

# ------------------------------------------

function configure_images_prune_cluster_c() {
  PROMPT "Configure Garbage Collection and Registry Images Prune on cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  configure_ocp_garbage_collection_and_images_prune
}

# ------------------------------------------

function configure_ocp_garbage_collection_and_images_prune() {
### function to set garbage collection on all cluster nodes
  trap_to_debug_commands;

  TITLE "Setting garbage collection on all OCP cluster nodes"

  cat <<EOF | ${OC} apply -f -
  apiVersion: machineconfiguration.openshift.io/v1
  kind: KubeletConfig
  metadata:
    name: garbage-collector-kubeconfig
  spec:
    machineConfigPoolSelector:
      matchLabels:
        custom-kubelet: small-pods
    kubeletConfig:
      evictionSoft:
        memory.available: "500Mi"
        nodefs.available: "10%"
        nodefs.inodesFree: "5%"
        imagefs.available: "15%"
        imagefs.inodesFree: "10%"
      evictionSoftGracePeriod:
        memory.available: "1m30s"
        nodefs.available: "1m30s"
        nodefs.inodesFree: "1m30s"
        imagefs.available: "1m30s"
        imagefs.inodesFree: "1m30s"
      evictionHard:
        memory.available: "200Mi"
        nodefs.available: "5%"
        nodefs.inodesFree: "4%"
        imagefs.available: "10%"
        imagefs.inodesFree: "5%"
      evictionPressureTransitionPeriod: 0s
      imageMinimumGCAge: 5m
      imageGCHighThresholdPercent: 80
      imageGCLowThresholdPercent: 75
EOF

  TITLE "Setting ContainerRuntimeConfig limits on all OCP cluster nodes"

  cat <<EOF | ${OC} apply -f -
  apiVersion: machineconfiguration.openshift.io/v1
  kind: ContainerRuntimeConfig
  metadata:
   name: overlay-size
  spec:
   machineConfigPoolSelector:
     matchLabels:
       custom-crio: overlay-size
   containerRuntimeConfig:
     pidsLimit: 2048
     logLevel: debug
     overlaySize: 8G
     log_size_max: 52428800
EOF

  TITLE "Enable Image Pruner policy - to delete unused images from registry:"

  ${OC} patch imagepruner.imageregistry/cluster --patch '{"spec":{"suspend":false}}' --type=merge
    # imagepruner.imageregistry.operator.openshift.io/cluster patched

  ${OC} wait imagepruner --timeout=10s --for=condition=available cluster
    # imagepruner.imageregistry.operator.openshift.io/cluster condition met

  ${OC} describe imagepruner.imageregistry.operator.openshift.io

  TITLE "List all images in all pods:"
  ${OC} get pods -A -o jsonpath="{..imageID}" |tr -s '[[:space:]]' '\n' | sort | uniq -c | awk '{print $2}'
}

# ------------------------------------------

function configure_custom_registry_cluster_a() {
  PROMPT "Using custom Registry for ACM and Submariner images on OCP cluster A"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  configure_cluster_custom_registry_secrets

  export KUBECONFIG="${KUBECONF_HUB}"
  configure_cluster_custom_registry_mirror

}

# ------------------------------------------

function configure_custom_registry_cluster_b() {
  PROMPT "Using custom Registry for ACM and Submariner images on OSP cluster B"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  configure_cluster_custom_registry_secrets

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  configure_cluster_custom_registry_mirror

}

# ------------------------------------------

function configure_custom_registry_cluster_c() {
  PROMPT "Using custom Registry for ACM and Submariner images on cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  configure_cluster_custom_registry_secrets

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  configure_cluster_custom_registry_mirror

}

# ------------------------------------------

function configure_cluster_custom_registry_secrets() {
### Configure access to external docker registry
  trap '' DEBUG # DONT trap_to_debug_commands

  wait_for_all_machines_ready || :
  wait_for_all_nodes_ready || :

  (
    # ocp_usr=$(${OC} whoami | tr -d ':')
    ocp_token=$(${OC} whoami -t)

    TITLE "Configure OCP registry local secret"

    local ocp_registry_url
    ocp_registry_url=$(${OC} registry info --internal)

    create_docker_registry_secret "$ocp_registry_url" "$OCP_USR" "$ocp_token" "$SUBM_NAMESPACE"

    # Do not ${OC} logout - it will cause authentication error pulling images during join command
  )

  TITLE "Prune old registry images associated with mirror registry (Brew): https://${BREW_REGISTRY}"
  ${OC} adm prune images --registry-url=https://${BREW_REGISTRY} --force-insecure --confirm || :

}

# ------------------------------------------

function configure_cluster_custom_registry_mirror() {
### Configure a mirror server on the cluster registry
  trap '' DEBUG # DONT trap_to_debug_commands

  ${OC} wait --timeout=5m --for=condition=Available clusteroperators authentication kube-apiserver
  ${OC} wait --timeout=5m --for='condition=Progressing=False' clusteroperators authentication kube-apiserver
  ${OC} wait --timeout=5m --for='condition=Degraded=False' clusteroperators authentication kube-apiserver || :

  ${OC} get clusteroperators authentication kube-apiserver

  local ocp_registry_url
  ocp_registry_url=$(${OC} registry info --internal)
  local local_registry_path="${ocp_registry_url}/${SUBM_NAMESPACE}"

  TITLE "Add OCP Registry mirror for ACM and Submariner:"

  create_docker_registry_secret "$BREW_REGISTRY" "$REGISTRY_USR" "$REGISTRY_PWD" "$SUBM_NAMESPACE"

  create_docker_registry_secret "$BREW_REGISTRY" "$REGISTRY_USR" "$REGISTRY_PWD" "$ACM_NAMESPACE"

  add_acm_registry_mirror_to_ocp_node "master" "${local_registry_path}" || :
  add_acm_registry_mirror_to_ocp_node "worker" "${local_registry_path}" || :

  wait_for_all_machines_ready || :
  wait_for_all_nodes_ready || :

  TITLE "Show OCP Registry (machine-config encoded) on master nodes:"
  ${OC} get mc 99-master-submariner-registries -o json | jq -r '.spec.config.storage.files[0].contents.source' | awk -F ',' '{print $2}' || :

  TITLE "Show OCP Registry (machine-config encoded) on worker nodes:"
  ${OC} get mc 99-worker-submariner-registries -o json | jq -r '.spec.config.storage.files[0].contents.source' | awk -F ',' '{print $2}' || :

}

# ------------------------------------------

function add_acm_registry_mirror_to_ocp_node() {
### Helper function to add OCP registry mirror for ACM and Submariner on all master or all worker nodes
  trap_to_debug_commands

  # set registry variables
  local node_type="$1" # master or worker
  # local registry_url="$2"
  local local_registry_path="$2"

  reg_values="
  node_type = $node_type
  local_registry_path = $local_registry_path"

  if [[ -z "$local_registry_path" ]] || [[ ! "$node_type" =~ ^(master|worker)$ ]]; then
    FATAL "Expected Openshift Registry values are missing: $reg_values"
  else
    TITLE "Adding Submariner registry mirror to all OCP cluster nodes"
    echo -e "$reg_values"
  fi

  config_source=$(cat <<EOF | raw_to_url_encode
  [[registry]]
    prefix = ""
    location = "${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX}"
    mirror-by-digest-only = false
    insecure = false
    blocked = false

    [[registry.mirror]]
      location = "${local_registry_path}"
      insecure = false

    [[registry.mirror]]
      location = "${BREW_REGISTRY}/${REGISTRY_IMAGE_PREFIX}"
      insecure = false

  [[registry]]
    prefix = ""
    location = "${STAGING_REGISTRY}/${REGISTRY_IMAGE_PREFIX}"
    mirror-by-digest-only = false
    insecure = false
    blocked = false

    [[registry.mirror]]
      location = "${local_registry_path}"
      insecure = false

    [[registry.mirror]]
      location = "${BREW_REGISTRY}/${REGISTRY_IMAGE_PREFIX}"
      insecure = false

  [[registry]]
    prefix = ""
    location = "${VPN_REGISTRY}"
    mirror-by-digest-only = false
    insecure = false
    blocked = false

    [[registry.mirror]]
      location = "${BREW_REGISTRY}"
      insecure = false

  [[registry]]
    prefix = ""
    location = "${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}"
    mirror-by-digest-only = false
    insecure = false
    blocked = false

    [[registry.mirror]]
      location = "${local_registry_path}"
      insecure = false

    [[registry.mirror]]
      location = "${BREW_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}"
      insecure = false

  [[registry]]
    prefix = ""
    location = "${STAGING_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}"
    mirror-by-digest-only = false
    insecure = false
    blocked = false

    [[registry.mirror]]
      location = "${local_registry_path}"
      insecure = false

    [[registry.mirror]]
      location = "${BREW_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}"
      insecure = false

  [[registry]]
    prefix = ""
    location = "registry.access.redhat.com/openshift4/ose-oauth-proxy"
    mirror-by-digest-only = true
    insecure = false
    blocked = false

    [[registry.mirror]]
      location = "registry.redhat.io/openshift4/ose-oauth-proxy"
      insecure = false
EOF
  )

  TITLE "Enabling auto-reboot of ${node_type} when changing Machine Config Pool:"
  ${OC} patch --type=merge --patch='{"spec":{"paused":false}}' machineconfigpool/${node_type}

  local ocp_version
  ocp_version=$(${OC} version | awk '/Server Version/ { print $3 }')
  echo "# Checking API ignition version for OCP version: $ocp_version"

  ignition_version=$(${OC} extract -n openshift-machine-api secret/worker-user-data --keys=userData --to=- | grep -oP '(?s)(?<=version":")[0-9\.]+(?=")')

  TITLE "Updating Registry in ${node_type} Machine configuration, via OCP API Ignition version: $ignition_version"

  local nodes_conf
  nodes_conf="`mktemp`_${node_type}.yaml"

  cat <<-EOF > $nodes_conf
  apiVersion: machineconfiguration.openshift.io/v1
  kind: MachineConfig
  metadata:
    labels:
      machineconfiguration.openshift.io/role: ${node_type}
    name: 99-${node_type}-submariner-registries
  spec:
    config:
      ignition:
        version: ${ignition_version}
      storage:
        files:
        - contents:
            source: data:text/plain,${config_source}
          filesystem: root
          mode: 0420
          path: /etc/containers/registries.conf.d/submariner-registries.conf
EOF

  ${OC} apply --dry-run='server' -f $nodes_conf | highlight "unchanged" \
  || ${OC} apply -f $nodes_conf

}

# ------------------------------------------

function upload_submariner_images_to_registry_cluster_a() {
# Upload custom images to the registry - OCP cluster A (public)
  PROMPT "Upload custom images to the registry of cluster A"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"

  upload_submariner_images_to_registry "$SUBM_VER_TAG"
}

# ------------------------------------------

function upload_submariner_images_to_registry_cluster_b() {
# Upload custom images to the registry - OSP cluster B (on-prem)
  PROMPT "Upload custom images to the registry of cluster B"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  upload_submariner_images_to_registry "$SUBM_VER_TAG"
}

# ------------------------------------------

function upload_submariner_images_to_registry_cluster_c() {
# Upload custom images to the registry - OSP cluster C
  PROMPT "Upload custom images to the registry of cluster C"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  upload_submariner_images_to_registry "$SUBM_VER_TAG"
}

# ------------------------------------------

function upload_submariner_images_to_registry() {
# Join Submariner member - of current cluster kubeconfig
  trap_to_debug_commands;

  local image_tag="${1:-$SUBM_VER_TAG}"

  # Fix the $image_tag value for custom images
  set_subm_version_tag_var "image_tag"

  # [[ -x "$(command -v subctl)" ]] || FATAL "No SubCtl installation found. Try to run again with option '--subctl-version'"
  # local image_tag="$(subctl version | awk '{print $3}')"

  TITLE "Overriding submariner images with custom images from mirror registry (Brew): \
  \n# Source registry: ${BREW_REGISTRY}/${REGISTRY_IMAGE_IMPORT_PATH} \
  \n# Images version tag: ${image_tag}"

  create_namespace "$SUBM_NAMESPACE"

  for img in \
    $SUBM_IMG_GATEWAY \
    $SUBM_IMG_ROUTE \
    $SUBM_IMG_NETWORK \
    $SUBM_IMG_LIGHTHOUSE \
    $SUBM_IMG_COREDNS \
    $SUBM_IMG_GLOBALNET \
    $SUBM_IMG_OPERATOR \
    $SUBM_IMG_BUNDLE \
    ; do
      local img_source="${BREW_REGISTRY}/${REGISTRY_IMAGE_IMPORT_PATH}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}-${img}:${image_tag}"
      echo -e "\n# Importing image from a mirror OCP registry: ${img_source} \n"

      local cmd="${OC} import-image -n ${SUBM_NAMESPACE} ${img}:${image_tag} --from=${img_source} --confirm"

      watch_and_retry "$cmd" 3m "Image Name:\s+${img}:${image_tag}"
  done

}

# ------------------------------------------

function run_subctl_join_on_cluster_a() {
# Join Submariner member - OCP cluster A (public)
  PROMPT "Joining cluster A to Submariner Broker"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  run_subctl_join_cmd_from_file "${SUBCTL_JOIN_CLUSTER_A_FILE}"
}

# ------------------------------------------

function run_subctl_join_on_cluster_b() {
# Join Submariner member - OSP cluster B (on-prem)
  PROMPT "Joining cluster B to Submariner Broker"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  run_subctl_join_cmd_from_file "${SUBCTL_JOIN_CLUSTER_B_FILE}"

}

# ------------------------------------------

function run_subctl_join_on_cluster_c() {
# Join Submariner member - cluster C (on-prem)
  PROMPT "Joining cluster C to Submariner Broker"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  run_subctl_join_cmd_from_file "${SUBCTL_JOIN_CLUSTER_C_FILE}"

}

# ------------------------------------------

function run_subctl_join_cmd_from_file() {
# Join Submariner member - of current cluster kubeconfig
  trap_to_debug_commands;

  echo "# Read subctl join command from file: $1"
  local JOIN_CMD
  JOIN_CMD="$(< $1)"

  cd ${WORKDIR}

  # Process:
  #
  # 1) Loads the broker-info.subm file.
  # 2) Asks the user for any missing information.
  # 3) Deploys the operator.
  # 4) Finds the CIDRs.
  # 5) Creates the Submariner CR (for the operator).
  # 6) Adds the CR to the cluster.
  #
  # Note: You don’t need to specify the CIDRs - subctl determines them on its own.
  # The user can specify them if necessary, and subctl will use that information
  # (warning the user if it doesn’t match what it determined).
  #
  # For example:
  # ./bin/subctl join --operator-image submariner-operator:local --kubeconfig \
  # ~/automation/ocp-install/ocpup/.config/cl1/auth/kubeconfig --clusterid cluster3 \
  # --repository local --version local broker-info.subm
  #

  # export KUBECONFIG="${KUBECONFIG}:${KUBECONF_HUB}"
  ${OC} config view

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"
  TITLE "Executing SubCtl Join command on $cluster_name: \n# ${JOIN_CMD}"

  $JOIN_CMD

}

# ------------------------------------------

function test_submariner_resources_cluster_a() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  test_submariner_resources_status
}

# ------------------------------------------

function test_submariner_resources_cluster_b() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  test_submariner_resources_status
}

# ------------------------------------------

function test_submariner_resources_cluster_c() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  test_submariner_resources_status
}

# ------------------------------------------

function test_submariner_resources_status() {
# Check submariner-gateway on the Operator pod
  trap_to_debug_commands;

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"
  local submariner_status=UP

  PROMPT "Testing that Submariner CatalogSource, CRDs and resources were created on cluster ${cluster_name}"

  ${OC} get catalogsource -n ${SUBM_NAMESPACE} --ignore-not-found

  cmd="${OC} get catalogsource -n ${SUBM_NAMESPACE} ${SUBM_CATALOG} -o jsonpath='{.status.connectionState.lastObservedState}'"
  watch_and_retry "$cmd" 5m "READY" || FATAL "Submariner CatalogSource '${SUBM_CATALOG}' was not created in ${SUBM_NAMESPACE}"

  ${OC} get crds | grep submariners || submariner_status=DOWN
      # ...
      # submariners.submariner.io                                   2019-11-28T14:09:56Z

  ${OC} get namespace ${SUBM_NAMESPACE} -o json  || submariner_status=DOWN

  ${OC} get Submariner -n ${SUBM_NAMESPACE} -o yaml || submariner_status=DOWN

  ${OC} get all -n ${SUBM_NAMESPACE} --show-labels |& (! highlight "Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|No resources found") \
  || submariner_status=DOWN

  echo -e "\n# TODO: consider checking for 'Terminating' pods"

  if [[ "$submariner_status" = DOWN ]] ; then
    echo "### Potential Bugs ###"

    BUG "Globalnet pod might have terminated after deployment" \
    "No workaround, ignore ERROR state (Globalnet pod will be restarted)" \
    "https://github.com/submariner-io/submariner/issues/903"

    BUG "Submariner operator failed to provision the Cluster CRD" \
    "No workaround yet" \
    "https://bugzilla.redhat.com/show_bug.cgi?id=1921824"

    FATAL "Submariner installation failure occurred on $cluster_name.
    Resources/CRDs were not installed, or Submariner pods have crashed."
  fi

}

# ------------------------------------------

function test_public_ip_on_gateway_node() {
# Testing that Submariner Gateway node received public (external) IP
  PROMPT "Testing that Submariner Gateway node received public (external) IP"
  trap_to_debug_commands;

  # Should be run on the Broker cluster
  export KUBECONFIG="${KUBECONF_HUB}"

  local public_ip
  public_ip=$(get_external_ips_of_worker_nodes)
  TITLE "Before VM reboot - Gateway public (external) IP should be: $public_ip"

  BUG "When upgrading Submariner 0.8 to 0.9 - Lighthouse replica-set may fail to start" \
  "No workaround" \
  "https://bugzilla.redhat.com/show_bug.cgi?id=1951587"

  verify_gateway_public_ip "$public_ip"

}

# ------------------------------------------

function test_disaster_recovery_of_gateway_nodes() {
# Check that submariner tunnel works if broker nodes External-IPs (on gateways) is changed
  PROMPT "Testing Disaster Recovery: Reboot Submariner-Gateway VM, to verify re-allocation of public (external) IP"
  trap_to_debug_commands;

  aws --version || FATAL "AWS-CLI is missing. Try to run again with option '--config-aws-cli'"

  # Should be run on the Broker cluster
  export KUBECONFIG="${KUBECONF_HUB}"

  local ocp_infra_id
  ocp_infra_id="$(${OC} get -o jsonpath='{.status.infrastructureName}{"\n"}' infrastructure cluster)"
  # e.g. nmanos-aws-devcluster-dzzxk

  TITLE "Get all AWS running VMs, that were assigned as 'submariner-gw' in OCP cluster $CLUSTER_A_NAME (InfraID '${ocp_infra_id}')"

  local gateway_aws_instance_ids
  gateway_aws_instance_ids=$(aws ec2 describe-instances --filters \
  Name=tag:Name,Values=${ocp_infra_id}-submariner-gw-* \
  Name=instance-state-name,Values=running \
  --output text --query Reservations[*].Instances[*].InstanceId \
   | tr '\r\n' ' ')

  [[ -n "$gateway_aws_instance_ids" ]] || \
  FATAL "No running VM instances of '${ocp_infra_id}-submariner-gw' in OCP cluster $CLUSTER_A_NAME. \n\
  Did you skip OCP preparations with --skip-ocp-setup ?"

  echo -e "\n# Stopping all AWS VMs of 'submariner-gw' in OCP cluster $CLUSTER_A_NAME: [${gateway_aws_instance_ids}]"
  aws ${DEBUG_FLAG} ec2 stop-instances --force --instance-ids $gateway_aws_instance_ids || :
  cmd="aws ec2 describe-instances --instance-ids $gateway_aws_instance_ids --output text &> '$TEMP_FILE'"
  watch_and_retry "$cmd ; grep 'STATE' $TEMP_FILE" 3m "stopped" || :

  cat "$TEMP_FILE"

  echo -e "\n# Starting all AWS VMs of 'submariner-gw' in OCP cluster $CLUSTER_A_NAME: [$gateway_aws_instance_ids]"
  aws ${DEBUG_FLAG} ec2 start-instances --instance-ids $gateway_aws_instance_ids || :
  cmd="aws ec2 describe-instances --instance-ids $gateway_aws_instance_ids --output text &> '$TEMP_FILE'"
  watch_and_retry "$cmd ; grep 'STATE' $TEMP_FILE" 3m "running" || aws_reboot=FAILED

  cat "$TEMP_FILE"

  if [[ "$aws_reboot" = FAILED ]] ; then
      FATAL "AWS-CLI reboot VMs of 'submariner-gw' in OCP cluster $CLUSTER_A_NAME has failed"
  fi

}

# ------------------------------------------

function test_renewal_of_gateway_and_public_ip() {
# Testing that Submariner Gateway was re-created with new public IP
  PROMPT "Testing that Submariner Gateway was re-created with new public IP"
  trap_to_debug_commands;

  # Should be run on the Broker cluster
  export KUBECONFIG="${KUBECONF_HUB}"

  TITLE "Watching Submariner Gateway pod - It should create new Gateway:"

  local active_gateway_pod
  export_variable_name_of_active_gateway_pod "active_gateway_pod"

  local regex="All controllers stopped or exited"
  # Watch submariner-gateway pod logs for 200 (10 X 20) seconds
  watch_pod_logs "$active_gateway_pod" "${SUBM_NAMESPACE}" "$regex" 10 || :

  local public_ip
  public_ip=$(get_external_ips_of_worker_nodes)
  echo -e "\n\n# The new Gateway public (external) IP should be: $public_ip \n"
  verify_gateway_public_ip "$public_ip"

}

# ------------------------------------------

function export_variable_name_of_active_gateway_pod() {
# Set the variable value for the active gateway pod
  # trap_to_debug_commands;

  # Get variable name
  local var_name="${1}"

  # Optional: Do not print detailed output (silent echo)
  local silent="${2}"

  local gateways_output
  gateways_output="`mktemp`_gateways"

  [[ "$silent" =~ ^(y|yes)$ ]] || \
  TITLE "Wait for Submariner active gateway, and set it into variable '${var_name}'"

  [[ -x "$(command -v subctl)" ]] || FATAL "No SubCtl installation found. Try to run again with option '--subctl-version'"

  # Wait (silently) for an active gateway node
  watch_and_retry "subctl show gateways &> $gateways_output ; grep 'active' $gateways_output" 3m || :

  [[ "$silent" =~ ^(y|yes)$ ]] || \
  TITLE "Show Submariner Gateway nodes, and get the active one"

  [[ "$silent" =~ ^(y|yes)$ ]] || \
  cat $gateways_output |& highlight "active"

  local active_gateway_node
  active_gateway_node=$(cat $gateways_output | awk '/active/ {print $1}')

  # Define label for the search of a gateway pod
  local gw_label='app=submariner-gateway'
  # For SubCtl <= 0.8 : 'app=submariner-engine' is expected as the Gateway pod label
  [[ $(subctl version | grep --invert-match "v0.8") ]] || gw_label="app=submariner-engine"

  [[ "$silent" =~ ^(y|yes)$ ]] || \
  TITLE "Find Submariner Gateway pod that runs on the active node: $active_gateway_node"
  ${OC} get pod -n ${SUBM_NAMESPACE} -l $gw_label -o wide > $gateways_output

  [[ "$silent" =~ ^(y|yes)$ ]] || \
  cat $gateways_output

  local gw_id
  gw_id="$(grep "$active_gateway_node" "$gateways_output" | cut -d ' ' -f 1)"

  [[ "$silent" =~ ^(y|yes)$ ]] || \
  cat $gateways_output | highlight "${gw_id}"

  [[ "$silent" =~ ^(y|yes)$ ]] || \
  echo "# Eval and export the variable '${var_name}=${gw_id}'"

  local eval_cmd="export ${var_name}=${gw_id}"
  eval $eval_cmd
}

# ------------------------------------------

function verify_gateway_public_ip() {
# sub-function for test_disaster_recovery_of_gateway_nodes functions
  trap_to_debug_commands;

  local public_ip="$1"

  # Show worker node EXTERNAL-IP
  ${OC} get nodes -l node-role.kubernetes.io/worker -o wide |& highlight "EXTERNAL-IP"

  # Show Submariner Gateway public_ip
  cmd="${OC} describe Gateway -n ${SUBM_NAMESPACE} | grep -C 12 'Local Endpoint:'"
  local regex="public_ip:\s*${public_ip}"
  # Attempt cmd for 3 minutes (grepping for 'Local Endpoint:' and print 12 lines afterwards), looking for Public IP
  watch_and_retry "$cmd" 3m "$regex"

}

# ------------------------------------------

function test_cable_driver_cluster_a() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  test_submariner_cable_driver
}

# ------------------------------------------

function test_cable_driver_cluster_b() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  test_submariner_cable_driver
}

# ------------------------------------------

function test_cable_driver_cluster_c() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  test_submariner_cable_driver
}

# ------------------------------------------

function test_submariner_cable_driver() {
# Check submariner cable driver
  trap_to_debug_commands;

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Testing Cable-Driver ${subm_cable_driver:+\"$subm_cable_driver\" }on ${cluster_name}"

  export_variable_name_of_active_gateway_pod "active_gateway_pod"

  local regex="(cable.* started|Status:connected)"
  # Watch submariner-gateway pod logs for 200 (10 X 20) seconds
  watch_pod_logs "$active_gateway_pod" "${SUBM_NAMESPACE}" "$regex" 10

}

# ------------------------------------------

function test_ha_status_cluster_a() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  test_ha_status
}

# ------------------------------------------

function test_ha_status_cluster_b() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  test_ha_status
}

# ------------------------------------------

function test_ha_status_cluster_c() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  test_ha_status
}

# ------------------------------------------

function test_ha_status() {
# Check submariner HA status
  trap_to_debug_commands;

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"
  local submariner_status=UP

  PROMPT "Check HA status of Submariner and Gateway resources on ${cluster_name}"

  ${OC} describe configmaps -n openshift-dns || submariner_status=DOWN

  ${OC} get clusters -n ${SUBM_NAMESPACE} -o wide || submariner_status=DOWN

  echo -e "\n# TODO: Need to get current cluster ID"
  #${OC} describe cluster "${cluster_id}" -n ${SUBM_NAMESPACE} || submariner_status=DOWN

  local cmd="${OC} describe Gateway -n ${SUBM_NAMESPACE} &> '$TEMP_FILE'"

  TITLE "Checking 'Gateway' resource status"
  local regex="Ha Status:\s*active"
  # Attempt cmd for 3 minutes (grepping for 'Connections:' and print 30 lines afterwards), looking for HA active
  watch_and_retry "$cmd ; grep -E '$regex' $TEMP_FILE" 3m || :
  cat $TEMP_FILE |& highlight "$regex" || submariner_status=DOWN

  TITLE "Checking 'Submariner' resource status"
  local regex="Status:\s*connect"
  # Attempt cmd for 3 minutes (grepping for 'Connections:' and print 30 lines afterwards), looking for Status connected
  watch_and_retry "$cmd ; grep -E '$regex' $TEMP_FILE" 3m || :
  # cat $TEMP_FILE |& highlight "Status:\s*connected" || submariner_status=DOWN
  cat $TEMP_FILE |& (! highlight "Status Failure\s*\w+") || submariner_status=DOWN

  if [[ "$submariner_status" = DOWN ]] ; then
    FATAL "Submariner HA failure occurred."
  fi

}

# ------------------------------------------

function test_submariner_connection_cluster_a() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  test_submariner_connection_established
}

# ------------------------------------------

function test_submariner_connection_cluster_b() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  test_submariner_connection_established
}

# ------------------------------------------

function test_submariner_connection_cluster_c() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  test_submariner_connection_established
}

# ------------------------------------------

function test_submariner_connection_established() {
# Check submariner cable driver
  trap_to_debug_commands;

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Check Submariner Gateway established connection on ${cluster_name}"

  export_variable_name_of_active_gateway_pod "active_gateway_pod"

  TITLE "Tailing logs in Submariner-Gateway pod [$active_gateway_pod] to verify connection between clusters"
  # ${OC} logs $active_gateway_pod -n ${SUBM_NAMESPACE} | grep "received packet" -C 2 || submariner_status=DOWN

  local regex="(Successfully installed Endpoint cable .* remote IP|Status:connected|CableName:.*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)"
  # Watch submariner-gateway pod logs for 400 (20 X 20) seconds
  watch_pod_logs "$active_gateway_pod" "${SUBM_NAMESPACE}" "$regex" 20 || submariner_status=DOWN

  ${OC} describe pod $active_gateway_pod -n ${SUBM_NAMESPACE} || submariner_status=DOWN

  [[ "$submariner_status" != DOWN ]] || FATAL "Submariner clusters are not connected."
}

# ------------------------------------------

function test_ipsec_status_cluster_a() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  test_ipsec_status
}

# ------------------------------------------

function test_ipsec_status_cluster_b() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  test_ipsec_status
}

# ------------------------------------------

function test_ipsec_status_cluster_c() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  test_ipsec_status
}

# ------------------------------------------

function test_ipsec_status() {
# Check submariner cable driver
  trap_to_debug_commands;

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Testing IPSec Status of the Active Gateway in ${cluster_name}"

  export_variable_name_of_active_gateway_pod "active_gateway_pod"

  : > "$TEMP_FILE"

  TITLE "Verify IPSec status on the active Gateway pod [${active_gateway_pod}]:"
  ${OC} exec $active_gateway_pod -n ${SUBM_NAMESPACE} -- bash -c "ipsec status" |& tee -a "$TEMP_FILE" || :

  local loaded_con
  loaded_con="`grep "Total IPsec connections:" "$TEMP_FILE" | grep -Po "loaded \K([0-9]+)" | tail -1`"
  local active_con
  active_con="`grep "Total IPsec connections:" "$TEMP_FILE" | grep -Po "active \K([0-9]+)" | tail -1`"

  if [[ ! "$active_con" = "$loaded_con" ]] ; then
    FATAL "IPSec tunnel error: $loaded_con Loaded connections, but only $active_con Active"
  fi

}

# ------------------------------------------

function test_globalnet_status_cluster_a() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  test_globalnet_status
}

# ------------------------------------------

function test_globalnet_status_cluster_b() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  test_globalnet_status
}

# ------------------------------------------

function test_globalnet_status_cluster_c() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  test_globalnet_status
}

# ------------------------------------------

function test_globalnet_status() {
  # Check Globalnet controller pod status
  trap_to_debug_commands;

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Testing GlobalNet controller, Global IPs and Endpoints status on ${cluster_name}"

  # globalnet_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-globalnet -o jsonpath="{.items[0].metadata.name}")
  # [[ -n "$globalnet_pod" ]] || globalnet_status=DOWN
  globalnet_pod="`get_running_pod_by_label 'app=submariner-globalnet' "$SUBM_NAMESPACE" `"


  TITLE "Tailing logs in GlobalNet pod [$globalnet_pod] to verify that Global IPs were allocated to cluster services"

  local regex="(Allocating globalIp|Starting submariner-globalnet)"
  # Watch globalnet pod logs for 200 (10 X 20) seconds
  watch_pod_logs "$globalnet_pod" "${SUBM_NAMESPACE}" "$regex" 10 || globalnet_status=DOWN

  TITLE "Tailing logs in GlobalNet pod [$globalnet_pod], to see if Endpoints were removed (due to Submariner Gateway restarts)"

  regex="remove endpoint"
  (! watch_pod_logs "$globalnet_pod" "${SUBM_NAMESPACE}" "$regex" 1 "1s") || globalnet_status=DOWN

  [[ "$globalnet_status" != DOWN ]] || FATAL "GlobalNet pod error on ${SUBM_NAMESPACE} namespace, or globalIp / Endpoints failure occurred."
}

# ------------------------------------------

function export_nginx_default_namespace_managed_cluster() {
  PROMPT "Create ServiceExport for $NGINX_CLUSTER_BC on managed cluster, without specifying Namespace"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_MANAGED}"

  configure_namespace_for_submariner_tests

  local current_namespace
  current_namespace="$(${OC} config view -o jsonpath='{.contexts[].context.namespace}')"

  TITLE "# The ServiceExport should be created on the default Namespace '${current_namespace}', as configured in KUBECONFIG:
  \n# $KUBECONFIG"

  export_service_in_lighthouse "$NGINX_CLUSTER_BC"
}

# ------------------------------------------

function export_nginx_headless_namespace_managed_cluster() {
  PROMPT "Create ServiceExport for the HEADLESS $NGINX_CLUSTER_BC on managed cluster, in the Namespace '$HEADLESS_TEST_NS'"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_MANAGED}"

  echo "# The ServiceExport should be created on the default Namespace, as configured in KUBECONFIG:
  \n# $KUBECONFIG : ${HEADLESS_TEST_NS}"

  export_service_in_lighthouse "$NGINX_CLUSTER_BC" "$HEADLESS_TEST_NS"
}

# ------------------------------------------

function export_service_in_lighthouse() {
  trap_to_debug_commands;
  local svc_name="$1"
  local namespace="$2"

  subctl export service -h

  subctl export service "${svc_name}" ${namespace:+ -n $namespace}

  #   ${OC} ${namespace:+-n $namespace} apply -f - <<EOF
  #     apiVersion: lighthouse.submariner.io/v2alpha1
  #     kind: ServiceExport
  #     metadata:
  #       name: ${svc_name}
  # EOF

  TITLE "Wait up to 3 minutes for $svc_name to successfully sync to the broker:"

  # ${OC} rollout status --timeout=3m serviceexport "${svc_name}" ${namespace:+ -n $namespace}
  # ${OC} wait --timeout=3m --for=condition=ready serviceexport "${svc_name}" ${namespace:+ -n $namespace}
  # ${OC} wait --timeout=3m --for=condition=Valid serviceexports.multicluster.x-k8s.io/${svc_name} ${namespace:+-n $namespace}
  BUG "Rollout status failed: ServiceExport is not a registered version" \
  "Skip checking for ServiceExport creation status" \
  "https://github.com/submariner-io/submariner/issues/640"
  # Workaround:
  # Do not run this rollout status, but watch pod description:

  #local cmd="${OC} describe serviceexport $svc_name ${namespace:+-n $namespace}"
  # Workaround:
  local cmd="${OC} describe serviceexport $svc_name ${namespace:+-n $namespace}"

  # BUG:
  # local regex='Status:\s+True'
  local regex='Message:.*successfully synced'
  watch_and_retry "$cmd" 3m "$regex"

  TITLE "Show $svc_name ServiceExport status is Valid:"
  ${OC} get serviceexport "${svc_name}" ${namespace:+ -n $namespace}
  ${OC} get serviceexport $svc_name ${namespace:+-n $namespace} -o jsonpath='{.status.conditions[?(@.status=="True")].type}' | grep "Valid"

  echo "# Show $svc_name Service info:"
  ${OC} get svc "${svc_name}" ${namespace:+ -n $namespace}

  BUG "kubectl get serviceexport with '-o wide' does not show more info" \
  "Use '-o yaml' instead" \
  "https://github.com/submariner-io/submariner/issues/739"
  # Workaround:
  ${OC} get serviceexport "${svc_name}" ${namespace:+ -n $namespace} -o wide
  ${OC} get serviceexport "${svc_name}" ${namespace:+ -n $namespace} -o yaml

  echo -e "\n# Describe Lighthouse Exported Services:\n"
  ${OC} describe serviceexports --all-namespaces

}

# ------------------------------------------

function test_lighthouse_status_cluster_a() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  test_lighthouse_status
}

# ------------------------------------------

function test_lighthouse_status_cluster_b() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  test_lighthouse_status
}

# ------------------------------------------

function test_lighthouse_status_cluster_c() {
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  test_lighthouse_status
}

# ------------------------------------------

function test_lighthouse_status() {
  # Check Lighthouse (the pod for service-discovery) status
  trap_to_debug_commands;

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  PROMPT "Testing Lighthouse agent status on ${cluster_name}"

  # lighthouse_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-lighthouse-agent -o jsonpath="{.items[0].metadata.name}")
  # [[ -n "$lighthouse_pod" ]] || FATAL "Lighthouse pod was not created on ${SUBM_NAMESPACE} namespace."
  lighthouse_pod="`get_running_pod_by_label 'app=submariner-lighthouse-agent' "$SUBM_NAMESPACE" `"

  TITLE "Tailing logs in Lighthouse pod [$lighthouse_pod] to verify Service-Discovery sync with Broker"
  local regex="agent .* started"
  # Watch lighthouse pod logs for 100 (5 X 20) seconds
  watch_pod_logs "$lighthouse_pod" "${SUBM_NAMESPACE}" "$regex" 5 || FAILURE "Lighthouse status is not as expected"

  echo -e "\n# TODO: Can also test app=submariner-lighthouse-coredns  for the lighthouse DNS status"
}


# ------------------------------------------

function test_global_ip_created_for_svc_or_pod() {
  # Check that the Service or Pod was annotated with GlobalNet IP
  # Set external variable GLOBAL_IP if there's a GlobalNet IP
  trap_to_debug_commands

  obj_type="$1" # "svc" for Service, "pod" for Pod
  obj_id="$2" # Object name or id
  namespace="$3" # Optional : namespace

  cmd="${OC} describe $obj_type $obj_id ${namespace:+-n $namespace}"

  globalnet_tag='submariner.io\/globalIp'
  ipv4_regex='[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
  watch_and_retry "$cmd | grep '$globalnet_tag'" 3m "$ipv4_regex"

  $cmd | highlight "$globalnet_tag" || \
  BUG "GlobalNet annotation and IP was not set on $obj_type : $obj_id ${namespace:+(namespace : $namespace)}"

  # Set the external variable $GLOBAL_IP with the GlobalNet IP
  # GLOBAL_IP=$($cmd | grep -E "$globalnet_tag" | awk '{print $NF}')
  GLOBAL_IP=$($cmd | grep "$globalnet_tag" | grep -Eoh "$ipv4_regex")
  export GLOBAL_IP
}

# ------------------------------------------

function test_clusters_connected_by_service_ip() {
  PROMPT "After Submariner is installed:
  Identify Netshoot pod on cluster A, and Nginx service on managed cluster"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_HUB}"
  # ${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --field-selector status.phase=Running | awk 'FNR == 2 {print $1}' > "$TEMP_FILE"
  # netshoot_pod_cluster_a="$(< $TEMP_FILE)"
  netshoot_pod_cluster_a="`get_running_pod_by_label "run=${NETSHOOT_CLUSTER_A}" "$TEST_NS" `"

  echo "# NETSHOOT_CLUSTER_A: $netshoot_pod_cluster_a"
    # netshoot-785ffd8c8-zv7td

  export KUBECONFIG="${KUBECONF_MANAGED}"
  echo "${OC} get svc -l app=${NGINX_CLUSTER_BC} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')"
  # nginx_IP_cluster_bc=$(${OC} get svc -l app=${NGINX_CLUSTER_BC} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')
  ${OC} get svc -l app=${NGINX_CLUSTER_BC} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}' > "$TEMP_FILE"
  nginx_IP_cluster_bc="$(< $TEMP_FILE)"
  TITLE "Nginx service on cluster B, will be identified by its IP (without DNS from service-discovery): ${nginx_IP_cluster_bc}:${NGINX_PORT}"
    # nginx_IP_cluster_bc: 100.96.43.129

  export KUBECONFIG="${KUBECONF_HUB}"
  CURL_CMD="${TEST_NS:+-n $TEST_NS} ${netshoot_pod_cluster_a} -- curl --output /dev/null --max-time 30 --verbose ${nginx_IP_cluster_bc}:${NGINX_PORT}"

  if [[ ! "$globalnet" =~ ^(y|yes)$ ]] ; then
    PROMPT "Testing connection without GlobalNet: From Netshoot on OCP cluster A (public), to Nginx service IP on managed cluster"

    if ! ${OC} exec ${CURL_CMD} ; then
      FAILURE "Submariner connection failure${subm_cable_driver:+ (Cable-driver=$subm_cable_driver)}.
      \n Did you install clusters with overlapping CIDRs ?"
    fi

      # *   Trying 100.96.72.226:8080...
      # * TCP_NODELAY set
      # * Connected to 100.96.72.226 (100.96.72.226) port 8080 (#0)
      # > HEAD / HTTP/1.1
      # > Host: 100.96.72.226
      # > User-Agent: curl/7.65.1
      # > Accept: */*
      # >
      # * Mark bundle as not supporting multiuse
      # < HTTP/1.1 200 OK
      # < Server: nginx/1.17.6
      # < Date: Thu, 05 Dec 2019 20:54:17 GMT
      # < Content-Type: text/html
      # < Content-Length: 612
      # < Last-Modified: Tue, 19 Nov 2019 15:14:41 GMT
      # < Connection: keep-alive
      # < ETag: "5dd406e1-264"
      # < Accept-Ranges: bytes
      # <
      # * Connection #0 to host 100.96.72.226 left intact

  else
    PROMPT "Testing GlobalNet: There should be NO-connectivity if clusters A and B have Overlapping CIDRs"

    msg="# Negative Test - Clusters have Overlapping CIDRs:
    \n# Nginx internal IP (${nginx_IP_cluster_bc}:${NGINX_PORT}) on cluster B, should NOT be reachable outside cluster, if using GlobalNet."

    ${OC} exec ${CURL_CMD} |& (! highlight "Failed to connect" && FAILURE "$msg") || echo -e "$msg"
  fi
}

# ------------------------------------------

function test_clusters_connected_overlapping_cidrs() {
### Run Connectivity tests between the On-Premise and Public clusters ###
# To validate that now Submariner made the connection possible!
  trap_to_debug_commands;

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"
  PROMPT "Testing GlobalNet annotation - Nginx service on managed cluster $cluster_name should get a GlobalNet IP"

  export KUBECONFIG="${KUBECONF_MANAGED}"

  # Should fail if NGINX_CLUSTER_BC was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_global_ip_created_for_svc_or_pod svc "$NGINX_CLUSTER_BC" $TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on Nginx service (${NGINX_CLUSTER_BC}${TEST_NS:+.$TEST_NS})"
  nginx_global_ip="$GLOBAL_IP"

  PROMPT "Testing GlobalNet annotation - Netshoot pod on OCP cluster A (public) should get a GlobalNet IP"
  export KUBECONFIG="${KUBECONF_HUB}"
  # netshoot_pod_cluster_a=$(${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} \
  # --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')
  netshoot_pod_cluster_a="`get_running_pod_by_label "run=${NETSHOOT_CLUSTER_A}" "$TEST_NS" `"

  # Should fail if netshoot_pod_cluster_a was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_global_ip_created_for_svc_or_pod pod "$netshoot_pod_cluster_a" $TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on Netshoot Pod (${netshoot_pod_cluster_a}${TEST_NS:+ in $TEST_NS})"
  netshoot_global_ip="$GLOBAL_IP"

  echo -e "\n# TODO: Ping to the netshoot_global_ip"


  PROMPT "Testing GlobalNet connectivity - From Netshoot pod ${netshoot_pod_cluster_a} (IP ${netshoot_global_ip}) on cluster A
  To Nginx service on cluster B, by its Global IP: $nginx_global_ip:${NGINX_PORT}"

  export KUBECONFIG="${KUBECONF_HUB}"
  ${OC} exec ${netshoot_pod_cluster_a} ${TEST_NS:+-n $TEST_NS} \
  -- curl --output /dev/null --max-time 30 --verbose ${nginx_global_ip}:${NGINX_PORT}

  echo -e "\n# TODO: validate annotation of globalIp in the node"
}

# ------------------------------------------

function test_clusters_connected_full_domain_name() {
### Nginx service on cluster B, will be identified by its Domain Name ###
# This is to test service-discovery (Lighthouse) of NON-headless $NGINX_CLUSTER_BC service, on the default namespace

  trap_to_debug_commands;

  # Set FQDN on clusterset.local when using Service-Discovery (lighthouse)
  local nginx_cl_b_dns="${NGINX_CLUSTER_BC}${TEST_NS:+.$TEST_NS}.svc.${MULTI_CLUSTER_DOMAIN}"

  PROMPT "Testing Service-Discovery: From Netshoot pod on cluster A${TEST_NS:+ (Namespace $TEST_NS)}
  To the default Nginx service on cluster B${TEST_NS:+ (Namespace ${TEST_NS:-default})}, by DNS hostname: $nginx_cl_b_dns"

  export KUBECONFIG="${KUBECONF_HUB}"

  TITLE "Try to ping ${NGINX_CLUSTER_BC} until getting expected FQDN: $nginx_cl_b_dns (and IP)"
  echo -e "\n# TODO: Validate both GlobalIP and svc.${MULTI_CLUSTER_DOMAIN} with   ${OC} get all"
      # NAME                 TYPE           CLUSTER-IP   EXTERNAL-IP                            PORT(S)   AGE
      # service/kubernetes   clusterIP      172.30.0.1   <none>                                 443/TCP   39m
      # service/openshift    ExternalName   <none>       kubernetes.default.svc.clusterset.local   <none>    32m

  cmd="${OC} exec ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} -- ping -c 1 $nginx_cl_b_dns"
  local regex="PING ${nginx_cl_b_dns}"
  watch_and_retry "$cmd" 3m "$regex"
    # PING netshoot-cl-a-new.test-submariner-new.svc.clusterset.local (169.254.59.89)

  BUG "LibreSwan may fail here, but subctl may not warn on sub-connection problem" \
   "No workaround yet, it is caused by LibreSwan bug 1081" \
  "https://github.com/submariner-io/submariner/issues/1080"
  # No workaround yet

  TITLE "Try to CURL from ${NETSHOOT_CLUSTER_A} to ${nginx_cl_b_dns}:${NGINX_PORT} :"
  ${OC} exec ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_cl_b_dns}:${NGINX_PORT}"

  echo -e "\n# TODO: Test connectivity with https://github.com/tsliwowicz/go-wrk"

}

# ------------------------------------------

function test_clusters_cannot_connect_short_service_name() {
### Negative test for nginx_cl_b_short_dns FQDN ###

  trap_to_debug_commands;

  local nginx_cl_b_short_dns="${NGINX_CLUSTER_BC}${TEST_NS:+.$TEST_NS}"

  PROMPT "Testing Service-Discovery:
  There should be NO DNS resolution from cluster A to the local Nginx address on cluster B: $nginx_cl_b_short_dns (FQDN without \"clusterset\")"

  export KUBECONFIG="${KUBECONF_HUB}"

  msg="# Negative Test - ${nginx_cl_b_short_dns}:${NGINX_PORT} should not be reachable (FQDN without \"clusterset\")."

  ${OC} exec ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} \
  -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_cl_b_short_dns}:${NGINX_PORT}" \
  |& (! highlight "command terminated with exit code" && FATAL "$msg") || echo -e "$msg"
    # command terminated with exit code 28
}

# ------------------------------------------

function install_new_netshoot_cluster_a() {
### Install $NEW_NETSHOOT_CLUSTER_A on the $TEST_NS namespace ###

  trap_to_debug_commands;
  PROMPT "Install NEW Netshoot pod on OCP cluster A${TEST_NS:+ (Namespace $TEST_NS)}"
  export KUBECONFIG="${KUBECONF_HUB}" # Can also use --context ${CLUSTER_A_NAME} on all further oc commands

  [[ -z "$TEST_NS" ]] || create_namespace "$TEST_NS"

  ${OC} delete pod ${NEW_NETSHOOT_CLUSTER_A} --ignore-not-found ${TEST_NS:+-n $TEST_NS} || :

  ${OC} run ${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --image ${NETSHOOT_IMAGE} \
  --pod-running-timeout=5m --restart=Never -- sleep 5m

  TITLE "Wait up to 3 minutes for NEW Netshoot pod [${NEW_NETSHOOT_CLUSTER_A}] to be ready:"
  ${OC} wait --timeout=3m --for=condition=ready pod -l run=${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
  ${OC} describe pod ${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
}

# ------------------------------------------

function test_new_netshoot_global_ip_cluster_a() {
### Check that $NEW_NETSHOOT_CLUSTER_A on the $TEST_NS is annotated with GlobalNet IP ###

  trap_to_debug_commands;
  PROMPT "Testing GlobalNet annotation - NEW Netshoot pod on OCP cluster A (public) should get a GlobalNet IP"
  export KUBECONFIG="${KUBECONF_HUB}"

  # netshoot_pod=$(${OC} get pods -l run=${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} \
  # --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')
  # get_running_pod_by_label "run=${NEW_NETSHOOT_CLUSTER_A}" "${TEST_NS}"

  # Should fail if NEW_NETSHOOT_CLUSTER_A was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_global_ip_created_for_svc_or_pod pod "$NEW_NETSHOOT_CLUSTER_A" $TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on NEW Netshoot Pod (${NEW_NETSHOOT_CLUSTER_A}${TEST_NS:+ in $TEST_NS})"
}

# ------------------------------------------

function install_nginx_headless_namespace_managed_cluster() {
### Install $NGINX_CLUSTER_BC on the $HEADLESS_TEST_NS namespace ###
  trap_to_debug_commands;

  PROMPT "Install HEADLESS Nginx service on managed cluster${HEADLESS_TEST_NS:+ (Namespace $HEADLESS_TEST_NS)}"
  export KUBECONFIG="${KUBECONF_MANAGED}"

  TITLE "Creating ${NGINX_CLUSTER_BC}:${NGINX_PORT} in ${HEADLESS_TEST_NS}, using ${NGINX_IMAGE}, and disabling it's cluster-ip (with '--cluster-ip=None'):"

  install_nginx_service "${NGINX_CLUSTER_BC}" "${NGINX_IMAGE}" "${HEADLESS_TEST_NS}" "--port=${NGINX_PORT} --cluster-ip=None" || :
}

# ------------------------------------------

function test_nginx_headless_global_ip_managed_cluster() {
### Check that $NGINX_CLUSTER_BC on the $HEADLESS_TEST_NS is annotated with GlobalNet IP ###
  trap_to_debug_commands;

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"
  PROMPT "Testing GlobalNet annotation - The HEADLESS Nginx service on managed cluster $cluster_name should get a GlobalNet IP"

  if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then
    BUG "HEADLESS Service is not supported with GlobalNet" \
     "No workaround yet - Skip the whole test" \
    "https://github.com/submariner-io/lighthouse/issues/273"
    # No workaround yet
    FAILURE "Mark this test as failed, but continue"
  fi

  export KUBECONFIG="${KUBECONF_MANAGED}"

  # Should fail if NGINX_CLUSTER_BC was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_global_ip_created_for_svc_or_pod svc "$NGINX_CLUSTER_BC" $HEADLESS_TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FAILURE "GlobalNet error on the HEADLESS Nginx service (${NGINX_CLUSTER_BC}${HEADLESS_TEST_NS:+.$HEADLESS_TEST_NS})"

  echo -e "\n# TODO: Ping to the new_nginx_global_ip"
  # new_nginx_global_ip="$GLOBAL_IP"
}

# ------------------------------------------

function test_clusters_connected_headless_service_on_new_namespace() {
### Nginx service on cluster B, will be identified by its Domain Name (with service-discovery) ###

  trap_to_debug_commands;

  # Set FQDN on clusterset.local when using Service-Discovery (lighthouse)
  local nginx_headless_cl_b_dns="${NGINX_CLUSTER_BC}${HEADLESS_TEST_NS:+.$HEADLESS_TEST_NS}.svc.${MULTI_CLUSTER_DOMAIN}"

  PROMPT "Testing Service-Discovery: From NEW Netshoot pod on cluster A${TEST_NS:+ (Namespace $TEST_NS)}
  To the HEADLESS Nginx service on cluster B${HEADLESS_TEST_NS:+ (Namespace $HEADLESS_TEST_NS)}, by DNS hostname: $nginx_headless_cl_b_dns"

  if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then

    BUG "HEADLESS Service is not supported with GlobalNet" \
     "No workaround yet - Skip the whole test" \
    "https://github.com/submariner-io/lighthouse/issues/273"
    # No workaround yet - skipping test
    return

  else

    export KUBECONFIG="${KUBECONF_HUB}"

    TITLE "Try to ping HEADLESS ${NGINX_CLUSTER_BC} until getting expected FQDN: $nginx_headless_cl_b_dns (and IP)"
    echo -e "\n# TODO: Validate both GlobalIP and svc.${MULTI_CLUSTER_DOMAIN} with   ${OC} get all"
        # NAME                 TYPE           CLUSTER-IP   EXTERNAL-IP                            PORT(S)   AGE
        # service/kubernetes   clusterIP      172.30.0.1   <none>                                 443/TCP   39m
        # service/openshift    ExternalName   <none>       kubernetes.default.svc.clusterset.local   <none>    32m

    BUG "It may fail resolving Headless service host, that was previously exported (when redeploying Submariner)" \
    "No workaround yet" \
    "https://github.com/submariner-io/submariner/issues/872"

    cmd="${OC} exec ${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} -- ping -c 1 $nginx_headless_cl_b_dns"
    local regex="PING ${nginx_headless_cl_b_dns}"
    watch_and_retry "$cmd" 3m "$regex"
      # PING netshoot-cl-a-new.test-submariner-new.svc.clusterset.local (169.254.59.89)

    TITLE "Try to CURL from ${NEW_NETSHOOT_CLUSTER_A} to ${nginx_headless_cl_b_dns}:${NGINX_PORT} :"
    ${OC} exec ${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_headless_cl_b_dns}:${NGINX_PORT}"

    echo -e "\n# TODO: Test connectivity with https://github.com/tsliwowicz/go-wrk"

  fi

}

# ------------------------------------------

function test_clusters_cannot_connect_headless_short_service_name() {
### Negative test for HEADLESS nginx_cl_b_short_dns FQDN ###

  trap_to_debug_commands;

  local nginx_cl_b_short_dns="${NGINX_CLUSTER_BC}${HEADLESS_TEST_NS:+.$HEADLESS_TEST_NS}"

  PROMPT "Testing Service-Discovery:
  There should be NO DNS resolution from cluster A to the local Nginx address on cluster B: $nginx_cl_b_short_dns (FQDN without \"clusterset\")"

  export KUBECONFIG="${KUBECONF_HUB}"

  msg="# Negative Test - ${nginx_cl_b_short_dns}:${NGINX_PORT} should not be reachable (FQDN without \"clusterset\")."

  ${OC} exec ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} \
  -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_cl_b_short_dns}:${NGINX_PORT}" \
  |& (! highlight "command terminated with exit code" && FATAL "$msg") || echo -e "$msg"
    # command terminated with exit code 28

}

# ------------------------------------------

function test_subctl_show_on_merged_kubeconfigs() {
### Test subctl show command on merged kubeconfig ###
  PROMPT "Testing SubCtl show on merged kubeconfig of multiple clusters"
  trap_to_debug_commands;

  local subctl_info

  # export_active_clusters_kubeconfig

  export_merged_kubeconfigs

  subctl show versions || subctl_info=ERROR

  subctl show networks || subctl_info=ERROR

  subctl show endpoints || subctl_info=ERROR

  subctl show connections || subctl_info=ERROR

  subctl show gateways || subctl_info=ERROR

  if [[ "$subctl_info" = ERROR ]] ; then
    FAILURE "SubCtl show failed when using merged kubeconfig"
  fi

}

# ------------------------------------------

function export_merged_kubeconfigs() {
### Helper function to export all active clusters kubeconfig at once (merged) ###
  trap_to_debug_commands;

  TITLE "Exporting all active clusters kubeconfig at once (merged)"

  local merged_kubeconfigs="${KUBECONF_HUB}"
  # local active_context_names="${CLUSTER_A_NAME}"

  if [[ -s "$CLUSTER_B_YAML" ]] ; then
    echo "# Appending ${CLUSTER_B_NAME} context to \"${merged_kubeconfigs}\""
    merged_kubeconfigs="${merged_kubeconfigs}:${KUBECONF_CLUSTER_B}"
    # active_context_names="${active_context_names}|${CLUSTER_B_NAME}"
  fi

  if [[ -s "$CLUSTER_C_YAML" ]] ; then
    echo "# Appending ${CLUSTER_C_NAME} context to \"${merged_kubeconfigs}\""
    merged_kubeconfigs="${merged_kubeconfigs}:${KUBECONF_CLUSTER_C}"
    # active_context_names="${active_context_names}|${CLUSTER_C_NAME}"
  fi

  export KUBECONFIG="${merged_kubeconfigs}"
  ${OC} config get-contexts

  # echo "# Deleting all contexts except \"${active_context_names}\" from current kubeconfig:"
  # local context_changed
  #
  # ${OC} config get-contexts -o name | grep -E --invert-match "^(${active_context_names})\$" \
  # | while read -r context_name ; do
  #   echo "# Deleting kubeconfig context: $context_name"
  #   ${OC} config delete-context "${context_name}" || :
  #   context_changed=YES
  # done
  #
  # [[ -z "$context_changed" ]] || ${OC} config get-contexts
  #   #   CURRENT   NAME                  CLUSTER               AUTHINFO      NAMESPACE
  #   #   *         nmanos-cluster-a      nmanos-cluster-a      admin         default
  #   #             nmanos-cluster-c      nmanos-cluster-c      admin         default

  echo -e "\n# Current OC user: $(${OC} whoami || : )"

}

# ------------------------------------------

function test_submariner_packages() {
### Run Submariner Unit tests (mock) ###
  PROMPT "Testing Submariner Packages (Unit-Tests) with GO"
  trap_to_debug_commands;

  local project_path="$GOPATH/src/github.com/submariner-io/submariner"
  cd $project_path
  pwd

  export GO111MODULE="on"
  # export CGO_ENABLED=1 # required for go test -race
  go env

  if [[ "$create_junit_xml" =~ ^(y|yes)$ ]]; then
    echo -e "\n# Junit report to create: $PKG_JUNIT_XML \n"
    junit_params="-ginkgo.reportFile $PKG_JUNIT_XML"
  fi

  local msg="# Running unit-tests with GO in project: \n# $project_path"

  echo -e "$msg \n# Output will be printed both to stdout and to $E2E_LOG file."
  echo -e "$msg" >> "$E2E_LOG"

  go test -v -cover ./pkg/... \
  -ginkgo.v -ginkgo.trace -ginkgo.reportPassed ${junit_params} \
  | tee -a "$E2E_LOG"

}

# ------------------------------------------

function test_submariner_e2e_with_go() {
# Run E2E Tests of Submariner:
  PROMPT "Testing Submariner End-to-End tests with GO"
  trap_to_debug_commands;

  test_project_e2e_with_go \
  "$GOPATH/src/github.com/submariner-io/submariner" \
  "$E2E_JUNIT_XML"

}

# ------------------------------------------

function test_lighthouse_e2e_with_go() {
# Run E2E Tests of Lighthouse with Ginkgo
  PROMPT "Testing Lighthouse End-to-End tests with GO"
  trap_to_debug_commands;

  local test_params

  if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then
    test_params="--globalnet"
  fi

  test_project_e2e_with_go \
  "$GOPATH/src/github.com/submariner-io/lighthouse" \
  "$LIGHTHOUSE_JUNIT_XML" \
  "$test_params"

}

# ------------------------------------------

function test_project_e2e_with_go() {
# Helper function to run E2E Tests of Submariner repo with Ginkgo
  trap_to_debug_commands;
  local e2e_project_path="$1"
  local junit_output_file="$2"
  local test_params="$3"

  cd "$e2e_project_path"
  pwd

  TITLE "Set E2E context for the active clusters"
  export KUBECONFIG="${KUBECONF_HUB}"
  local e2e_dp_context
  e2e_dp_context="--dp-context $(${OC} config current-context)"

  if [[ -s "$CLUSTER_B_YAML" ]] ; then
    echo "# Appending \"${CLUSTER_B_NAME}\" to current E2E context (${e2e_dp_context})"
    export KUBECONFIG="${KUBECONF_CLUSTER_B}"
    e2e_dp_context="${e2e_dp_context} --dp-context $(${OC} config current-context)"
  fi

  if [[ -s "$CLUSTER_C_YAML" ]] ; then
    echo "# Appending \"${CLUSTER_C_NAME}\" to current E2E context (${e2e_dp_context})"
    export KUBECONFIG="${KUBECONF_CLUSTER_C}"
    e2e_dp_context="${e2e_dp_context} --dp-context $(${OC} config current-context)"
  fi

  echo "E2E context: ${e2e_dp_context}"

  ### Set E2E $test_params and $junit_params" ###

  test_params="$test_params $e2e_dp_context
  --submariner-namespace ${SUBM_NAMESPACE}
  --connection-timeout 30 --connection-attempts 3"

  local msg="# Running End-to-End tests with GO in project: \n# $e2e_project_path
  \n# Ginkgo test parameters: $test_params"

  echo -e "$msg \n# Output will be printed both to stdout and to $E2E_LOG file. \n"
  echo -e "$msg" >> "$E2E_LOG"

  local junit_params
  if [[ "$create_junit_xml" =~ ^(y|yes)$ ]]; then
    msg="# Junit report file will be created: \n# $junit_output_file \n"
    echo -e "$msg"
    echo -e "$msg" >> "$E2E_LOG"
    junit_params="-ginkgo.reportFile $junit_output_file"
  fi

  ### Run E2E with GO test ###

  export_merged_kubeconfigs

  export GO111MODULE="on"
  go env

  go test -v ./test/e2e \
  -timeout 120m \
  -ginkgo.v -ginkgo.trace \
  -ginkgo.randomizeAllSpecs \
  -ginkgo.noColor \
  -ginkgo.reportPassed \
  ${junit_params} \
  -ginkgo.skip "\[redundancy\]" \
  -args $test_params | tee -a "$E2E_LOG"

}

# ------------------------------------------

function test_subctl_diagnose_on_merged_kubeconfigs() {
### Test subctl diagnose command on merged kubeconfig ###
  PROMPT "Testing SubCtl diagnose on merged kubeconfig of multiple clusters"
  trap_to_debug_commands;

  local subctl_diagnose

  # export_active_clusters_kubeconfig

  export_merged_kubeconfigs

  # For SubCtl > 0.8 : Run subctl diagnose:
  if [[ $(subctl version | grep --invert-match "v0.8") ]] ; then

    subctl diagnose deployment || : # Temporarily ignore error

    subctl diagnose connections || subctl_diagnose=ERROR

    subctl diagnose k8s-version || subctl_diagnose=ERROR

    subctl diagnose kube-proxy-mode ${TEST_NS:+--namespace $TEST_NS} || subctl_diagnose=ERROR

    subctl diagnose cni || subctl_diagnose=ERROR

    subctl diagnose firewall intra-cluster --validation-timeout 120 || subctl_diagnose=ERROR

    subctl diagnose firewall inter-cluster ${KUBECONF_HUB} ${KUBECONF_MANAGED} --validation-timeout 120 --verbose || subctl_diagnose=ERROR

    BUG "subctl diagnose firewall metrics does not work on merged kubeconfig" \
    "Ignore 'subctl diagnose firewall metrics' output" \
    "https://bugzilla.redhat.com/show_bug.cgi?id=2013711"
    # workaround:
    export KUBECONFIG="${KUBECONF_HUB}"

    subctl diagnose firewall metrics --validation-timeout 120 --verbose || :

    if [[ "$subctl_diagnose" = ERROR ]] ; then
      FAILURE "SubCtl diagnose had some failed checks, please investigate"
    fi

  else
    TITLE "Subctl diagnose command is not supported in $(subctl version)"
  fi

}

# ------------------------------------------

function test_subctl_benchmarks() {
  PROMPT "Testing subctl benchmark: latency and throughput tests"
  trap_to_debug_commands;

  # export_active_clusters_kubeconfig

  subctl benchmark latency ${KUBECONF_HUB} ${KUBECONF_MANAGED} --verbose || benchmark_status=ERROR

  subctl benchmark throughput ${KUBECONF_HUB} ${KUBECONF_MANAGED} --verbose || benchmark_status=ERROR

  if [[ "$benchmark_status" = ERROR ]] ; then
    FAILURE "Submariner benchmark tests have ended with failures. \n\
    Possible bug: https://bugzilla.redhat.com/show_bug.cgi?id=1971246"
  fi

}

# ------------------------------------------

function build_submariner_repos() {
### Building latest Submariner code and tests ###
  PROMPT "Building Submariner-IO code of E2E and unit-tests for version $SUBM_VER_TAG"
  trap_to_debug_commands;

  verify_golang || FATAL "No Golang compiler found. Try to run again with option '--config-golang'"

  TITLE "Retrieve correct branch to pull for Submariner version '$SUBM_VER_TAG'"

  local subctl_branch_tag
  if [[ "$SUBM_VER_TAG" =~ latest|devel ]]; then
    # Find the latest release branch name
    subctl_branch_tag="$(get_subctl_branch_tag)"
  else
    # Find the latest release branch name that includes ${SUBM_VER_TAG} regex
    subctl_branch_tag=$(get_subctl_branch_tag "${SUBM_VER_TAG}")
  fi

  build_go_repo "https://github.com/submariner-io/submariner" $subctl_branch_tag

  build_go_repo "https://github.com/submariner-io/lighthouse" $subctl_branch_tag
}

# ------------------------------------------

function build_operator_latest() {  # [DEPRECATED]
### Building latest Submariner-Operator code and SubCtl tool ###
  PROMPT "Building latest Submariner-Operator code and SubCtl tool"
  trap_to_debug_commands;

  verify_golang || FATAL "No Golang compiler found. Try to run again with option '--config-golang'"

  # Install Docker
  # install_local_docker "${WORKDIR}"

  # Delete old submariner-operator directory
  #rm -rf $GOPATH/src/github.com/submariner-io/submariner-operator

  # Download Submariner Operator with go
  # export PATH=$PATH:$GOROOT/bin
  GO111MODULE="off" go get -v github.com/submariner-io/submariner-operator/... || echo "# GO Get Submariner Operator finished"

  # Pull latest changes and build:
  cd $GOPATH/src/github.com/submariner-io/submariner-operator
  ls

  # go get -v -u -t ./...
  git_reset_local_repo

  TITLE "Build SubCtl tool and install it in $GOBIN/"

  BUG "GO111MODULE=on go install" \
  "make bin/subctl # BUT Will fail if Docker is not pre-installed" \
  "https://github.com/submariner-io/submariner-operator/issues/319"
  # export GO111MODULE=on
  # GO111MODULE=on go mod vendor
  # GO111MODULE=on go install # Compile binary and moves it to $GOBIN

  GO111MODULE="on" go mod vendor
  ./scripts/generate-embeddedyamls

  # ./scripts/build-subctl
  BUG "./scripts/build-subctl failed since it runs git outside repo directory" \
  "Precede with DAPPER_SOURCE = submariner-operator path" \
  "https://github.com/submariner-io/submariner-operator/issues/390"
  # workaround:
  DAPPER_SOURCE="$(git rev-parse --show-toplevel)"
  export DAPPER_SOURCE

  BUG "./scripts/build fails for missing library file" \
  "Use SCRIPTS_DIR from Shipyard" \
  "https://github.com/submariner-io/submariner/issues/576"
  # workaround:
  wget -O - https://github.com/submariner-io/shipyard/archive/devel.tar.gz | tar xz --strip=2 "shipyard-devel/scripts/shared"
  export SCRIPTS_DIR=${PWD}/shared

  BUG "Building subctl: compile.sh fails on bad substitution of flags" \
  "NO Workaround yet" \
  "https://github.com/submariner-io/submariner-operator/issues/403"

  ./scripts/build-subctl
    # ...
    # Building subctl version dev for linux/amd64
    # ...

  ls -l ./bin/subctl
  mkdir -p $GOBIN
  # cp -f ./bin/subctl $GOBIN/
  /usr/bin/install ./bin/subctl $GOBIN/subctl

  # Create symbolic link /usr/local/bin/subctl :
  #sudo ln -sf $GOPATH/src/github.com/submariner-io/submariner-operator/bin/subctl /usr/local/bin/subctl
  #cp -f ./bin/subctl ~/.local/bin

}

# ------------------------------------------

function test_submariner_e2e_with_subctl() {
# Run E2E Tests of Submariner:
  PROMPT "Testing Submariner End-to-End tests with SubCtl command"
  trap_to_debug_commands;

  # export_active_clusters_kubeconfig

  [[ -x "$(command -v subctl)" ]] || FATAL "No SubCtl installation found. Try to run again with option '--subctl-version'"
  subctl version

  TITLE "Set SubCtl E2E context for the active clusters"
  export KUBECONFIG="${KUBECONF_HUB}"
  local e2e_subctl_context
  e2e_subctl_context="$(${OC} config current-context)"

  if [[ -s "$CLUSTER_B_YAML" ]] ; then
    echo "# Appending \"${CLUSTER_B_NAME}\" to current E2E context (${e2e_subctl_context})"
    export KUBECONFIG="${KUBECONF_CLUSTER_B}"
    e2e_subctl_context="${e2e_subctl_context},$(${OC} config current-context)"
  fi

  if [[ -s "$CLUSTER_C_YAML" ]] ; then
    echo "# Appending \"${CLUSTER_C_NAME}\" to current E2E context (${e2e_subctl_context})"
    export KUBECONFIG="${KUBECONF_CLUSTER_C}"
    e2e_subctl_context="${e2e_subctl_context},$(${OC} config current-context)"
  fi

  BUG "No SubCtl option to set -ginkgo.reportFile" \
  "No workaround yet..." \
  "https://github.com/submariner-io/submariner-operator/issues/509"

  TITLE "SubCtl E2E output will be printed both to stdout and to the file $E2E_LOG"

  # export_active_clusters_kubeconfig

  export_merged_kubeconfigs

  # For SubCtl > 0.8:
  if [[ $(subctl version | grep --invert-match "v0.8") ]] ; then
    subctl verify --only service-discovery,connectivity --verbose --kubecontexts ${e2e_subctl_context} | tee -a "$E2E_LOG"
  else
    # For SubCtl <= 0.8:
    # subctl verify --disruptive-tests --verbose ${KUBECONF_HUB} ${KUBECONF_CLUSTER_B} ${KUBECONF_CLUSTER_C} | tee -a "$E2E_LOG"
    subctl verify --only service-discovery,connectivity --verbose ${KUBECONF_HUB} ${KUBECONF_CLUSTER_B} ${KUBECONF_CLUSTER_C} | tee -a "$E2E_LOG"
  fi

}

# ------------------------------------------

function upload_junit_xml_to_polarion() {
  trap_to_debug_commands;
  local junit_file="$1"
  echo -e "\n### Uploading test results to Polarion from Junit file: $junit_file ###\n"

  create_polarion_testcases_doc_from_junit "https://$POLARION_SERVER/polarion" "$POLARION_AUTH" "$junit_file" \
  "$POLARION_PROJECT_ID" "$POLARION_TEAM_NAME" "$POLARION_USR" "$POLARION_COMPONENT_ID" "$POLARION_TESTCASES_DOC" "$POLARION_TESTPLAN_ID"

  create_polarion_testrun_result_from_junit "https://$POLARION_SERVER/polarion" "$POLARION_AUTH" \
  "$junit_file" "$POLARION_PROJECT_ID" "$POLARION_TEAM_NAME" "$POLARION_TESTRUN_TEMPLATE" "$POLARION_TESTPLAN_ID"

}

# ------------------------------------------

function create_all_test_results_in_polarion() {
  PROMPT "Upload all test results to Polarion"
  trap_to_debug_commands;

  # Temp file to store Polarion output
  local polarion_testrun_import_log
  polarion_testrun_import_log="`mktemp`_polarion_import_log"
  local polarion_rc=0

  # Upload SYSTEM tests to Polarion
  TITLE "Upload Junit results of SYSTEM (Shell) tests to Polarion:"

  # Redirect output to stdout and to $polarion_testrun_import_log, in order to get polarion testrun url into report
  upload_junit_xml_to_polarion "$SHELL_JUNIT_XML" |& tee "$polarion_testrun_import_log" || polarion_rc=1

  # Add Polarion link to the HTML report
  add_polarion_testrun_url_to_report_headlines "$polarion_testrun_import_log" "$SHELL_JUNIT_XML"


  # Upload Ginkgo E2E tests to Polarion
  if [[ (! "$skip_tests" =~ ((e2e|all)(,|$))+) && -s "$E2E_JUNIT_XML" ]] ; then

    TITLE "Upload Junit results of Submariner E2E (Ginkgo) tests to Polarion:"

    # Redirecting with TEE to stdout and to $polarion_testrun_import_log, in order to get polarion testrun url into report
    upload_junit_xml_to_polarion "$E2E_JUNIT_XML" |& tee "$polarion_testrun_import_log" || polarion_rc=1

    # Add Polarion link to the HTML report
    add_polarion_testrun_url_to_report_headlines "$polarion_testrun_import_log" "$E2E_JUNIT_XML"

    TITLE "Upload Junit results of Lighthouse E2E (Ginkgo) tests to Polarion:"

    # Redirecting with TEE to stdout and to $polarion_testrun_import_log, in order to get polarion testrun url into report
    upload_junit_xml_to_polarion "$LIGHTHOUSE_JUNIT_XML" |& tee "$polarion_testrun_import_log" || polarion_rc=1

    # Add Polarion link to the HTML report
    add_polarion_testrun_url_to_report_headlines "$polarion_testrun_import_log" "$LIGHTHOUSE_JUNIT_XML"

  fi

  # Upload UNIT tests to Polarion (skipping, not really required)

  # if [[ (! "$skip_tests" =~ ((pkg|all)(,|$))+) && -s "$PKG_JUNIT_XML" ]] ; then
  #   echo "# Upload Junit results of PKG (Ginkgo) unit-tests to Polarion:"
  #   sed -r 's/(<\/?)(passed>)/\1system-out>/g' -i "$PKG_JUNIT_XML" || :
  #
  #   upload_junit_xml_to_polarion "$PKG_JUNIT_XML" || polarion_rc=1
  # fi

  return $polarion_rc
}


# ------------------------------------------

function add_polarion_testrun_url_to_report_headlines() {
# Helper function to search polarion testrun url in the testrun import output, in order to add later to the HTML report
  trap_to_debug_commands;

  local polarion_testrun_import_log="$1"
  local polarion_test_run_file="$2"

  TITLE "Add new Polarion Test run results to the Html report headlines: "
  local polarion_testrun_result_page
  polarion_testrun_result_page="$(grep -Poz '(?s)Test suite.*\n.*Polarion results published[^\n]*' "$polarion_testrun_import_log" \
  | sed -z 's/\.\n.* to:/:\n/' )" || :

  local polarion_testrun_name
  polarion_testrun_name="$(basename ${polarion_test_run_file%.*})" # Get file name without path and extension
  polarion_testrun_name="${polarion_testrun_name//junit}" # Remove all "junit" from file name
  polarion_testrun_name="${polarion_testrun_name//_/ }" # Replace all _ with spaces

  if [[ -n "$polarion_testrun_result_page" ]] ; then
    # echo "$polarion_testrun_result_page" | sed -r 's/(https:[^ ]*)/\1\&tab=records/g' >> "$POLARION_RESULTS" || :
    echo "$polarion_testrun_result_page" >> "$POLARION_RESULTS" || :
    # echo -e " (${polarion_testrun_name}) \n" >> "$POLARION_RESULTS" || :
  else
    echo -e "# Error reading Polarion Test results link for ${polarion_testrun_name}: \n ${polarion_testrun_result_page}" 1>&2
  fi

}

# ------------------------------------------

function env_teardown() {
  # Run tests and environment functions at the end (call with trap exit)

  if [[ "$print_logs" =~ ^(y|yes)$ ]]; then
    TITLE "Showing product versions (since CLI option --print-logs was used)"

    ${junit_cmd} test_products_versions_cluster_a || :

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_products_versions_cluster_b || :

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_products_versions_cluster_c || :
  fi

}

# ------------------------------------------

function test_products_versions_cluster_a() {
  PROMPT "Show products versions on cluster A"

  export KUBECONFIG="${KUBECONF_HUB}"
  test_products_versions

  save_cluster_info_to_file
}

# ------------------------------------------

function test_products_versions_cluster_b() {
  PROMPT "Show products versions on cluster B"

  export KUBECONFIG="${KUBECONF_CLUSTER_B}"
  test_products_versions

  save_cluster_info_to_file
}

# ------------------------------------------

function test_products_versions_cluster_c() {
  PROMPT "Show products versions on cluster C"

  export KUBECONFIG="${KUBECONF_CLUSTER_C}"
  test_products_versions

  save_cluster_info_to_file
}

# ------------------------------------------

function test_products_versions() {
# Show OCP clusters versions, and Submariner version
  trap '' DEBUG # DONT trap_to_debug_commands

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"
  local cluster_info_output="${SCRIPT_DIR}/${cluster_name}.info"

  local ocp_cloud
  ocp_cloud="$(print_current_cluster_cloud || :)"

  local cluster_version
  cluster_version="$(${OC} version | awk '/Server Version/ { print $3 }' )" || :

  TITLE "OCP cluster ${cluster_name} information"
  echo -e "\n# Cloud platform: ${ocp_cloud}"
  echo -e "\n# OCP version: ${cluster_version}"

  echo -e "\n### Submariner components ###\n"

  subctl version || :

  subctl show versions || :

  # Show Libreswan (cable driver) version in the active gateway pod
  export_variable_name_of_active_gateway_pod "active_gateway_pod" "yes" || :

  if [[ -n "$active_gateway_pod" ]] ; then
    echo -e "\n### Linux version on the running Gateway pod: $active_gateway_pod ###"
    ${OC} exec $active_gateway_pod -n ${SUBM_NAMESPACE} -- bash -c "cat /etc/os-release" | awk -F\" '/PRETTY_NAME/ {print $2}' || :
    echo -e "\n\n"

    echo -e "\n### LibreSwan version on the running Gateway pod: $active_gateway_pod ###"
    ${OC} exec $active_gateway_pod -n ${SUBM_NAMESPACE} -- bash -c "rpm -qa libreswan" || :
    echo -e "\n\n"
  fi

  # Show Submariner images info of running pods
  print_images_info_of_namespace_pods "${SUBM_NAMESPACE}"

  # Show Submariner CSVs (Cluster service versions)
  print_csvs_in_namespace "$SUBM_NAMESPACE"

  # Show Submariner image-stream tags
  print_image_tags_info "${SUBM_NAMESPACE}"

  # # Show BREW_REGISTRY images
  # ${OC} get images | grep "${BREW_REGISTRY}" |\
  # grep "$SUBM_IMG_GATEWAY|\
  #     $SUBM_IMG_ROUTE|\
  #     $SUBM_IMG_NETWORK|\
  #     $SUBM_IMG_LIGHTHOUSE|\
  #     $SUBM_IMG_COREDNS|\
  #     $SUBM_IMG_GLOBALNET|\
  #     $SUBM_IMG_OPERATOR|\
  #     $SUBM_IMG_BUNDLE" |\
  # while read -r line ; do
  #   set -- $(echo $line | awk '{ print $1, $2 }')
  #   local img_id="$1"
  #   local img_name="$2"
  #
  #   echo -e "\n### Local registry image: $(echo $img_name | sed -r 's|.*/([^@]+).*|\1|') ###"
  #   print_image_info "$img_id"
  # done

  echo -e "\n# Current OC user: $(${OC} whoami || : )"
  echo -e "\n# Current Kubeconfig contexts:"
  ${OC} config get-contexts

  echo -e "\n### Cluster routes on ${cluster_name} ###"
  ${OC} get routes -A || :

}

# ------------------------------------------

function save_cluster_info_to_file() {
# Save important OCP cluster and Submariner information to local files
  trap '' DEBUG # DONT trap_to_debug_commands

  local cluster_name
  cluster_name="$(print_current_cluster_name || :)"

  local ocp_cloud
  ocp_cloud="$(print_current_cluster_cloud || :)"

  local cluster_version
  cluster_version="$(${OC} version | awk '/Server Version/ { print $3 }' )" || :

  # Print OCP cluster info into file local file "<cluster name>.info"
  local cluster_info_output="${SCRIPT_DIR}/${cluster_name}.info"

  local cluster_info="${ocp_cloud} cluster : OCP ${cluster_version}"
  echo "${cluster_info}" > "${cluster_info_output}" || :

  # Print all cluster routes into file "<cluster name>.info"
  ${OC} get routes -A | awk '$2 ~ /console/ {print $1 " : " $3}' >> "${cluster_info_output}" || :

  # Just for the first managed cluster - print Submariner images url into $SUBMARINER_IMAGES file
  [[ -s "$SUBMARINER_IMAGES" ]] || \
  print_images_info_of_namespace_pods "${SUBM_NAMESPACE}" | grep -Po "url=\K.*" > $SUBMARINER_IMAGES

}

# ------------------------------------------

function collect_submariner_info() {
  # print submariner pods descriptions and logs
  # Ref: https://github.com/submariner-io/shipyard/blob/devel/scripts/shared/post_mortem.sh

  local log_file="${1:-subm_pods.log}"

  (
    PROMPT "Collecting system information due to test failure" "$RED"
    trap_to_debug_commands;

    df -h
    free -h

    TITLE "Openshift information"

    export_merged_kubeconfigs

    # oc version
    BUG "OC client version 4.5.1 cannot use merged kubeconfig" \
    "use an older OC client, or run oc commands for each cluster separately" \
    "https://bugzilla.redhat.com/show_bug.cgi?id=1857202"
    # Workaround:
    OC="/usr/bin/oc"

    ${OC} config view || :
    ${OC} status || :
    ${OC} version || :

    TITLE "Submariner information (subctl show and diagnose)"

    subctl show all || :

    subctl diagnose all || :

    export KUBECONFIG="${KUBECONF_HUB}"
    print_resources_and_pod_logs "$CLUSTER_A_NAME"

    if [[ -s "$CLUSTER_B_YAML" ]] ; then
      export KUBECONFIG="${KUBECONF_CLUSTER_B}"
      print_resources_and_pod_logs "$CLUSTER_B_NAME"
    fi

    if [[ -s "$CLUSTER_C_YAML" ]] ; then
      export KUBECONFIG="${KUBECONF_CLUSTER_C}"
      print_resources_and_pod_logs "$CLUSTER_C_NAME"
    fi

  ) |& tee -a $log_file

}

# ------------------------------------------

function print_resources_and_pod_logs() {
  trap_to_debug_commands;
  local cluster_name="$1"

  PROMPT "OCP, ACM and Submariner logs in ${cluster_name}"

  TITLE "Openshift Nodes on ${cluster_name}"

  ${OC} get nodes -o wide || :

  TITLE "Unready Pods (if any) on ${cluster_name}"

  ${OC} get pod -A |  grep -Ev '([1-9]+)/\1' | grep -v 'Completed' | grep -E '[0-9]+/[0-9]+' || :

  TITLE "ACM and Submariner resources in ${cluster_name}"

  ${OC} get all -n ${ACM_NAMESPACE} || :

  ${OC} get all -n ${SUBM_NAMESPACE} || :

  ${OC} get all -n ${BROKER_NAMESPACE} || :

  TITLE "Submariner Gateway info on ${cluster_name}"

  ${OC} get nodes --selector=submariner.io/gateway=true --show-labels || :

  ${OC} describe Submariner -n ${SUBM_NAMESPACE} || :
  # ${OC} get Submariner -o yaml -n ${SUBM_NAMESPACE} || :

  ${OC} describe Gateway -n ${SUBM_NAMESPACE} || :

  TITLE "Submariner Roles and Broker info on ${cluster_name}"

  ${OC} get roles -A | grep "submariner" || :

  ${OC} describe role submariner-k8s-broker-cluster -n ${BROKER_NAMESPACE} || :

  TITLE "Submariner Deployments, Daemon and Replica sets on ${cluster_name}"

  ${OC} describe deployments -n ${SUBM_NAMESPACE} || :
  #  ${OC} get deployments -o yaml -n ${SUBM_NAMESPACE} || :

  ${OC} describe daemonsets -n ${SUBM_NAMESPACE} || :

  ${OC} describe replicasets -n ${SUBM_NAMESPACE} || :

  TITLE "Openshift configurations on ${cluster_name}"

  ${OC} describe configmaps -n openshift-dns || :

  echo -e "\n# TODO: Loop on each cluster: ${OC} describe cluster ${cluster_name} -n ${SUBM_NAMESPACE}"

  # for pod in $(${OC} get pods -A \
  # -l 'name in (submariner-operator,submariner-gateway,submariner-globalnet,kube-proxy)' \
  # -o jsonpath='{.items[0].metadata.namespace} {.items[0].metadata.name}' ; do
  #     echo "######################: Logs for Pod $pod :######################"
  #     ${OC}  -n $ns describe pod $name
  #     ${OC}  -n $namespace logs $pod
  # done

  TITLE "Openshift Machines on ${cluster_name}"

  ${OC} get machineconfigpool || :

  ${OC} get Machine -A | awk '{
    if (NR>1) {
      namespace = $1
      machine = $2
      printf ("\n###################### Machine: %s (Namespece: %s) ######################\n", machine, namespace )
      cmd = "oc describe Machine " machine " -n " namespace
      printf ("\n$ %s\n\n", cmd)
      system("oc describe Machine "$2" -n "$1)
    }
  }'

  TITLE "Submariner LOGS on ${cluster_name}"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "name=submariner-operator"

  local gw_label='app=submariner-gateway'
  # For SubCtl <= 0.8 : 'app=submariner-engine' is expected as the Gateway pod label
  [[ $(subctl version | grep --invert-match "v0.8") ]] || gw_label="app=submariner-engine"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" $gw_label

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-globalnet"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-lighthouse-agent"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-lighthouse-coredns"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-routeagent"

  print_pod_logs_in_namespace "$cluster_name" "kube-system" "k8s-app=kube-proxy"

  print_pod_logs_in_namespace "$cluster_name" "kube-system" "component=kube-controller-manager"

  echo -e "\n############################## End of Submariner logs collection on ${cluster_name} ##############################\n"

  TITLE "ALL Openshift events on ${cluster_name}"

  ${OC} get events -A --sort-by='.metadata.creationTimestamp' \
  -o custom-columns=FirstSeen:.firstTimestamp,LastSeen:.lastTimestamp,Count:.count,From:.source.component,Type:.type,Reason:.reason,Message:.message || :

}

# ------------------------------------------

# Functions to debug this script

function debug_test_polarion() {
  trap_to_debug_commands;
  PROMPT "DEBUG Polarion setup"

  # Set Polarion access if $upload_to_polarion = yes/y
  if [[ "$upload_to_polarion" =~ ^(y|yes)$ ]] ; then
    TITLE "Set Polarion access for the user [$POLARION_USR]"
    ( # subshell to hide commands
      local polauth
      polauth=$(echo "${POLARION_USR}:${POLARION_PWD}" | base64 --wrap 0)
      echo "--header \"Authorization: Basic ${polauth}\"" > "$POLARION_AUTH"
    )
  fi

  echo 1 > $TEST_STATUS_FILE

}

function debug_test_pass() {
  trap_to_debug_commands;
  PROMPT "PASS test for DEBUG"

  local test="TRUE"

  if [[ -n "$test" ]] ; then
    BUG "A dummy bug" \
     "A workaround" \
    "A link"
  fi

  local msg="
    & (ampersand) <br>
    < (lower) <br>
    > (greater) <br>
    ‘ (single quotes) <br>
    \" (double quotes) <br>
    "

  TITLE "PRINT TEST: \n $msg"

}

function debug_test_fail() {
  trap_to_debug_commands;
  PROMPT "FAIL test for DEBUG"
  echo "Should not get here if calling after a bad exit code (e.g. FAILURE or FATAL)"
  # find ${CLUSTER_A_DIR} -name "*.log" -print0 | xargs -0 cat

  local TEST=1
  if [[ -n "$TEST" ]] ; then
    TITLE "Test FAILURE() function, that should not break whole script, but just this test"
    FAILURE "MARK TEST FAILURE, BUT CONTINUE"
  fi

  echo "It should NOT print this"

}

function debug_test_fatal() {
  trap_to_debug_commands;
  PROMPT "FATAL test for DEBUG"
  FATAL "Terminating script here"
}

# ------------------------------------------



####################################################################################
#                    MAIN - Submariner Deploy and Tests                            #
####################################################################################

### Set script in debug/verbose mode, if used CLI option: --debug / -d ###
if [[ "$script_debug_mode" =~ ^(yes|y)$ ]]; then
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

# Exporting active clusters KUBECONFIGs
export_active_clusters_kubeconfig

# Printing output both to stdout and to $SYS_LOG with tee
echo -e "\n# TODO: consider adding timestamps with: ts '%H:%M:%.S' -s"
(

  ### Script debug calls (should be left as a comment) ###

    # ${junit_cmd} debug_test_polarion
    # ${junit_cmd} debug_test_pass
    # ${junit_cmd} debug_test_fail
    # rc=$?
    # BUG "debug_test_fail - Exit code: $rc" \
    # "If RC $rc = 5 - junit_cmd should continue execution"
    # ${junit_cmd} debug_test_pass
    # ${junit_cmd} debug_test_fatal

  ### END Script debug ###

  # Print planned steps according to CLI/User inputs
  ${junit_cmd} show_test_plan

  # Setup and verify environment
  setup_workspace

  # Set script trap functions
  set_trap_functions

  ### Destroy / Create / Clean OCP Clusters (if not requested to --skip-ocp-setup) ###

  # Exporting active clusters KUBECONFIGs
  # export_active_clusters_kubeconfig

  if [[ ! "$skip_ocp_setup" =~ ^(y|yes)$ ]]; then

    # Running download_ocp_installer for cluster A

    if [[ "$get_ocp_installer" =~ ^(y|yes)$ ]] && [[ "$ocp_installer_required" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} download_ocp_installer ${OCP_VERSION}

    fi

    # Running destroy or create or both (reset) for cluster A

    if [[ "$reset_cluster_a" =~ ^(y|yes)$ ]] || [[ "$destroy_cluster_a" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} destroy_ocp_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_NAME"

    fi

    if [[ "$reset_cluster_a" =~ ^(y|yes)$ ]] || [[ "$create_cluster_a" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} prepare_install_ocp_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_YAML" "$CLUSTER_A_NAME"

      ${junit_cmd} create_ocp_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_NAME"

    fi
    ### END of Cluster A Setup ###

    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      # Running build_ocpup_tool_latest if requested, for cluster B

      if [[ "$get_ocpup_tool" =~ ^(y|yes)$ ]] && [[ "$ocpup_tool_required" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} build_ocpup_tool_latest

      fi


      # Running destroy or create or both (reset) for cluster B

      if [[ "$reset_cluster_b" =~ ^(y|yes)$ ]] || [[ "$destroy_cluster_b" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} destroy_osp_cluster "$CLUSTER_B_DIR" "$CLUSTER_B_NAME"

      fi

      if [[ "$reset_cluster_b" =~ ^(y|yes)$ ]] || [[ "$create_cluster_b" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} prepare_install_osp_cluster "$CLUSTER_B_YAML" "$CLUSTER_B_NAME"

        ${junit_cmd} create_osp_cluster "$CLUSTER_B_NAME"

      fi

    fi
    ### END of Cluster B Setup ###

    if [[ -s "$CLUSTER_C_YAML" ]] ; then

      # Running download_ocp_installer if requested, for cluster C

      if [[ "$get_ocp_installer" =~ ^(y|yes)$ ]] && [[ "$ocp_installer_required" =~ ^(y|yes)$ ]] ; then

        echo -e "\n# TODO: Need to download specific OCP version for each OCP cluster (i.e. CLI flag for each cluster is required)"

        # ${junit_cmd} download_ocp_installer ${OCP_VERSION}

      fi

      # Running destroy or create or both (reset) for cluster C

      if [[ "$reset_cluster_c" =~ ^(y|yes)$ ]] || [[ "$destroy_cluster_c" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} destroy_ocp_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_NAME"

      fi

      if [[ "$reset_cluster_c" =~ ^(y|yes)$ ]] || [[ "$create_cluster_c" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} prepare_install_ocp_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_YAML" "$CLUSTER_C_NAME"

        ${junit_cmd} create_ocp_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_NAME"

      fi

    fi
    ### END of Cluster C Setup ###

    ### Running prerequisites for submariner tests ###
    # It will be skipped if using --skip-tests (except for pkg unit-tests, that does not require submariner deployment)

    if [[ ! "$skip_tests" =~ (all(,|$))+ ]] ; then

      ### Verify clusters status after OCP reset/create, and add elevated user and context ###

      ${junit_cmd} update_kubeconfig_context_cluster_a

      ${junit_cmd} test_kubeconfig_cluster_a

      ${junit_cmd} add_elevated_user_to_cluster_a

      # Verify cluster B (if it is expected to be an active cluster)
      if [[ -s "$CLUSTER_B_YAML" ]] ; then

        ${junit_cmd} update_kubeconfig_context_cluster_b

        ${junit_cmd} test_kubeconfig_cluster_b

        ${junit_cmd} add_elevated_user_to_cluster_b

      fi

      # Verify cluster C (if it is expected to be an active cluster)
      if [[ -s "$CLUSTER_C_YAML" ]] ; then

        ${junit_cmd} update_kubeconfig_context_cluster_c

        ${junit_cmd} test_kubeconfig_cluster_c

        ${junit_cmd} add_elevated_user_to_cluster_c

      fi

      ### Cleanup Submariner from all clusters ###

      # Running cleanup on cluster A if requested
      if [[ "$clean_cluster_a" =~ ^(y|yes)$ ]] && [[ ! "$destroy_cluster_a" =~ ^(y|yes)$ ]] ; then

        # ${junit_cmd} clean_acm_namespace_and_resources_cluster_a  # Skipping ACM cleanup, as it might not be required for Submariner tests

        ${junit_cmd} clean_submariner_namespace_and_resources_cluster_a

        ${junit_cmd} clean_submariner_labels_and_machine_sets_cluster_a

        ${junit_cmd} delete_old_submariner_images_from_cluster_a

      fi

      # Running cleanup on cluster B if requested
      if [[ -s "$CLUSTER_B_YAML" ]] ; then

        if [[ "$clean_cluster_b" =~ ^(y|yes)$ ]] && [[ ! "$destroy_cluster_b" =~ ^(y|yes)$ ]] ; then

          # ${junit_cmd} clean_acm_namespace_and_resources_cluster_b  # Skipping ACM cleanup, as it might not be required for Submariner tests

          ${junit_cmd} clean_submariner_namespace_and_resources_cluster_b

          ${junit_cmd} clean_submariner_labels_and_machine_sets_cluster_b

          ${junit_cmd} delete_old_submariner_images_from_cluster_b

        fi
      fi

      # Running cleanup on cluster C if requested
      if [[ -s "$CLUSTER_C_YAML" ]] ; then

        if [[ "$clean_cluster_c" =~ ^(y|yes)$ ]] && [[ ! "$destroy_cluster_c" =~ ^(y|yes)$ ]] ; then

          # ${junit_cmd} clean_acm_namespace_and_resources_cluster_c  # Skipping ACM cleanup, as it might not be required for Submariner tests

          ${junit_cmd} clean_submariner_namespace_and_resources_cluster_c

          ${junit_cmd} clean_submariner_labels_and_machine_sets_cluster_c

          ${junit_cmd} delete_old_submariner_images_from_cluster_c

        fi
      fi

      # Configure firewall ports, gateway labels, and images prune on all clusters

      echo -e "\n# TODO: If installing without ADDON (when adding clusters with subctl join) -
      \n\# Then for AWS/GCP run subctl cloud prepare, and for OSP use terraform script"
      # https://submariner.io/operations/deployment/subctl/#cloud-prepare

      ${junit_cmd} configure_images_prune_cluster_a

      if [[ -s "$CLUSTER_B_YAML" ]] ; then

        echo -e "\n# TODO: Run only if it's an openstack (on-prem) cluster"

        # ${junit_cmd} open_firewall_ports_on_cluster_a

        # ${junit_cmd} label_gateway_on_broker_nodes_with_external_ip

        ${junit_cmd} open_firewall_ports_on_openstack_cluster_b

        ${junit_cmd} label_first_gateway_cluster_b

        ${junit_cmd} configure_images_prune_cluster_b

      fi

      if [[ -s "$CLUSTER_C_YAML" ]] ; then

        echo -e "\n# TODO: If installing without ADDON (when adding clusters with subctl join) -
        \n\# Then for AWS/GCP run subctl cloud prepare, and for OSP use terraform script"
        # https://submariner.io/operations/deployment/subctl/#cloud-prepare
        #
        # ${junit_cmd} open_firewall_ports_on_cluster_c
        #
        # ${junit_cmd} label_first_gateway_cluster_c

        ${junit_cmd} configure_images_prune_cluster_c

      fi

      # Overriding Submariner images with custom images from registry, if requested with --registry-images
      if [[ "$registry_images" =~ ^(y|yes)$ ]] ; then

        # ${junit_cmd} remove_submariner_images_from_local_registry_with_podman

        ${junit_cmd} configure_custom_registry_cluster_a

        ${junit_cmd} upload_submariner_images_to_registry_cluster_a

        if [[ -s "$CLUSTER_B_YAML" ]] ; then

          ${junit_cmd} configure_custom_registry_cluster_b

          ${junit_cmd} upload_submariner_images_to_registry_cluster_b

        fi

        if [[ -s "$CLUSTER_C_YAML" ]] ; then

          ${junit_cmd} configure_custom_registry_cluster_c

          ${junit_cmd} upload_submariner_images_to_registry_cluster_c

        fi

      fi # End of configure custom images in OCP registry

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

    fi ### END of prerequisites for submariner system tests ###

  else  # When using --skip-ocp-setup :

    # Verify clusters status even if OCP setup/cleanup was skipped

    ${junit_cmd} test_kubeconfig_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_kubeconfig_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_kubeconfig_cluster_c

  fi

  TITLE "OCP clusters and environment setup is ready"
  echo -e "\n# From this point, if script fails - \$TEST_STATUS_FILE is considered FAILED, and will be reported to Polarion.
  \n# ($TEST_STATUS_FILE with exit code 1)"

  echo 1 > $TEST_STATUS_FILE

  ### END of ALL OCP Clusters Setup, Cleanup and Registry configure ###


  ### INSTALL ACM with Submariner on all Clusters ###

  if [[ "$install_acm" =~ ^(y|yes)$ ]] ; then

    # Setup ACM Hub

    ${junit_cmd} install_acm_operator "$ACM_VER_TAG"

    ${junit_cmd} create_acm_multiclusterhub

    ${junit_cmd} create_clusterset_for_submariner_in_acm_hub

    ${junit_cmd} create_and_import_managed_cluster "${KUBECONF_HUB}"

    # Setup Submariner Addon on the managed clusters

    ${junit_cmd} configure_submariner_bundle_on_cluster "${KUBECONF_HUB}"

    ${junit_cmd} install_submariner_via_acm_managed_cluster "${KUBECONF_HUB}"

    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      ${junit_cmd} create_and_import_managed_cluster "${KUBECONF_CLUSTER_B}"

      ${junit_cmd} configure_submariner_bundle_on_cluster "${KUBECONF_CLUSTER_B}"

      ${junit_cmd} install_submariner_via_acm_managed_cluster "${KUBECONF_CLUSTER_B}"

    fi

    if [[ -s "$CLUSTER_C_YAML" ]] ; then

      ${junit_cmd} create_and_import_managed_cluster "${KUBECONF_CLUSTER_C}"

      ${junit_cmd} configure_submariner_bundle_on_cluster "${KUBECONF_CLUSTER_C}"

      ${junit_cmd} install_submariner_via_acm_managed_cluster "${KUBECONF_CLUSTER_C}"

    fi

  fi

  TITLE "From this point, if script fails - \$TEST_STATUS_FILE is considered UNSTABLE, and will be reported to Polarion"
  echo -e "\n# ($TEST_STATUS_FILE with exit code 2)"

  echo 2 > $TEST_STATUS_FILE

  ### END of ACM Install ###

  ### Download and install SUBCTL ###
  if [[ "$download_subctl" =~ ^(y|yes)$ ]] ; then

    ${junit_cmd} download_and_install_subctl "$SUBM_VER_TAG"

  fi

  ### Deploy Submariner on the clusters with SUBCTL tool (if using --subctl-install) ###

  if [[ "$install_with_subctl" =~ ^(y|yes)$ ]]; then

    # Running build_operator_latest if requested  # [DEPRECATED]
    # [[ ! "$build_operator" =~ ^(y|yes)$ ]] || ${junit_cmd} build_operator_latest

    ${junit_cmd} test_subctl_command

    ${junit_cmd} set_join_parameters_for_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} set_join_parameters_for_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} set_join_parameters_for_cluster_c

    # Overriding Submariner images with custom images from registry
    if [[ "$registry_images" =~ ^(y|yes)$ ]]; then

      ${junit_cmd} append_custom_images_to_join_cmd_cluster_a

      [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} append_custom_images_to_join_cmd_cluster_b

      [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} append_custom_images_to_join_cmd_cluster_c

    fi

    ${junit_cmd} install_broker_cluster_a

    ${junit_cmd} test_broker_before_join

    ${junit_cmd} run_subctl_join_on_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} run_subctl_join_on_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} run_subctl_join_on_cluster_c

  fi
  ### END of install_with_subctl ###

  ### Running High-level / E2E / Unit Tests (if not requested to --skip-tests sys / all) ###

  if [[ ! "$skip_tests" =~ ((sys|all)(,|$))+ ]]; then

    ### Running High-level (System) tests of Submariner ###

    ${junit_cmd} test_public_ip_on_gateway_node

    ${junit_cmd} test_disaster_recovery_of_gateway_nodes

    ${junit_cmd} test_renewal_of_gateway_and_public_ip

    ${junit_cmd} test_submariner_resources_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_submariner_resources_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_submariner_resources_cluster_c

    ${junit_cmd} test_cable_driver_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_cable_driver_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_cable_driver_cluster_c

    ${junit_cmd} test_ha_status_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_ha_status_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_ha_status_cluster_c

    ${junit_cmd} test_submariner_connection_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_submariner_connection_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_submariner_connection_cluster_c

    ${junit_cmd} test_subctl_show_on_merged_kubeconfigs

    ${junit_cmd} test_ipsec_status_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_ipsec_status_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_ipsec_status_cluster_c

    if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} test_globalnet_status_cluster_a

      [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_globalnet_status_cluster_b

      [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_globalnet_status_cluster_c
    fi

    # Test service-discovery (lighthouse)

    ${junit_cmd} test_lighthouse_status_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_lighthouse_status_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_lighthouse_status_cluster_c

    ### Running connectivity tests between the On-Premise and Public clusters,
    # To validate that now Submariner made the connection possible.

    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      export KUBECONF_MANAGED="${KUBECONF_CLUSTER_B}"

    elif [[ -s "$CLUSTER_C_YAML" ]] ; then

      export KUBECONF_MANAGED="${KUBECONF_CLUSTER_C}"

    fi

    ${junit_cmd} test_clusters_connected_by_service_ip

    ${junit_cmd} install_new_netshoot_cluster_a

    ${junit_cmd} install_nginx_headless_namespace_managed_cluster

    if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} test_new_netshoot_global_ip_cluster_a

      ${junit_cmd} test_nginx_headless_global_ip_managed_cluster
    fi

    # Test the default (pre-installed) netshoot and nginx with service-discovery

    ${junit_cmd} export_nginx_default_namespace_managed_cluster

    ${junit_cmd} test_clusters_connected_full_domain_name

    ${junit_cmd} test_clusters_cannot_connect_short_service_name

    # Test the new netshoot and headless nginx service discovery

    if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} test_clusters_connected_overlapping_cidrs

        echo -e "\n# TODO: Test headless service with GLobalnet - when the feature of is supported"
        BUG "HEADLESS Service is not supported with GlobalNet" \
         "No workaround yet - Skip the whole test" \
        "https://github.com/submariner-io/lighthouse/issues/273"
        # No workaround yet

    else
      ${junit_cmd} export_nginx_headless_namespace_managed_cluster

      ${junit_cmd} test_clusters_connected_headless_service_on_new_namespace

      ${junit_cmd} test_clusters_cannot_connect_headless_short_service_name
    fi


    ### Running diagnose and benchmark tests with subctl

    ${junit_cmd} test_subctl_diagnose_on_merged_kubeconfigs

    ${junit_cmd} test_subctl_benchmarks

  fi # END of all System tests


  ### Running Submariner tests with Ginkgo or with subctl commands

  if [[ ! "$skip_tests" =~ all ]]; then

    ### Compiling Submariner projects in order to run Ginkgo tests with GO

    if [[ "$build_go_tests" =~ ^(y|yes)$ ]] ; then
      verify_golang || FATAL "No Golang compiler found. Try to run again with option '--config-golang'"

      ${junit_cmd} build_submariner_repos
    fi

    ### Running Unit-tests in Submariner project with Ginkgo

    if [[ ! "$skip_tests" =~ pkg ]] && [[ "$build_go_tests" =~ ^(y|yes)$ ]]; then
      ${junit_cmd} test_submariner_packages

      if tail -n 5 "$E2E_LOG" | grep 'FAIL' ; then
        ginkgo_tests_status=FAILED
        BUG "Submariner Unit-Tests FAILED"
      else
        echo "### Submariner Unit-Tests PASSED ###"
      fi

    fi

    if [[ ! "$skip_tests" =~ e2e ]]; then

      if [[ "$build_go_tests" =~ ^(y|yes)$ ]] ; then

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
  test_status="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat $TEST_STATUS_FILE)"
  echo -e "\n# Publishing to Polarion should be run only If $TEST_STATUS_FILE does not include empty: [${test_status}] \n"

  ### Upload Junit xmls to Polarion - only if requested by user CLI, and $test_status is set ###
  if [[ -n "$test_status" ]] && [[ "$upload_to_polarion" =~ ^(y|yes)$ ]] ; then
      create_all_test_results_in_polarion || :
  fi

  # ------------------------------------------

  ### Creating HTML report from console output ###

  message="Creating HTML Report"

  # If $TEST_STATUS_FILE does not include 0 (0 = all Tests passed) or 2 (2 = some tests passed) - it means that system tests have failed (or not run at all)
  if [[ "$test_status" != @(0|2) ]] ; then
    message="$message - System tests failed with exit status [$test_status]"
    color="$RED"
  fi
  PROMPT "$message" "$color"

  TITLE "Creating HTML Report"
  echo -e "# SYS_LOG = $SYS_LOG
  # REPORT_NAME = $REPORT_NAME
  # REPORT_FILE = $REPORT_FILE
  "

  if [[ -n "$REPORT_FILE" ]] ; then
    echo "# Remove path and replace all spaces from REPORT_FILE: '$REPORT_FILE'"
    REPORT_FILE="$(basename ${REPORT_FILE// /_})"
  fi

) |& tee -a "$SYS_LOG"


# ------------------------------------------


echo "# Clean $SYS_LOG from sh2ju debug lines (+++), if CLI option: --debug was NOT used"
[[ "$script_debug_mode" =~ ^(yes|y)$ ]] || sed -i 's/+++.*//' "$SYS_LOG"

TITLE "Set Html report headlines with important test and environment info"
html_report_headlines=""

if [[ -s "$POLARION_RESULTS" ]] ; then
  headline="Polarion results:"
  echo "# ${headline}"
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
  echo "# ${headline}"
  cat "$SUBMARINER_IMAGES"

  html_report_headlines+="
  <br> <b>${headline}</b>
  $(< "$SUBMARINER_IMAGES")"
fi


### Create REPORT_FILE (html) from $SYS_LOG using log_to_html()
{
  log_to_html "$SYS_LOG" "$REPORT_NAME" "$REPORT_FILE" "$html_report_headlines"

  # If REPORT_FILE was not passed externally, set it as the latest html file that was created
  REPORT_FILE="${REPORT_FILE:-$(ls -1 -tu *.html | head -1)}"

} || :

# ------------------------------------------

### Collecting artifacts and compressing to tar.gz archive ###

if [[ -n "${REPORT_FILE}" ]] ; then
   ARCHIVE_FILE="${REPORT_FILE%.*}_${DATE_TIME}.tar.gz"
else
   ARCHIVE_FILE="${PWD##*/}_${DATE_TIME}.tar.gz"
fi

TITLE "Compressing Report, Log, Kubeconfigs and other test artifacts into: ${ARCHIVE_FILE}"

# export_active_clusters_kubeconfig

# Artifact OCP clusters kubeconfigs and logs
if [[ -s "$CLUSTER_A_YAML" ]] ; then
  echo "# Saving kubeconfig and OCP installer log of Cluster A"

  cp -f "$KUBECONF_HUB" "kubconf_${CLUSTER_A_NAME}" || :

  find ${CLUSTER_A_DIR} -type f -name "*.log" -exec \
  sh -c 'cp "{}" "cluster_a_$(basename "$(dirname "{}")")$(basename "{}")"' \; || :
fi

if [[ -s "$CLUSTER_B_YAML" ]] ; then
  echo "# Saving kubeconfig and OCP installer log of Cluster B"

  cp -f "$KUBECONF_CLUSTER_B" "kubconf_${CLUSTER_B_NAME}" || :

  find ${CLUSTER_B_DIR} -type f -name "*.log" -exec \
  sh -c 'cp "{}" "cluster_b_$(basename "$(dirname "{}")")$(basename "{}")"' \; || :
fi

if [[ -s "$CLUSTER_C_YAML" ]] ; then
  echo "# Saving kubeconfig and OCP installer log of Cluster C"

  cp -f "$KUBECONF_CLUSTER_C" "kubconf_${CLUSTER_C_NAME}" || :

  find ${CLUSTER_C_DIR} -type f -name "*.log" -exec \
  sh -c 'cp "{}" "cluster_c_$(basename "$(dirname "{}")")$(basename "{}")"' \; || :
fi

# Artifact other WORKDIR files
[[ ! -f "$WORKDIR/$BROKER_INFO" ]] || cp -f "$WORKDIR/$BROKER_INFO" "subm_${BROKER_INFO}"
[[ ! -f "${WORKDIR}/${OCP_USR}.sec" ]] || cp -f "${WORKDIR}/${OCP_USR}.sec" "${OCP_USR}.sec"

# Compress all artifacts
tar --dereference --hard-dereference -cvzf $ARCHIVE_FILE $(ls \
 "$REPORT_FILE" \
 "$SYS_LOG" \
 kubconf_* \
 subm_* \
 *.sec \
 *.xml \
 *.yaml \
 *.log \
 2>/dev/null)

TITLE "Archive \"$ARCHIVE_FILE\" now contains:"
tar tvf $ARCHIVE_FILE

TITLE "To view in your Browser, run:\n tar -xvf ${ARCHIVE_FILE}; firefox ${REPORT_FILE}"

test_status="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat $TEST_STATUS_FILE)"
TITLE "Exiting script with \$TEST_STATUS_FILE return code: [$test_status]"

if [[ -z "$test_status" ]] ; then
  exit 3
else
  exit $test_status
fi


# ------------------------------------------
