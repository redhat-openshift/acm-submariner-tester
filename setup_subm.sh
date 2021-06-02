#!/bin/bash
#######################################################################################################
#                                                                                                     #
# Setup Submariner on AWS and OSP (Upshift)                                                           #
# By Noam Manos, nmanos@redhat.com                                                                    #
#                                                                                                     #
# You can find latest script here:                                                                    #
# https://github.com/manosnoam/ocp-multi-cluster-tester                                               #
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

  * Create AWS cluster A:                              --create-cluster-a
  * Create OSP cluster B:                              --create-cluster-b
  * Destroy existing AWS cluster A:                    --destroy-cluster-a
  * Destroy existing OSP cluster B:                    --destroy-cluster-b
  * Reset (create & destroy) AWS cluster A:            --reset-cluster-a
  * Reset (create & destroy) OSP cluster B:            --reset-cluster-b
  * Clean existing AWS cluster A:                      --clean-cluster-a
  * Clean existing OSP cluster B:                      --clean-cluster-b
  * Download OCP Installer version:                    --get-ocp-installer [latest / x.y.z / nightly]
  * Download latest OCPUP Tool:                        --get-ocpup-tool
  * Install Golang if missing:                         --config-golang
  * Install AWS-CLI and configure access:              --config-aws-cli
  * Skip OCP clusters setup (destroy/create/clean):    --skip-ocp-setup

- Submariner installation options:

  * Download SubCtl version:                           --subctl-version [latest / x.y.z / {tag}]
  * Override images from a custom registry:            --registry-images
  * Configure and test GlobalNet:                      --globalnet
  * Skip Submariner installation on all clusters:      --skip-install

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

`./setup_subm.sh --clean-cluster-a --clean-cluster-b --subctl-version 0.8.1 --registry-images --globalnet`

  * Reuse (clean) existing clusters
  * Install Submariner 0.8.1 release
  * Override Submariner images from a custom repository (configured in REGISTRY variables)
  * Configure GlobalNet (for overlapping clusters CIDRs)
  * Run Submariner E2E tests (with subctl)


`./setup_subm.sh --get-ocp-installer 4.5.1 --reset-cluster-a --clean-cluster-b --subctl-version subctl-devel --build-tests --junit`

  * Download OCP installer version 4.5.1
  * Recreate new cluster on AWS (cluster A)
  * Clean existing cluster on OSP (cluster B)
  * Install "subctl-devel" (subctl development branch)
  * Build and run Submariner E2E and unit-tests with GO
  * Create Junit tests result (xml files)

----------------------------------------------------------------------'

####################################################################################
#          Global bash configurations, constants and external sources              #
####################################################################################

# Set SCRIPT_DIR as current absolute path where this script runs in (e.g. Jenkins build directory)
export SCRIPT_DIR="$(dirname "$(realpath -s $0)")"

### Import Submariner setup variables ###
source "$SCRIPT_DIR/subm_variables"

### Import General Helpers Function ###
source "$SCRIPT_DIR/helper_functions"

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

# Date-time signature for log and report files
export DATE_TIME="$(date +%d%m%Y_%H%M)"

# Global temp file
export TEMP_FILE="`mktemp`_temp"

# JOB_NAME is a prefix for files, which is the name of current script directory
export JOB_NAME="$(basename "$SCRIPT_DIR")"
export SHELL_JUNIT_XML="$SCRIPT_DIR/${JOB_NAME}_1_sys_junit.xml"
export PKG_JUNIT_XML="$SCRIPT_DIR/${JOB_NAME}_2_pkg_junit.xml"
export E2E_JUNIT_XML="$SCRIPT_DIR/${JOB_NAME}_3_e2e_junit.xml"
export LIGHTHOUSE_JUNIT_XML="$SCRIPT_DIR/${JOB_NAME}_4_lighthouse_junit.xml"

export E2E_LOG="$SCRIPT_DIR/${JOB_NAME}_e2e_output.log"
> "$E2E_LOG"

# Set SYS_LOG name according to REPORT_NAME (from subm_variables)
export REPORT_NAME="${REPORT_NAME:-Submariner Tests}"
# SYS_LOG="${REPORT_NAME// /_}" # replace all spaces with _
# SYS_LOG="${SYS_LOG}_${DATE_TIME}.log" # can also consider adding timestamps with: ts '%H:%M:%.S' -s
SYS_LOG="${SCRIPT_DIR}/${JOB_NAME}_${DATE_TIME}.log" # can also consider adding timestamps with: ts '%H:%M:%.S' -s
> "$SYS_LOG"

# Common test variables
export NEW_NETSHOOT_CLUSTER_A="${NETSHOOT_CLUSTER_A}-new" # A NEW Netshoot pod on cluster A
export HEADLESS_TEST_NS="${TEST_NS}-headless" # Namespace for the HEADLESS $NGINX_CLUSTER_B service

### Store dynamic variable values in local files

# The default script exit code is 1 (later it is updated)
export SCRIPT_RC=1

# File to store test status. Resetting to empty - before running tests (i.e. don't publish to Polarion yet)
export TEST_STATUS_FILE="$SCRIPT_DIR/test_status.out"
> $TEST_STATUS_FILE

# File to store OCP cluster A version
export CLUSTER_A_VERSION_FILE="$SCRIPT_DIR/cluster_a.ver"
> $CLUSTER_A_VERSION_FILE

# File to store OCP cluster B version
export CLUSTER_B_VERSION_FILE="$SCRIPT_DIR/cluster_b.ver"
> $CLUSTER_B_VERSION_FILE

# File to store OCP cluster C version
export CLUSTER_C_VERSION_FILE="$SCRIPT_DIR/cluster_c.ver"
> $CLUSTER_C_VERSION_FILE

# File to store SubCtl version
export SUBCTL_VERSION_FILE="$SCRIPT_DIR/subctl.ver"
> $SUBCTL_VERSION_FILE

# File to store SubCtl JOIN command for cluster A
export SUBCTL_JOIN_CLUSTER_A_FILE="$SCRIPT_DIR/subctl_join_cluster_a.cmd"
> $SUBCTL_JOIN_CLUSTER_A_FILE

# File to store SubCtl JOIN command for cluster B
export SUBCTL_JOIN_CLUSTER_B_FILE="$SCRIPT_DIR/subctl_join_cluster_b.cmd"
> $SUBCTL_JOIN_CLUSTER_B_FILE

# File to store SubCtl JOIN command for cluster C
export SUBCTL_JOIN_CLUSTER_C_FILE="$SCRIPT_DIR/subctl_join_cluster_c.cmd"
> $SUBCTL_JOIN_CLUSTER_C_FILE

# File to store Polarion auth
export POLARION_AUTH="$SCRIPT_DIR/polarion.auth"
> $POLARION_AUTH

# File to store Polarion test-run report link
export POLARION_REPORTS="$SCRIPT_DIR/polarion.reports"
> $POLARION_REPORTS


####################################################################################
#                              CLI Script inputs                                   #
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
    destroy_cluster_a=YES
    shift ;;
  --create-cluster-a)
    create_cluster_a=YES
    shift ;;
  --reset-cluster-a)
    reset_cluster_a=YES
    shift ;;
  --clean-cluster-a)
    clean_cluster_a=YES
    shift ;;
  --destroy-cluster-b)
    destroy_cluster_b=YES
    shift ;;
  --create-cluster-b)
    create_cluster_b=YES
    shift ;;
  --reset-cluster-b)
    reset_cluster_b=YES
    shift ;;
  --clean-cluster-b)
    clean_cluster_b=YES
    shift ;;
  --destroy-cluster-c)
    destroy_cluster_c=YES
    shift ;;
  --create-cluster-c)
    create_cluster_c=YES
    shift ;;
  --reset-cluster-c)
    reset_cluster_c=YES
    shift ;;
  --clean-cluster-c)
    clean_cluster_c=YES
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
  --skip-install)
    skip_install=YES
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
    echo "# Importing additional variables from file: $GLOBAL_VARS"
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
#              Get User inputs (only for missing CLI inputs)                       #
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

    # User input: $reset_cluster_a - to destroy_aws_cluster AND create_aws_cluster
    while [[ ! "$reset_cluster_a" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to destroy & create AWS cluster A ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      reset_cluster_a=${input:-no}
    done

    # User input: $clean_cluster_a - to clean cluster A
    if [[ "$reset_cluster_a" =~ ^(no|n)$ ]]; then
      while [[ ! "$clean_cluster_a" =~ ^(yes|no)$ ]]; do
        echo -e "\n${YELLOW}Do you want to clean AWS cluster A ? ${NO_COLOR}
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

    # User input: $reset_cluster_c - to destroy_aws_cluster AND create_cluster_c
    while [[ ! "$reset_cluster_c" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to destroy & create OSP cluster C ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      reset_cluster_c=${input:-no}
    done

    # User input: $clean_cluster_c - to clean cluster C
    if [[ "$reset_cluster_c" =~ ^(no|n)$ ]]; then
      while [[ ! "$clean_cluster_c" =~ ^(yes|no)$ ]]; do
        echo -e "\n${YELLOW}Do you want to clean OSP cluster C ? ${NO_COLOR}
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

  # User input: $download_subctl and SUBM_VER_TAG - to download_and_install_subctl
  if [[ "$download_subctl" =~ ^(yes|y)$ ]]; then
    while [[ ! "$SUBM_VER_TAG" =~ ^[0-9a-Z]+$ ]]; do
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

  # User input: $skip_install - to skip submariner deployment
  while [[ ! "$skip_install" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to run without deploying Submariner ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    skip_install=${input:-NO}
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

### Set CLI/User inputs - Default to "NO" for any unset value ###

get_ocp_installer=${get_ocp_installer:-NO}
# OCP_VERSION=${OCP_VERSION}
get_ocpup_tool=${get_ocpup_tool:-NO}
# build_operator=${build_operator:-NO} # [DEPRECATED]
build_go_tests=${build_go_tests:-NO}
download_subctl=${download_subctl:-NO}
# SUBM_VER_TAG=${SUBM_VER_TAG}
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
globalnet=${globalnet:-NO}
# subm_cable_driver=${subm_cable_driver:-libreswan} [Deprecated]
config_golang=${config_golang:-NO}
config_aws_cli=${config_aws_cli:-NO}
skip_ocp_setup=${skip_ocp_setup:-NO}
skip_install=${skip_install:-NO}
skip_tests=${skip_tests:-NO}
print_logs=${print_logs:-NO}
create_junit_xml=${create_junit_xml:-NO}
upload_to_polarion=${upload_to_polarion:-NO}
script_debug_mode=${script_debug_mode:-NO}


####################################################################################
#                             Main script functions                                #
####################################################################################

# ------------------------------------------

function show_test_plan() {
  PROMPT "Input parameters and Test Plan steps"

  if [[ "$skip_ocp_setup" =~ ^(y|yes)$ ]]; then
    echo -e "\n# Skipping OCP clusters setup (destroy / create / clean): $skip_ocp_setup \n"
  else
    echo "### Will execute: Openshift clusters creation/cleanup before Submariner deployment:

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

    OSP cluster C:
    - destroy_cluster_c: $destroy_cluster_c
    - create_cluster_c: $create_cluster_c
    - reset_cluster_c: $reset_cluster_c
    - clean_cluster_c: $clean_cluster_c
    "
  fi

  if [[ "$skip_install" =~ ^(y|yes)$ ]]; then
    echo -e "\n# Skipping deployment and preparations: $skip_install \n"
  else
    echo "### Will execute: Submariner deployment and environment preparations:

    OCP and Submariner setup and test tools:
    - config_golang: $config_golang
    - config_aws_cli: $config_aws_cli
    - build_ocpup_tool_latest: $get_ocpup_tool
    - build_operator_latest: $build_operator # [DEPRECATED]
    - build_submariner_repos: $build_go_tests
    - download_and_install_subctl: $SUBM_VER_TAG
    "

    echo -e "# Submariner deployment and environment setup for the tests:

    - configure_custom_registry_cluster_a: $registry_images
    - configure_custom_registry_cluster_b / c: $registry_images
    - test_kubeconfig_cluster_a
    - test_kubeconfig_cluster_b / c
    - download_subctl: $SUBM_VER_TAG
    - install_netshoot_app_on_cluster_a
    - install_nginx_svc_on_cluster_b / c
    - test_basic_cluster_connectivity_before_submariner
    - test_clusters_disconnected_before_submariner
    - open_firewall_ports_on_the_broker_node (\"prep_for_subm.sh\")
    - open_firewall_ports_on_openstack_cluster_b (\"configure_osp.sh\")
    - label_gateway_on_broker_nodes_with_external_ip
    - label_first_gateway_cluster_b / c
    - install_broker_cluster_a
    - set_join_parameters_for_cluster_a
    - set_join_parameters_for_cluster_b / c
    - run_subctl_join_on_cluster_a
    - run_subctl_join_on_cluster_b / c
    $([[ ! "$globalnet" =~ ^(y|yes)$ ]] || echo "- test globalnet") \
    "
  fi

  # TODO: Should add function to manipulate opetshift clusters yamls, to have overlapping CIDRs

  if [[ "$skip_tests" =~ ((sys|all)(,|$))+ ]]; then
    echo -e "\n# Skipping high-level (system) tests: $skip_tests \n"
  else
  echo -e "\n### Will execute: High-level (System) tests of Submariner:

    - test_submariner_resources_cluster_a
    - test_submariner_resources_cluster_b / c
    - test_public_ip_on_gateway_node
    - test_disaster_recovery_of_gateway_nodes
    - test_renewal_of_gateway_and_public_ip
    - test_cable_driver_cluster_a
    - test_cable_driver_cluster_b / c
    - test_subctl_show_and_validate_on_merged_kubeconfigs
    - test_ha_status_cluster_a
    - test_ha_status_cluster_b / c
    - test_submariner_connection_cluster_a
    - test_submariner_connection_cluster_b / c
    - test_globalnet_status_cluster_a: $globalnet
    - test_globalnet_status_cluster_b / c: $globalnet
    - export_nginx_default_namespace_cluster_b / c
    - export_nginx_headless_namespace_cluster_b / c
    - test_lighthouse_status_cluster_a
    - test_lighthouse_status_cluster_b / c
    - test_clusters_connected_by_service_ip
    - install_new_netshoot_cluster_a
    - install_nginx_headless_namespace_cluster_b / c
    - test_clusters_connected_overlapping_cidrs: $globalnet
    - test_new_netshoot_global_ip_cluster_a: $globalnet
    - test_nginx_headless_global_ip_cluster_b / c: $globalnet
    - test_clusters_connected_full_domain_name
    - test_clusters_cannot_connect_short_service_name
    - test_clusters_connected_headless_service_on_new_namespace
    - test_clusters_cannot_connect_headless_short_service_name
    "
  fi

  if [[ "$skip_tests" =~ ((pkg|all)(,|$))+ ]]; then
    echo -e "\n# Skipping Submariner unit-tests: $skip_tests \n"
  else
    echo -e "\n### Will execute: Unit-tests (Ginkgo Packages) of Submariner:

    - test_submariner_packages
    "
  fi

  if [[ "$skip_tests" =~ ((e2e|all)(,|$))+ ]]; then
    echo -e "\n# Skipping Submariner E2E tests: $skip_tests \n"
  else
    echo -e "\n### Will execute: End-to-End (Ginkgo E2E) tests of Submariner:

    - test_submariner_e2e_with_go: $([[ "$build_go_tests" =~ ^(y|yes)$ ]] && echo 'YES' || echo 'NO' )
    - test_submariner_e2e_with_subctl: $([[ ! "$build_go_tests" =~ ^(y|yes)$ ]] && echo 'YES' || echo 'NO' )
    "
  fi

  echo -e "\n\n### All environment parameters: \n"
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
  PROMPT "Configuring workspace (Golang, AWS-CLI, Terraform, Polarion) in: ${WORKDIR}"
  trap '' DEBUG # DONT trap_to_debug_commands

  # Create WORKDIR and local BIN dir (if not yet exists)
  mkdir -p ${WORKDIR}
  mkdir -p $HOME/.local/bin

  # Add local BIN dir to PATH
  [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

  # # CD to main working directory
  # cd ${WORKDIR}

  # Installing GoLang with Anaconda, if $config_golang = yes/y
  if [[ "$config_golang" =~ ^(y|yes)$ ]] ; then
    install_anaconda "${WORKDIR}"

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

  # # Installing Terraform
  # install_local_terraform "${WORKDIR}"
  BUG "Terraform v0.13.x is not supported when using Submariner Terraform scripts" \
  "Use Terraform v0.12.29" \
  "https://github.com/submariner-io/submariner/issues/847"
  # Workaround:
  install_local_terraform "${WORKDIR}" "0.12.29"

  echo "# Installing JQ (JSON processor) with Anaconda"
  install_local_jq "${WORKDIR}"

  # Set Polarion access if $upload_to_polarion = yes/y
  if [[ "$upload_to_polarion" =~ ^(y|yes)$ ]] ; then
    echo "# Set Polarion access for the user [$POLARION_USR]"
    ( # subshell to hide commands
      local polauth=$(echo "${POLARION_USR}:${POLARION_PWD}" | base64 --wrap 0)
      echo "--header \"Authorization: Basic ${polauth}\"" > "$POLARION_AUTH"
    )
  fi

  # Trim trailing and leading spaces from $TEST_NS
  TEST_NS="$(echo "$TEST_NS" | xargs)"

  # Installing AWS-CLI if $config_aws_cli = yes/y
  if [[ "$config_aws_cli" =~ ^(y|yes)$ ]] ; then
    echo "# Installing AWS-CLI, and setting Profile [$AWS_PROFILE_NAME] and Region [$AWS_REGION]"
    ( # subshell to hide commands
    configure_aws_access \
    "${AWS_PROFILE_NAME}" "${AWS_REGION}" "${AWS_KEY}" "${AWS_SECRET}" "${WORKDIR}" "${GOBIN}"
    )
  fi

  # # CD to previous directory
  # cd -
}

# ------------------------------------------

function set_trap_functions() {
  PROMPT "Configuring trap functions on script exit"

  echo "# Will run env_teardown() when exiting the script"
  trap 'env_teardown' EXIT

  if [[ "$print_logs" =~ ^(y|yes)$ ]]; then
    echo "# Will collect Submariner information on test failure (CLI option --print-logs)"
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

  local ocp_major_version="$(echo $ocp_installer_version | cut -s -d '.' -f 1)" # Get the major digit of OCP version
  local ocp_major_version="${ocp_major_version:-4}" # if no numerical version was requested (e.g. "latest"), the default OCP major version is 4
  local oc_version_path="ocp/${ocp_installer_version}"

  # Get the nightly (ocp-dev-preview) build ?
  if [[ "$oc_version_path" =~ nightly ]] ; then
    oc_version_path="ocp-dev-preview/latest"
    # Also available at: https://openshift-release-artifacts.svc.ci.openshift.org/
  fi

  cd ${WORKDIR}

  ocp_url="https://mirror.openshift.com/pub/openshift-v${ocp_major_version}/clients/${oc_version_path}/"
  ocp_install_gz=$(curl $ocp_url | grep -Eoh "openshift-install-linux-.+\.tar\.gz" | cut -d '"' -f 1)
  oc_client_gz=$(curl $ocp_url | grep -Eoh "openshift-client-linux-.+\.tar\.gz" | cut -d '"' -f 1)

  [[ -n "$ocp_install_gz" && -n "$oc_client_gz" ]] || FATAL "Failed to retrieve OCP installer [${ocp_installer_version}] from $ocp_url"

  echo "# Deleting previous OCP installers, and downloading: [$ocp_install_gz], [$oc_client_gz]."
  # find -type f -maxdepth 1 -name "openshift-*.tar.gz" -mtime +1 -exec rm -rf {} \;
  delete_old_files_or_dirs "openshift-*.tar.gz"

  download_file ${ocp_url}${ocp_install_gz}
  download_file ${ocp_url}${oc_client_gz}

  tar -xvf ${ocp_install_gz} -C ${WORKDIR}
  tar -xvf ${oc_client_gz} -C ${WORKDIR}

  echo "# Install OC (Openshift Client tool) into ${GOBIN}:"
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

  verify_golang || FATAL "No Golang installation found. Try to run again with option '--config-golang'"

  # TODO: Need to fix ocpup alias

  cd ${WORKDIR}
  # rm -rf ocpup # We should not remove directory, as it may included previous install config files
  git clone https://github.com/dimaunx/ocpup || echo "# OCPUP directory already exists"
  cd ocpup

  # To cleanup GOLANG mod files:
    # go clean -cache -modcache -i -r

  git_reset_local_repo

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

function build_submariner_repos() {
### Building latest Submariner code and tests ###
  PROMPT "Building latest Submariner-IO projects code, including test packages (unit-tests and E2E)"
  trap_to_debug_commands;

  verify_golang || FATAL "No Golang installation found. Try to run again with option '--config-golang'"

  local branch_or_tag # To pull

  echo "# Retrieve correct branch to pull for Submariner version '$SUBM_VER_TAG'"
  if [[ "$SUBM_VER_TAG" =~ latest ]]; then
    local branch_or_tag="$(get_latest_subctl_version_tag)"
  elif [[ "$SUBM_VER_TAG" =~ ^[0-9] ]]; then
    echo "# Version ${SUBM_VER_TAG} is considered as 'v${SUBM_VER_TAG}' tag"
    local branch_or_tag="v${SUBM_VER_TAG}"
  fi

  build_go_repo "https://github.com/submariner-io/submariner" $branch_or_tag

  build_go_repo "https://github.com/submariner-io/lighthouse" $branch_or_tag
}

# ------------------------------------------

function build_operator_latest() {  # [DEPRECATED]
### Building latest Submariner-Operator code and SubCTL tool ###
  PROMPT "Building latest Submariner-Operator code and SubCTL tool"
  trap_to_debug_commands;

  verify_golang || FATAL "No Golang installation found. Try to run again with option '--config-golang'"

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

  echo "# Build SubCtl tool and install it in $GOBIN/"

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
  export DAPPER_SOURCE="$(git rev-parse --show-toplevel)"

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

function download_and_install_subctl() {
  ### Download SubCtl - Submariner installer - Latest RC release ###
    PROMPT "Testing \"getsubctl.sh\" to download and use SubCtl version $SUBM_VER_TAG"

    set_subm_version_tag_var

    download_subctl_by_tag "$SUBM_VER_TAG"

}

# ------------------------------------------

function download_subctl_by_tag() {
  ### Download SubCtl - Submariner installer ###
    trap_to_debug_commands;

    # Optional param: $1 => SubCtl version by tag to download
    # If not specifying a tag - it will download latest version released (not latest subctl-devel)
    local subctl_tag="${1:-v[0-9]}"

    local regex="tag/.*\K${subctl_tag}[^\"]*"
    local repo_url="https://github.com/submariner-io/submariner-operator"
    local repo_tag="`curl "$repo_url/tags/" | grep -Po -m 1 "$regex"`"

    cd ${WORKDIR}

    # Download SubCtl from SUBCTL_REGISTRY_MIRROR, if using --registry-images and if subctl_tag is not devel
    if [[ ! "$subctl_tag" =~ devel ]] && \
        [[ "$registry_images" =~ ^(y|yes)$ ]] && \
        [[ -n "$SUBCTL_PRIVATE_URL" ]] ; then

      echo "# Downloading SubCtl from $SUBCTL_PRIVATE_URL"

      # Update $subctl_tag value
      set_subm_version_tag_var "subctl_tag"

      local subctl_image_url="${SUBCTL_REGISTRY_MIRROR}/${REGISTRY_IMAGE_PREFIX}${SUBM_IMG_SUBCTL}:${subctl_tag}"
      # e.g. subctl_image_url="registry-proxy.engineering.redhat.com/rh-osbs/rhacm2-tech-preview-subctl-rhel8:0.9"

      local subctl_xz="subctl-${subctl_tag}-linux-amd64.tar.xz"

      ${OC} image extract $subctl_image_url --path=/dist/${subctl_xz}:./ --confirm

      echo "# SubCtl binary will be extracted from [${subctl_xz}] downloaded from $subctl_image_url"
      tar -xvf ${subctl_xz} --strip-components 1 --wildcards --no-anchored  "subctl*"

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

    else
      echo "# Downloading SubCtl from upstream URL: $releases_url"
      # curl https://get.submariner.io/ | VERSION=${subctl_tag} bash -x
      BUG "getsubctl.sh fails on an unexpected argument, since the local 'install' is not the default" \
      "set 'PATH=/usr/bin:$PATH' for the execution of 'getsubctl.sh'" \
      "https://github.com/submariner-io/submariner-operator/issues/473"
      # Workaround:
      PATH="/usr/bin:$PATH" which install

      #curl https://get.submariner.io/ | VERSION=${subctl_tag} PATH="/usr/bin:$PATH" bash -x
      BUG "getsubctl.sh sometimes fails on error 403 (rate limit exceeded)" \
      "If it has failed - Set 'getsubctl_status=FAILED' in order to download with wget instead" \
      "https://github.com/submariner-io/submariner-operator/issues/526"
      # Workaround:
      curl https://get.submariner.io/ | VERSION="${repo_tag}" PATH="/usr/bin:$PATH" bash -x || getsubctl_status=FAILED

      if [[ "$getsubctl_status" = FAILED ]] ; then
        releases_url="${repo_url}/releases"
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
    subctl version > "$SUBCTL_VERSION_FILE"

}

# ------------------------------------------

function get_latest_subctl_version_tag() {
  ### Print the tag of latest subctl version released ###

  local subctl_tag="v[0-9]"
  local regex="tag/.*\K${subctl_tag}[^\"]*"
  local repo_url="https://github.com/submariner-io/submariner-operator"
  local subm_release_version="`curl "$repo_url/tags/" | grep -Po -m 1 "$regex"`"

  echo $subm_release_version
}

# ------------------------------------------

function test_subctl_command() {
  trap_to_debug_commands;
  # Get SubCTL version (from file $SUBCTL_VERSION_FILE)
  # local subctl_version="$([[ ! -s "$SUBCTL_VERSION_FILE" ]] || cat "$SUBCTL_VERSION_FILE")"
  local subctl_version="$(subctl version | awk '{print $3}')"

  PROMPT "Verifying Submariner CLI tool ${subctl_version:+ ($subctl_version)}"

  [[ -x "$(command -v subctl)" ]] || FATAL "No SubCtl installation found. Try to run again with option '--subctl-version'"
  subctl version

  subctl --help

}

# ------------------------------------------

function prepare_install_aws_cluster() {
### Prepare installation files for AWS cluster A (public) ###
  PROMPT "Preparing installation files for AWS cluster A (public)"
  trap_to_debug_commands;
  # Using existing OCP install-config.yaml - make sure to have it in the workspace.

  local ocp_install_dir="$1"
  local installer_yaml_source="$2"
  local cluster_name="$3"

  cd ${WORKDIR}
  [[ -f openshift-install ]] || FATAL "OCP Installer is missing. Try to run again with option '--get-ocp-installer [latest / x.y.z]'"

  if [[ -d "$ocp_install_dir" ]] && [[ -n `ls -A "$ocp_install_dir"` ]] ; then
    FATAL "$ocp_install_dir directory contains previous deployment configuration. It should be initially removed."
  fi

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
  cp -f "${installer_yaml_source}" "$installer_yaml_new"
  chmod 777 "$installer_yaml_new"

  echo "# Update the OCP installer configuration (YAML) of AWS cluster $cluster_name"
  [[ -z "$cluster_name" ]] || change_yaml_key_value "$installer_yaml_new" "name" "$cluster_name" "metadata"
  [[ -z "$AWS_REGION" ]] || change_yaml_key_value "$installer_yaml_new" "region" "$AWS_REGION"

  # TODO: change more {keys : values} in $installer_yaml_new, from the global variables file

}

# ------------------------------------------

function create_aws_cluster() {
### Create AWS cluster A (public) with OCP installer ###
  trap_to_debug_commands;
  local ocp_install_dir="$1"
  local cluster_name="$2"

  PROMPT "Creating AWS cluster A (public): $cluster_name"

  # Run OCP installer with the user-cluster-a.yaml:
  cd ${ocp_install_dir}
  ../openshift-install create cluster --log-level debug

  # To tail all OpenShift Installer logs (in a new session):
    # find . -name "*.log" | xargs tail -f

  # Login to the new created cluster:
    # $ grep "Access the OpenShift web-console" -r . --include='*.log' -A 1
      # "Access the OpenShift web-console here: https://console-openshift-console.apps..."
      # "Login to the console with user: kubeadmin, password: ..."
}

# ------------------------------------------

function create_osp_cluster() {
### Create Openstack cluster B (on-prem) with OCPUP tool ###
  PROMPT "Creating Openstack cluster B (on-prem) with OCP-UP tool"
  trap_to_debug_commands;

  cd "${OCPUP_DIR}"
  [[ -x "$(command -v ocpup)" ]] || FATAL "OCPUP tool is missing. Try to run again with option '--get-ocpup-tool'"

  local terraform_osp_provider="./tf/osp-sg/versions.tf"

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

  echo -e "# Using an existing OCPUP yaml configuration file: \n${CLUSTER_B_YAML}"
  cp -f "${CLUSTER_B_YAML}" ./ || FATAL "OCPUP yaml configuration file is missing."

  ocpup_yml=$(basename -- "$CLUSTER_B_YAML")
  ls -l "$ocpup_yml"

  local ocpup_cluster_name="$(awk '/clusterName:/ {print $NF}' $ocpup_yml)"
  local ocpup_project_name="$(awk '/projectName:/ {print $NF}' $ocpup_yml)"
  local ocpup_user_name="$(awk '/userName:/ {print $NF}' $ocpup_yml)"

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

function test_kubeconfig_cluster_a() {
# Check that AWS cluster A (public) is up and running

  # Get OCP cluster A version (from file $CLUSTER_A_VERSION_FILE)
  cl_a_version="$([[ ! -s "$CLUSTER_A_VERSION_FILE" ]] || cat "$CLUSTER_A_VERSION_FILE")"

  PROMPT "Testing status of cluster $CLUSTER_A_NAME ${cl_a_version:+(OCP Version $cl_a_version)}"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  test_cluster_status "$CLUSTER_A_NAME"
  cl_a_version=$(${OC} version | awk '/Server Version/ { print $3 }')
  echo "$cl_a_version" > "$CLUSTER_A_VERSION_FILE"

  # ${OC} set env dc/dcname TZ=Asia/Jerusalem
}

# ------------------------------------------

function test_kubeconfig_cluster_b() {
# Check that OSP cluster B (on-prem) is up and running

  # Get OCP cluster B version (from file $CLUSTER_B_VERSION_FILE)
  cl_b_version="$([[ ! -s "$CLUSTER_B_VERSION_FILE" ]] || cat "$CLUSTER_B_VERSION_FILE")"

  PROMPT "Testing status of cluster $CLUSTER_B_NAME ${cl_b_version:+(OCP Version $cl_b_version)}"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  test_cluster_status "$CLUSTER_B_NAME"
  cl_b_version=$(${OC} version | awk '/Server Version/ { print $3 }')
  echo "$cl_b_version" > "$CLUSTER_B_VERSION_FILE"

  # ${OC} set env dc/dcname TZ=Asia/Jerusalem
}

# ------------------------------------------

function test_kubeconfig_cluster_c() {
# Check that cluster C is up and running

  # Get OCP cluster C version (from file $CLUSTER_C_VERSION_FILE)
  cl_c_version="$([[ ! -s "$CLUSTER_C_VERSION_FILE" ]] || cat "$CLUSTER_C_VERSION_FILE")"

  PROMPT "Testing status of cluster C${cl_c_version:+ (OCP Version $cl_c_version)}"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  test_cluster_status "$CLUSTER_C_NAME"
  cl_c_version=$(${OC} version | awk '/Server Version/ { print $3 }')
  echo "$cl_c_version" > "$CLUSTER_C_VERSION_FILE"

  # ${OC} set env dc/dcname TZ=Asia/Jerusalem
}

# ------------------------------------------

function test_cluster_status() {
  # Verify that current kubeconfig cluster is up and healthy
  trap_to_debug_commands;

  local cluster_name="$1"
  [[ -f ${KUBECONFIG} ]] || FATAL "Openshift deployment configuration for '$cluster_name' is missing: ${KUBECONFIG}"

  # echo "# Modify KUBECONFIG current-context name to: ${cluster_name}"
  # sed -z "s#name: [a-zA-Z0-9-]*\ncurrent-context: [a-zA-Z0-9-]*#name: ${cluster_name}\ncurrent-context: ${cluster_name}#" -i.bak ${KUBECONFIG}
  # ${OC} config set "current-context" "$cluster_name"

  local cur_context="$(${OC} config current-context)" # $cur_context should be equal to $cluster_name
  if [[ ! "$cur_context" = "${cluster_name}" ]] ; then

    BUG "E2E will fail if clusters have same name (default is \"admin\")" \
    "Modify KUBECONFIG cluster context name on both clusters to be unique" \
    "https://github.com/submariner-io/submariner/issues/245"

    BUG "E2E will fail if cluster id is not equal to cluster name" \
    "Modify KUBECONFIG context cluster name = cluster id" \
    "https://bugzilla.redhat.com/show_bug.cgi?id=1928805"

    echo "# Modify KUBECONFIG current-context '${cur_context}' to: ${cluster_name}"
    ${OC} config rename-context "${cur_context}" "${cluster_name}" || :
    ${OC} config use-context "${cluster_name}"
  fi

  echo "# Set KUBECONFIG context '$cluster_name' namespace to 'default'"
  ${OC} config set "contexts.${cluster_name}.namespace" "default"

  ${OC} config view
  ${OC} status || FATAL "Openshift cluster is not installed, or using bad context '$cluster_name' in kubeconfig: ${KUBECONFIG}"
  ${OC} version
  ${OC} get all
    # NAME                 TYPE           CLUSTER-IP   EXTERNAL-IP                            PORT(S)   AGE
    # service/kubernetes   clusterIP      172.30.0.1   <none>                                 443/TCP   39m
    # service/openshift    ExternalName   <none>       kubernetes.default.svc.cluster.local   <none>    32m

  wait_for_all_nodes_ready
}

# ------------------------------------------

function destroy_aws_cluster() {
### Destroy your previous AWS cluster (public) ###
  trap_to_debug_commands;
  local ocp_install_dir="$1"
  local cluster_name="$2"

  PROMPT "Destroying previous AWS cluster: $cluster_name"
  trap_to_debug_commands;

  # Temp - CD to main working directory
  cd ${WORKDIR}

  aws --version || FATAL "AWS-CLI is missing. Try to run again with option '--config-aws-cli'"

  # Only if your AWS cluster still exists (less than 48 hours passed) - run destroy command:
  # TODO: should first check if it was not already purged, because it can save a lot of time.
  if [[ -d "${ocp_install_dir}" ]]; then
    echo "# Previous OCP Installation found: ${ocp_install_dir}"
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

    echo "# Backup previous OCP install-config directory of cluster ${cluster_name}"
    parent_dir=$(dirname -- "$ocp_install_dir")
    base_dir=$(basename -- "$ocp_install_dir")
    backup_and_remove_dir "$ocp_install_dir" "${parent_dir}/_${base_dir}_${DATE_TIME}"

    # Remove existing OCP install-config directory:
    #rm -r "_${ocp_install_dir}/" || echo "# Old config dir removed."
    echo "# Deleting all previous ${ocp_install_dir} config directories (older than 1 day):"
    # find -type d -maxdepth 1 -name "_*" -mtime +1 -exec rm -rf {} \;
    delete_old_files_or_dirs "${parent_dir}/_${base_dir}_*" "d" 1
  else
    echo "# OCP cluster config (metadata.json) was not found in ${ocp_install_dir}. Skipping cluster Destroy."
  fi

  BUG "WARNING: OCP destroy command does not remove the previous DNS record sets from AWS Route53" \
  "Delete previous DNS record sets from AWS Route53" \
  "---"
  # Workaround:

  # set AWS DNS record sets to be deleted
  AWS_DNS_ALIAS1="api.${cluster_name}.${AWS_ZONE_NAME}."
  AWS_DNS_ALIAS2="\052.apps.${cluster_name}.${AWS_ZONE_NAME}."

  echo -e "# Deleting AWS DNS record sets from Route53:
  # $AWS_DNS_ALIAS1
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
  PROMPT "Destroying previous Openstack cluster B (on-prem)"
  trap_to_debug_commands;

  cd "${OCPUP_DIR}"
  [[ -x "$(command -v ocpup)" ]] || FATAL "OCPUP tool is missing. Try to run again with option '--get-ocpup-tool'"

  if [[ -f "${CLUSTER_B_DIR}/metadata.json" ]] ; then
    echo -e "# Using an existing OCPUP yaml configuration file: \n${CLUSTER_B_YAML}"
    cp -f "${CLUSTER_B_YAML}" ./ || FATAL "OCPUP yaml configuration file is missing."

    ocpup_yml=$(basename -- "$CLUSTER_B_YAML")
    ls -l "$ocpup_yml"

    local ocpup_cluster_name="$(awk '/clusterName:/ {print $NF}' $ocpup_yml)"

    local ocp_cmd="ocpup destroy clusters ${DEBUG_FLAG} --config $ocpup_yml"
    local ocp_log="${OCPUP_DIR}/.config/${ocpup_cluster_name}/.openshift_install.log"

    run_and_tail "$ocp_cmd" "$ocp_log" 5m || BUG "OCP destroy cluster B did not complete as expected"

    # To tail all OpenShift Installer logs (in a new session):
      # find . -name "*openshift_install.log" | xargs tail --pid=$pid -f # tail ocpup/.config/${ocpup_cluster_name}/.openshift_install.log

    echo "# Backup previous OCP install-config directory of cluster ${CLUSTER_B_NAME} "
    backup_and_remove_dir ".config"
  else
    echo "# OCP cluster config (metadata.json) was not found in ${CLUSTER_B_DIR}. Skipping cluster Destroy."
  fi
}


# ------------------------------------------

function clean_submariner_namespace_and_resources_cluster_a() {
### Run cleanup of previous Submariner on AWS cluster A (public) ###
  PROMPT "Cleaning previous Submariner (Namespaces, OLM, CRDs, Cluster Roles, ServiceExports) on AWS cluster A (public)"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  clean_submariner_namespace_and_resources
}

# ------------------------------------------

function clean_submariner_namespace_and_resources_cluster_b() {
### Run cleanup of previous Submariner on OSP cluster B (on-prem) ###
  PROMPT "Cleaning previous Submariner (Namespaces, OLM, CRDs, Cluster Roles, ServiceExports) on OSP cluster B (on-prem)"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  clean_submariner_namespace_and_resources
}

# ------------------------------------------

function clean_submariner_namespace_and_resources_cluster_c() {
### Run cleanup of previous Submariner on cluster C ###
  PROMPT "Cleaning previous Submariner (Namespaces, OLM, CRDs, Cluster Roles, ServiceExports) on cluster C"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
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

  delete_namespace_and_crds "${SUBM_NAMESPACE}" "submariner"

  # Required if Broker cluster is not a Dataplane cluster as well:
  delete_namespace_and_crds "${BROKER_NAMESPACE}"

}

# ------------------------------------------

function delete_submariner_cluster_roles() {
### Run cleanup of previous Submariner ClusterRoles and ClusterRoleBindings ###
  trap_to_debug_commands;

  echo "# Deleting Submariner ClusterRoles and ClusterRoleBindings"

  local roles="submariner-operator submariner-operator-globalnet submariner-lighthouse submariner-networkplugin-syncer"

  ${OC} delete clusterrole,clusterrolebinding $roles --ignore-not-found || :

}

# ------------------------------------------

function delete_lighthouse_dns_list() {
### Run cleanup of previous Lighthouse ServiceExport DNS list ###
  trap_to_debug_commands;

  echo "# Clean Lighthouse ServiceExport DNS list:"

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

  echo "# Deleting Submariner test namespaces: '$TEST_NS' '$HEADLESS_TEST_NS'"

  for ns in "$TEST_NS" "$HEADLESS_TEST_NS" ; do
    if [[ -n "$ns" ]]; then
      delete_namespace_and_crds "$ns"
      # create_namespace "$ns"
    fi
  done

  echo "# Unset Submariner test namespaces from kubeconfig current context"
  local cur_context="$(${OC} config current-context)"
  ${OC} config unset "contexts.${cur_context}.namespace"

}

# ------------------------------------------

function delete_e2e_namespaces() {
### Delete previous Submariner E2E namespaces from current cluster ###
  trap_to_debug_commands;

  local e2e_namespaces="$(${OC} get ns -o=custom-columns=NAME:.metadata.name | grep e2e-tests | cat )"

  if [[ -n "$e2e_namespaces" ]] ; then
    echo "# Deleting all 'e2e-tests' namespaces: $e2e_namespaces"
    ${OC} delete --timeout=30s ns $e2e_namespaces
  else
    echo "No 'e2e-tests' namespaces exist to be deleted"
  fi

}

# ------------------------------------------

function clean_node_labels_and_machines_cluster_a() {
### Remove previous Submariner Gateway Node's Labels and MachineSets from AWS cluster A (public) ###
  PROMPT "Remove previous Submariner Gateway Node's Labels and MachineSets from AWS cluster A (public)"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

  remove_submariner_gateway_labels

  remove_submariner_machine_sets
}

# ------------------------------------------

function clean_node_labels_and_machines_cluster_b() {
### Remove previous Submariner Gateway Node's Labels and MachineSets from OSP cluster B (on-prem) ###
  PROMPT "Remove previous Submariner Gateway Node's Labels and MachineSets from OSP cluster B (on-prem)"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"

  remove_submariner_gateway_labels

  remove_submariner_machine_sets
}

# ------------------------------------------

function clean_node_labels_and_machines_cluster_c() {
### Remove previous Submariner Gateway Node's Labels and MachineSets from cluster C ###
  PROMPT "Remove previous Submariner Gateway Node's Labels and MachineSets from cluster C"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"

  remove_submariner_gateway_labels

  remove_submariner_machine_sets
}

# ------------------------------------------

function remove_submariner_gateway_labels() {
  trap_to_debug_commands;

  echo "# Remove previous submariner gateway labels from all node in the cluster:"

  ${OC} label --all node submariner.io/gateway- || :
}

# ------------------------------------------

function remove_submariner_machine_sets() {
  trap_to_debug_commands;

  echo "# Remove previous machineset (if it has a template with submariner gateway label)"

  local subm_machineset="`${OC} get machineset -A -o jsonpath='{.items[?(@.spec.template.spec.metadata.labels.submariner\.io\gateway=="true")].metadata.name}'`"
  local ns="`${OC} get machineset -A -o jsonpath='{.items[?(@.spec.template.spec.metadata.labels.submariner\.io\gateway=="true")].metadata.namespace}'`"

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
#   # Get SubCTL version (from file $SUBCTL_VERSION_FILE)
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

function configure_namespace_for_submariner_tests_on_cluster_a() {
  PROMPT "Configure namespace '${TEST_NS:-default}' for running tests on AWS cluster A (public)"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  configure_namespace_for_submariner_tests

}

# ------------------------------------------

function configure_namespace_for_submariner_tests_on_cluster_b() {
  PROMPT "Configure namespace '${TEST_NS:-default}' for running tests on OSP cluster B"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  configure_namespace_for_submariner_tests

}

# ------------------------------------------

function configure_namespace_for_submariner_tests_on_cluster_c() {
  PROMPT "Configure namespace '${TEST_NS:-default}' for running tests on cluster C"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  configure_namespace_for_submariner_tests

}

# ------------------------------------------

function configure_namespace_for_submariner_tests() {
  trap_to_debug_commands;

  echo "# Set the default namespace to "${TEST_NS}" (if TEST_NS parameter was set in variables file)"
  if [[ -n "$TEST_NS" ]] ; then
    echo "# Create namespace for Submariner tests: ${TEST_NS}"
    create_namespace "${TEST_NS}"
  else
    echo "# Using the 'default' namespace for Submariner tests"
    export TEST_NS=default
  fi

  echo "# Backup current KUBECONFIG to: ${KUBECONFIG}.bak (if it doesn't exists already)"
  [[ -s ${KUBECONFIG}.bak ]] || cp -f "${KUBECONFIG}" "${KUBECONFIG}.bak"

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
  PROMPT "Install Netshoot application on AWS cluster A (public)"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

  [[ -z "$TEST_NS" ]] || create_namespace "${TEST_NS}"

  ${OC} delete pod ${NETSHOOT_CLUSTER_A} --ignore-not-found ${TEST_NS:+-n $TEST_NS} || :

  # NETSHOOT_CLUSTER_A=netshoot-cl-a # Already exported in global subm_variables

  # Deployment is terminated after netshoot is loaded - need to "oc run" with infinite loop
  # ${OC} delete deployment ${NETSHOOT_CLUSTER_A}  --ignore-not-found ${TEST_NS:+-n $TEST_NS}
  # ${OC} create deployment ${NETSHOOT_CLUSTER_A}  --image ${NETSHOOT_IMAGE} ${TEST_NS:+-n $TEST_NS}
  ${OC} run ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --image ${NETSHOOT_IMAGE} -- sleep infinity

  echo "# Wait up to 3 minutes for Netshoot pod [${NETSHOOT_CLUSTER_A}] to be ready:"
  ${OC} wait --timeout=3m --for=condition=ready pod -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
  ${OC} describe pod ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
}

# ------------------------------------------

function install_nginx_svc_on_cluster_b() {
  PROMPT "Install Nginx service on OSP cluster B${TEST_NS:+ (Namespace $TEST_NS)}"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"

  echo "# Creating ${NGINX_CLUSTER_B}:${NGINX_PORT} in ${TEST_NS}, using ${NGINX_IMAGE}, and disabling it's cluster-ip (with '--cluster-ip=None'):"

  install_nginx_service "${NGINX_CLUSTER_B}" "${NGINX_IMAGE}" "${TEST_NS}" "--port=${NGINX_PORT}"
}

# ------------------------------------------

function test_basic_cluster_connectivity_before_submariner() {
### Pre-test - Demonstrate that the clusters aren’t connected without Submariner ###
  PROMPT "Before Submariner is installed: Verifying IP connectivity on the SAME cluster"
  trap_to_debug_commands;

  # Trying to connect from cluster A to cluster B, will fails (after 5 seconds).
  # It’s also worth looking at the clusters to see that Submariner is nowhere to be seen.

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  echo -e "\n# Get IP of ${NGINX_CLUSTER_B} on OSP cluster B${TEST_NS:+(Namespace: $TEST_NS)} to verify connectivity:\n"

  ${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS}
  nginx_IP_cluster_b=$(${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')
    # nginx_cluster_b_ip: 100.96.43.129

  local netshoot_pod=netshoot-cl-b-new # A new Netshoot pod on cluster b
  echo "# Install $netshoot_pod on OSP cluster B, and verify connectivity on the SAME cluster, to ${nginx_IP_cluster_b}:${NGINX_PORT}"

  [[ -z "$TEST_NS" ]] || create_namespace "${TEST_NS}"

  ${OC} delete pod ${netshoot_pod} --ignore-not-found ${TEST_NS:+-n $TEST_NS} || :

  ${OC} run ${netshoot_pod} --attach=true --restart=Never --pod-running-timeout=3m --request-timeout=3m --rm -i \
  ${TEST_NS:+-n $TEST_NS} --image ${NETSHOOT_IMAGE} -- /bin/bash -c "curl --max-time 60 --verbose ${nginx_IP_cluster_b}:${NGINX_PORT}"
}

# ------------------------------------------

function test_clusters_disconnected_before_submariner() {
### Pre-test - Demonstrate that the clusters aren’t connected without Submariner ###
  PROMPT "Before Submariner is installed:
  Verifying that Netshoot pod on AWS cluster A (public), cannot reach Nginx service on OSP cluster B (on-prem)"
  trap_to_debug_commands;

  # Trying to connect from cluster A to cluster B, will fails (after 5 seconds).
  # It’s also worth looking at the clusters to see that Submariner is nowhere to be seen.

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  # nginx_IP_cluster_b=$(${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')
  ${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}' > "$TEMP_FILE"
  nginx_IP_cluster_b="$(< $TEMP_FILE)"
    # nginx_cluster_b_ip: 100.96.43.129

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  # ${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --field-selector status.phase=Running | awk 'FNR == 2 {print $1}' > "$TEMP_FILE"
  # netshoot_pod_cluster_a="$(< $TEMP_FILE)"
  netshoot_pod_cluster_a="`get_running_pod_by_label "run=${NETSHOOT_CLUSTER_A}" "$TEST_NS" `"

  msg="# Negative Test - Clusters should NOT be able to connect without Submariner."

  ${OC} exec $netshoot_pod_cluster_a ${TEST_NS:+-n $TEST_NS} -- \
  curl --output /dev/null --max-time 20 --verbose ${nginx_IP_cluster_b}:${NGINX_PORT} \
  |& (! highlight "command terminated with exit code" && FATAL "$msg") || echo -e "$msg"
    # command terminated with exit code 28
}

# ------------------------------------------

function open_firewall_ports_on_the_broker_node() {
### Open AWS Firewall ports on the gateway node with terraform (prep_for_subm.sh) ###
  # Readme: https://github.com/submariner-io/submariner/tree/devel/tools/openshift/ocp-ipi-aws
  PROMPT "Running \"prep_for_subm.sh\" - to add External IP and open ports on the Broker node in AWS cluster A (public)"
  trap_to_debug_commands;

  command -v terraform || FATAL "Terraform is required in order to run 'prep_for_subm.sh'"

  local git_user="submariner-io"
  local git_project="submariner"
  local commit_or_branch="release-0.8"
  local github_dir="tools/openshift/ocp-ipi-aws"
  local cluster_path="$CLUSTER_A_DIR"
  local target_path="${cluster_path}/${github_dir}"
  local terraform_script="prep_for_subm.sh"

  mkdir -p "${git_project}_scripts" && cd "${git_project}_scripts"

  download_github_file_or_dir "$git_user" "$git_project" "$commit_or_branch" "${github_dir}"

  BUG "'${terraform_script}' ignores local yamls and always download from devel branch" \
  "Copy '${github_dir}' directory (including '${terraform_script}') into OCP install dir" \
  "https://github.com/submariner-io/submariner/issues/880"
  # Workaround:

  echo "# Copy '${github_dir}' directory (including '${terraform_script}') to ${target_path}"
  mkdir -p "${target_path}"
  cp -rf "${github_dir}"/* "${target_path}"
  cd "${target_path}/"

  # Fix bug in terraform version
  sed -r 's/0\.12\.12/0\.12\.29/g' -i versions.tf || :

  # Fix bug in terraform provider permission denied
  chmod -R a+x ./.terraform/plugins/linux_amd64/* || :

  # Fix bug of using non-existing kubeconfig conext "admin"
  sed -e 's/--context=admin //g' -i "${terraform_script}"

  BUG "'prep_for_subm.sh' downloads remote 'ocp-ipi-aws', even if local 'ocp-ipi-aws' already exists" \
  "Modify 'prep_for_subm.sh' so it will download all 'ocp-ipi-aws/*' and do not change directory" \
  "----"
  # Workaround:
  sed 's/.*submariner_prep.*/# \0/' -i "${terraform_script}"

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

  BUG "Using the same IPSEC port numbers multiple times in one project, may be blocked on firewall" \
  "Make sure to use different IPSEC_NATT_PORT and IPSEC_IKE_PORT across clusters on same project" \
  "https://github.com/submariner-io/submariner-operator/issues/1047"
  # Workaround:
  # Do not use the same IPSEC port numbers multiple times in one project
  # export IPSEC_NATT_PORT=${IPSEC_NATT_PORT:-4501}
  # export IPSEC_IKE_PORT=${IPSEC_IKE_PORT:-501}

  export GW_INSTANCE_TYPE=${GW_INSTANCE_TYPE:-m4.xlarge}

  echo "# Running '${terraform_script} ${cluster_path} -auto-approve' script to apply Terraform 'ec2-resources.tf'"
  # bash -x ...
  ./${terraform_script} "${cluster_path}" -auto-approve |& highlight "Apply complete| already exists" \
  || FATAL "./${terraform_script} did not complete successfully"

  # Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
  # OR
  # Security group rule already exists.
  #

}

# ------------------------------------------

function open_firewall_ports_on_openstack_cluster_b() {
### Open AWS Firewall ports on the gateway node with terraform (configure_osp.sh) ###
  # Readme: https://github.com/sridhargaddam/configure-osp-for-subm
  PROMPT "Running \"configure_osp.sh\" - to open Firewall ports on all nodes in OSP cluster B (on-prem)"
  trap_to_debug_commands;

  command -v terraform || FATAL "Terraform is required in order to run 'configure_osp.sh'"

  local git_user="manosnoam"
  local git_project="configure-osp-for-subm"
  local commit_or_branch="main"
  local github_dir="osp-scripts"
  local cluster_path="$CLUSTER_B_DIR"
  local target_path="${cluster_path}/${github_dir}"
  local terraform_script="configure_osp.sh"

  mkdir -p "${git_project}_scripts" && cd "${git_project}_scripts"

  # Temporary, until merged to upstream
  # download_github_file_or_dir "$git_user" "$git_project" "$commit_or_branch" "${github_dir}"
  download_github_file_or_dir "$git_user" "$git_project" "$commit_or_branch" # "${github_dir}"

  # echo "# Copy '${github_dir}' directory (including '${terraform_script}') to ${target_path}"
  # mkdir -p "${target_path}"
  # cp -rf "${github_dir}"/* "${target_path}"
  # cd "${target_path}/"

  echo "# Copy '${git_project}_scripts' directory (including '${terraform_script}') to ${target_path}_scripts"
  mkdir -p "${target_path}_scripts"
  cp -rf * "${target_path}_scripts"
  cd "${target_path}_scripts/"
  ### Temporary end

  # Fix bug in terraform version
  sed -r 's/0\.12\.12/0\.12\.29/g' -i versions.tf || :

  # Fix bug in terraform provider permission denied
  chmod -R a+x ./.terraform/plugins/linux_amd64/* || :

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"

  # export IPSEC_NATT_PORT=${IPSEC_NATT_PORT:-4501}
  # export IPSEC_IKE_PORT=${IPSEC_IKE_PORT:-501}

  echo "# Running '${terraform_script} ${cluster_path} -auto-approve' script to apply open OSP required ports:"

  chmod a+x ./${terraform_script}
  # Use variables: -var region=”eu-west-2” -var region=”eu-west-1” or with: -var-file=newvariable.tf
  # bash -x ...
  ./${terraform_script} "${cluster_path}" -auto-approve |& highlight "Apply complete| already exists" \
  || FATAL "./${terraform_script} did not complete successfully"

  # Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
  # OR
  # Security group rule already exists.
  #

}

# ------------------------------------------

function label_gateway_on_broker_nodes_with_external_ip() {
### Label a Gateway node on AWS cluster A (public) ###
  PROMPT "Adding Gateway label to all worker nodes with an External-IP on AWS cluster A (public)"
  trap_to_debug_commands;

  BUG "If one of the gateway nodes does not have External-IP, submariner will fail to connect later" \
  "Make sure one node with External-IP has a gateway label" \
  "https://github.com/submariner-io/submariner-operator/issues/253"

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  # TODO: Check that the Gateway label was created with "prep_for_subm.sh" on AWS cluster A (public) ?
  gateway_label_all_nodes_external_ip
}

function label_first_gateway_cluster_b() {
### Label a Gateway node on cluster B ###
  PROMPT "Adding Gateway label to the first worker node on cluster B"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  gateway_label_first_worker_node
}

function label_first_gateway_cluster_c() {
### Label a Gateway node on cluster C ###
  PROMPT "Adding Gateway label to the first worker node on cluster C"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  gateway_label_first_worker_node
}

function gateway_label_first_worker_node() {
### Adding submariner gateway label to the first worker node ###
  trap_to_debug_commands;

  # gw_node1=$(${OC} get nodes -l node-role.kubernetes.io/worker | awk 'FNR == 2 {print $1}')
  ${OC} get nodes -l node-role.kubernetes.io/worker | awk 'FNR == 2 {print $1}' > "$TEMP_FILE"
  gw_node1="$(< $TEMP_FILE)"

  [[ -n "$gw_node1" ]] || FATAL "Failed to list worker nodes in current cluster"

  echo "# Adding submariner gateway labels to first worker node: $gw_node1"
    # gw_node1: user-cl1-bbmkg-worker-8mx4k

  # TODO: Run only If there's no Gateway label already:
  ${OC} label node $gw_node1 "submariner.io/gateway=true" --overwrite
    # node/user-cl1-bbmkg-worker-8mx4k labeled

  # ${OC} get nodes -l "submariner.io/gateway=true" |& highlight "Ready"
      # NAME                          STATUS   ROLES    AGE     VERSION
      # ip-10-0-89-164.ec2.internal   Ready    worker   5h14m   v1.14.6+c07e432da
  wait_for_all_nodes_ready

  echo -e "\n# Show Submariner Gateway Nodes: \n"
  ${OC} describe nodes -l submariner.io/gateway=true

}

function gateway_label_all_nodes_external_ip() {
### Adding submariner gateway label to all worker nodes with an External-IP ###
  trap_to_debug_commands;

  ${OC} wait --timeout=3m --for=condition=ready nodes -l node-role.kubernetes.io/worker

  # Filter all node names that have External-IP (column 7 is not none), and ignore header fields
  # Run 200 attempts, and wait for output to include regex of IPv4
  watch_and_retry "${OC} get nodes -l node-role.kubernetes.io/worker -o wide | awk '{print \$7}'" \
  200 '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || external_ips=NONE

  if [[ "$external_ips" = NONE ]] ; then
    ${OC} get nodes -o wide

    failed_machines=$(${OC} get Machine -A -o jsonpath='{.items[?(@.status.phase!="Running")].metadata.name}')

    FATAL "EXTERNAL-IP was not created yet. Please check if \"prep_for_subm.sh\" script had errors.
    ${failed_machines:+ Failed Machines: \n$(${OC} get Machine -A -o wide)}"
  fi

  # [[ -n "$gw_nodes" ]] || FATAL "External-IP was not created yet (by \"prep_for_subm.sh\" script)."

  gw_nodes=$(get_worker_nodes_with_external_ip)
  # ${OC} get nodes -l node-role.kubernetes.io/worker -o wide | awk '$7!="<none>" && NR>1 {print $1}' > "$TEMP_FILE"
  # gw_nodes="$(< $TEMP_FILE)"

  echo "# Adding submariner gateway label to all worker nodes with an External-IP: $gw_nodes"
    # gw_nodes: user-cl1-bbmkg-worker-8mx4k

  for node in $gw_nodes; do
    # TODO: Run only If there's no Gateway label already:
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

function install_broker_cluster_a() {
### Installing Submariner Broker on AWS cluster A (public) ###
  # TODO - Should test broker deployment also on different Public cluster (C), rather than on Public cluster A.
  # TODO: Call kubeconfig of broker cluster
  trap_to_debug_commands;

  DEPLOY_CMD="subctl deploy-broker --kubecontext ${CLUSTER_A_NAME}"

  if [[ "$globalnet" =~ ^(y|yes)$ ]]; then
    PROMPT "Adding GlobalNet to Submariner Deploy command"

    BUG "Running subctl with GlobalNet can fail if glabalnet_cidr address is already assigned" \
    "Define a new and unique globalnet-cidr for this cluster" \
    "https://github.com/submariner-io/submariner/issues/544"

    # DEPLOY_CMD="${DEPLOY_CMD} --globalnet --globalnet-cidr 169.254.0.0/19"
    DEPLOY_CMD="${DEPLOY_CMD} --globalnet"
  fi

  PROMPT "Deploying Submariner Broker on AWS cluster A (public)"

  # Deploys Submariner CRDs, creates the SA for the broker, the role and role bindings
  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

  cd ${WORKDIR}
  #cd $GOPATH/src/github.com/submariner-io/submariner-operator

  echo "# Remove previous broker-info.subm (if exists)"
  rm broker-info.subm || echo "# Previous ${BROKER_INFO} already removed"

  echo "# Executing Subctl Deploy command: ${DEPLOY_CMD}"

  BUG "For Submariner 0.9+ operator image should be accessible before broker deploy" \
  "Run broker deployment after uploading custom images to the cluster registry" \
  "https://github.com/submariner-io/submariner-website/issues/483"

  $DEPLOY_CMD
}

# ------------------------------------------

function test_broker_before_join() {
  PROMPT "Verify Submariner resources on the Broker cluster"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_BROKER}"

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
  # For Subctl <= 0.8 : "No resources found" is expected on the broker after deploy command
  [[ $(subctl version | grep --invert-match "v0.8") ]] || regex="No resources found"

  if [[ ! "$skip_ocp_setup" =~ ^(y|yes)$ ]]; then
    ${OC} get pods -n ${SUBM_NAMESPACE} --show-labels |& highlight "$regex" \
     || FATAL "Submariner Broker which was created with $(subctl version) deploy command (before join) \
      should have \"$regex\" in the Broker namespace '${SUBM_NAMESPACE}'"
  fi
}

# ------------------------------------------

function export_nginx_default_namespace_cluster_b() {
  PROMPT "Create ServiceExport for $NGINX_CLUSTER_B on OSP cluster B, without specifying Namespace"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"

  echo -e "# The ServiceExport should be created on the default Namespace, as configured in KUBECONFIG:
  \n# $KUBECONF_CLUSTER_B : ${TEST_NS:-default}"

  export_service_in_lighthouse "$NGINX_CLUSTER_B"
}

# ------------------------------------------

function export_nginx_headless_namespace_cluster_b() {
  PROMPT "Create ServiceExport for the HEADLESS $NGINX_CLUSTER_B on OSP cluster B, in the Namespace '$HEADLESS_TEST_NS'"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"

  echo "# The ServiceExport should be created on the default Namespace, as configured in KUBECONFIG:
  \n# $KUBECONF_CLUSTER_B : ${HEADLESS_TEST_NS}"

  export_service_in_lighthouse "$NGINX_CLUSTER_B" "$HEADLESS_TEST_NS"
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

  echo "# Wait up to 3 minutes for $svc_name to successfully sync to the broker:"

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

  echo "# Show $svc_name ServiceExport status is Valid:"
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

function configure_images_prune_cluster_a() {
  PROMPT "Configure Garbage Collection and Registry Images Prune on AWS cluster A"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  configure_ocp_garbage_collection_and_images_prune
}

# ------------------------------------------

function configure_images_prune_cluster_b() {
  PROMPT "Configure Garbage Collection and Registry Images Prune on OSP cluster B"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  configure_ocp_garbage_collection_and_images_prune
}

# ------------------------------------------

function configure_images_prune_cluster_c() {
  PROMPT "Configure Garbage Collection and Registry Images Prune on cluster C"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  configure_ocp_garbage_collection_and_images_prune
}

# ------------------------------------------

function configure_ocp_garbage_collection_and_images_prune() {
### function to set garbage collection on all cluster nodes
  trap_to_debug_commands;

  echo "# Setting garbage collection on all OCP cluster nodes"

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

  echo "# Setting ContainerRuntimeConfig limits on all OCP cluster nodes"

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

  echo "# Enable Image Pruner policy - to delete unused images from registry:"

  ${OC} patch imagepruner.imageregistry/cluster --patch '{"spec":{"suspend":false}}' --type=merge
    # imagepruner.imageregistry.operator.openshift.io/cluster patched

  ${OC} wait imagepruner --timeout=10s --for=condition=available cluster
    # imagepruner.imageregistry.operator.openshift.io/cluster condition met

  ${OC} describe imagepruner.imageregistry.operator.openshift.io

  echo "# List all images in all pods:"
  ${OC} get pods -A -o jsonpath="{..imageID}" |tr -s '[[:space:]]' '\n' | sort | uniq -c | awk '{print $2}'
}

# ------------------------------------------

function configure_custom_registry_cluster_a() {
  PROMPT "Using custom Registry for Submariner images on AWS cluster A"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  configure_cluster_custom_registry_secrets

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  configure_cluster_custom_registry_mirror

}

# ------------------------------------------

function configure_custom_registry_cluster_b() {
  PROMPT "Using custom Registry for Submariner images on OSP cluster B"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  configure_cluster_custom_registry_secrets

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  configure_cluster_custom_registry_mirror

}

# ------------------------------------------

function configure_custom_registry_cluster_c() {
  PROMPT "Using custom Registry for Submariner images on cluster C"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  configure_cluster_custom_registry_secrets

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  configure_cluster_custom_registry_mirror

}

# ------------------------------------------

function configure_cluster_custom_registry_secrets() {
### Configure access to external docker registry
  trap '' DEBUG # DONT trap_to_debug_commands

  echo "# Configure OCP registry global secret"

  wait_for_all_machines_ready || :
  wait_for_all_nodes_ready || :

  local ocp_usr="${1:-$OCP_USR}"
  local secret_filename="${3:-http.secret}"

  ( # subshell to hide commands
    local ocp_pwd="${2:-$OCP_PWD}"
    printf "${ocp_usr}:$(openssl passwd -apr1 ${ocp_pwd})\n" > "${secret_filename}"
  )

  ${OC} delete secret $secret_filename -n openshift-config --ignore-not-found || :

  ${OC} create secret generic ${secret_filename} --from-file=htpasswd=${secret_filename} -n openshift-config

  cat <<EOF | ${OC} apply -f -
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
           name: ${secret_filename}
EOF

  ${OC} describe oauth.config.openshift.io/cluster

  local cur_context=$(${OC} config current-context)

  echo "# Add new user '${ocp_usr}' to cluster roles, and verify login, while saving kubeconfig current-context ($cur_context)"

  ${OC} wait --timeout=5m --for=condition=Available clusteroperators authentication kube-apiserver
  ${OC} wait --timeout=5m --for='condition=Progressing=False' clusteroperators authentication kube-apiserver
  ${OC} wait --timeout=5m --for='condition=Degraded=False' clusteroperators authentication kube-apiserver

  ### Give user admin privileges
  # ${OC} create clusterrolebinding registry-controller --clusterrole=cluster-admin --user=${ocp_usr}
  ${OC} adm policy add-cluster-role-to-user cluster-admin ${ocp_usr}

  local cmd="${OC} get clusterrolebindings --no-headers -o custom-columns='USER:subjects[].name'"
  watch_and_retry "$cmd" 5m "^${ocp_usr}$" || BUG "WARNING: User \"${ocp_usr}\" may not be cluster admin"

  ( # subshell to hide commands
    local ocp_pwd="${2:-$OCP_PWD}"
    local cmd="${OC} login -u ${ocp_usr} -p ${ocp_pwd}"
    # Attempt to login up to 3 minutes
    watch_and_retry "$cmd" 3m

    # ocp_usr=$(${OC} whoami | tr -d ':')
    # ocp_pwd=$(${OC} whoami -t)
    ocp_token=$(${OC} whoami -t)

    echo "# Configure OCP registry local secret"

    local ocp_registry_url=$(${OC} registry info --internal)

    create_docker_registry_secret "$ocp_registry_url" "$ocp_usr" "$ocp_token" "$SUBM_NAMESPACE"

    # Do not ${OC} logout - it will cause authentication error pulling images during join command
  )

  echo "# Prune old registry images associated with Mirror url: https://${REGISTRY_MIRROR}"
  oc adm prune images --registry-url=https://${REGISTRY_MIRROR} --force-insecure --confirm || :

  echo "# Restore kubeconfig current-context to $cur_context"
  # ${OC} config set "current-context" "$cur_context"
  ${OC} config use-context "$cur_context"

}

# ------------------------------------------

function configure_cluster_custom_registry_mirror() {
### Configure a mirror server on the cluster registry
  trap '' DEBUG # DONT trap_to_debug_commands

  local ocp_registry_url=$(${OC} registry info --internal)
  local local_registry_path="${ocp_registry_url}/${SUBM_NAMESPACE}"

  echo "# Add OCP Registry mirror for Submariner:"

  create_docker_registry_secret "$REGISTRY_MIRROR" "$REGISTRY_USR" "$REGISTRY_PWD" "$SUBM_NAMESPACE"

  add_submariner_registry_mirror_to_ocp_node "master" "$REGISTRY_URL" "${local_registry_path}" || :
  add_submariner_registry_mirror_to_ocp_node "worker" "$REGISTRY_URL" "${local_registry_path}" || :

  wait_for_all_machines_ready || :
  wait_for_all_nodes_ready || :

}

# ------------------------------------------

function create_docker_registry_secret() {
### Helper function to add new Docker registry
  trap '' DEBUG # DONT trap_to_debug_commands

  # input variables
  local registry_server="$1"
  local registry_usr=$2
  local registry_pwd=$3
  local namespace="$4"

  local secret_name="${registry_server}-${registry_usr}"
  local secret_name="${secret_name//[^a-z0-9]/-}"

  echo -e "# Creating new docker-registry in '$namespace' namespace:
  \n# Server: ${registry_server} \n# Secret name: ${secret_name}"

  create_namespace "${namespace}"

  ${OC} delete secret $secret_name -n $namespace --ignore-not-found || :

  ( # subshell to hide commands
    ${OC} create secret docker-registry -n ${namespace} $secret_name --docker-server=${registry_server} \
    --docker-username=${registry_usr} --docker-password=${registry_pwd} # --docker-email=${registry_email}
  )

  echo "# Adding '$secret_name' secret:"
  ${OC} describe secret $secret_name -n $namespace || :

  ( # update the cluster global pull-secret
    ${OC} patch secret/pull-secret -n openshift-config -p \
    '{"data":{".dockerconfigjson":"'"$( \
    ${OC} get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" \
    | base64 --decode | jq -r -c '.auths |= . + '"$( \
    ${OC} get secret/${secret_name} -n $namespace    --output="jsonpath={.data.\.dockerconfigjson}" \
    | base64 --decode | jq -r -c '.auths')"'' | base64 -w 0)"'"}}'
  )

  ${OC} describe secret/pull-secret -n openshift-config

}

# ------------------------------------------

function add_submariner_registry_mirror_to_ocp_node() {
### Helper function to add OCP registry mirror for Submariner on all master or all worker nodes
  trap_to_debug_commands

  # set registry variables
  local node_type="$1" # master or worker
  local registry_url="$2"
  local registry_mirror="$3"

  reg_values="
  node_type = $node_type
  registry_url = $registry_url
  registry_mirror = $registry_mirror"

  if [[ -z "$registry_url" ]] || [[ -z "$registry_mirror" ]] || \
  [[ ! "$node_type" =~ ^(master|worker)$ ]]; then
    FATAL "Expected Openshift Registry values are missing: $reg_values"
  else
    echo "# Adding Submariner registry mirror to all OCP cluster nodes: $reg_values"
  fi

  config_source=$(cat <<EOF | raw_to_url_encode
  [[registry]]
    prefix = ""
    location = "${registry_url}"
    mirror-by-digest-only = false
    insecure = false
    blocked = false

    [[registry.mirror]]
      location = "${registry_mirror}"
      insecure = false
EOF
  )

  echo "# Enabling auto-reboot of ${node_type} when changing Machine Config Pool:"
  ${OC} patch --type=merge --patch='{"spec":{"paused":false}}' machineconfigpool/${node_type}

  local ocp_version=$(${OC} version | awk '/Server Version/ { print $3 }')
  echo "# Checking API ignition version for OCP version: $ocp_version"

  ignition_version=$(${OC} extract -n openshift-machine-api secret/worker-user-data --keys=userData --to=- | grep -oP '(?s)(?<=version":")[0-9\.]+(?=")')

  echo "# Updating Registry in ${node_type} Machine configuration, via OCP API Ignition version: $ignition_version"

  local nodes_conf="`mktemp`_${node_type}.yaml"

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

function delete_old_submariner_images_from_cluster_a() {
  PROMPT "Delete previous Submariner images in AWS cluster A"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  delete_old_submariner_images_from_current_cluster
}

# ------------------------------------------

function delete_old_submariner_images_from_cluster_b() {
  PROMPT "Delete previous Submariner images in OSP cluster B"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  delete_old_submariner_images_from_current_cluster
}

# ------------------------------------------

function delete_old_submariner_images_from_cluster_c() {
  PROMPT "Delete previous Submariner images in cluster C"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  delete_old_submariner_images_from_current_cluster
}

# ------------------------------------------

function delete_old_submariner_images_from_current_cluster() {
### Configure a mirror server on the cluster registry
  trap_to_debug_commands

  echo "# Deleting old Submariner images, tags, and image streams (if exist)"

  for node in $(${OC} get nodes -o name) ; do
    echo -e "\n### Delete Submariner images in $node ###"
    ${OC} debug $node -n default -- chroot /host /bin/bash -c "\
    crictl images | awk '\$1 ~ /submariner|lighthouse/ {print \$3}' | xargs -n1 crictl rmi" || :
  done

  # # Delete images
  # ${OC} get images | grep "${REGISTRY_MIRROR}" | while read -r line ; do
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
    echo "# Deleting image stream: $img_stream"
    oc delete imagestream "${img_stream}" -n ${SUBM_NAMESPACE} --ignore-not-found || :
    # oc tag -d submariner-operator/${img_stream}
  done

}

# ------------------------------------------

function set_join_parameters_for_cluster_a() {
  PROMPT "Set parameters of SubCtl Join command for AWS cluster A (public)"
  trap_to_debug_commands;

  write_subctl_join_command "${SUBCTL_JOIN_CLUSTER_A_FILE}"
}

# ------------------------------------------

function set_join_parameters_for_cluster_b() {
  PROMPT "Set parameters of SubCtl Join command for OSP cluster B (on-prem)"
  trap_to_debug_commands;

  write_subctl_join_command "${SUBCTL_JOIN_CLUSTER_B_FILE}"

}

# ------------------------------------------

function set_join_parameters_for_cluster_c() {
  PROMPT "Set parameters of SubCtl Join command for cluster C"
  trap_to_debug_commands;

  write_subctl_join_command "${SUBCTL_JOIN_CLUSTER_C_FILE}"

}

# ------------------------------------------

function write_subctl_join_command() {
# Join Submariner member - of current cluster kubeconfig
  trap_to_debug_commands;
  local join_cmd_file="$1"

  echo -e "# Adding Broker file and IPSec ports to subctl join command"

  subctl_join="subctl join \
  ./${BROKER_INFO} ${subm_cable_driver:+--cable-driver $subm_cable_driver} \
  --ikeport ${IPSEC_IKE_PORT} --nattport ${IPSEC_NATT_PORT}"

  echo "# Adding '--health-check' to subctl join command (to enable Gateway health check)"

  subctl_join="${subctl_join} --health-check"

  local pod_debug_flag="--pod-debug"
  # For Subctl <= 0.8 : '--enable-pod-debugging' is expected as the debug flag for the join command"
  [[ $(subctl version | grep --invert-match "v0.8") ]] || pod_debug_flag="--enable-pod-debugging"

  echo "# Adding '${pod_debug_flag}' and '--ipsec-debug' to subctl join command (for tractability)"
  subctl_join="${subctl_join} ${pod_debug_flag} --ipsec-debug"

  # TODO: Following bug should be resolved by https://github.com/submariner-io/submariner-operator/pull/1227
  #
  # if [[ ! "$registry_images" =~ ^(y|yes)$ ]] && [[ "$SUBM_VER_TAG" =~ ^subctl-devel ]]; then
  #   BUG "operator image 'devel' should be the default when using subctl devel binary" \
  #   "Add '--version devel' to $join_cmd_file" \
  #   "https://github.com/submariner-io/submariner-operator/issues/563"
  #   # Workaround
  #   subctl_join="${subctl_join} --version devel"
  # fi

  echo "# Write the join parameters into the join command file: $join_cmd_file"
  echo "$subctl_join" > "$join_cmd_file"

}

# ------------------------------------------

function upload_custom_images_to_registry_cluster_a() {
# Upload custom images to the registry - AWS cluster A (public)
  PROMPT "Upload custom images to the registry of cluster A"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  upload_custom_images_to_registry "${SUBCTL_JOIN_CLUSTER_A_FILE}"
}

# ------------------------------------------

function upload_custom_images_to_registry_cluster_b() {
# Upload custom images to the registry - OSP cluster B (on-prem)
  PROMPT "Upload custom images to the registry of cluster B"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  upload_custom_images_to_registry "${SUBCTL_JOIN_CLUSTER_B_FILE}"
}

# ------------------------------------------

function upload_custom_images_to_registry_cluster_c() {
# Upload custom images to the registry - OSP cluster C
  PROMPT "Upload custom images to the registry of cluster C"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  upload_custom_images_to_registry "${SUBCTL_JOIN_CLUSTER_C_FILE}"
}

# ------------------------------------------

function upload_custom_images_to_registry() {
# Join Submariner member - of current cluster kubeconfig
  trap_to_debug_commands;

  local join_cmd_file="$1"
  echo "# Read subctl join command from file: $join_cmd_file"
  local subctl_join="$(< $join_cmd_file)"

  # Update $SUBM_VER_TAG value
  set_subm_version_tag_var

  echo -e "# Overriding submariner images with custom images from ${REGISTRY_URL} \
  \n# Mirror path: ${REGISTRY_MIRROR}/${REGISTRY_IMAGE_PREFIX} \
  \n# Version tag: ${SUBM_VER_TAG}"

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
      local img_source="${REGISTRY_MIRROR}/${REGISTRY_IMAGE_PREFIX}${img}:${SUBM_VER_TAG}"
      echo -e "\n# Importing image from a mirror OCP registry: ${img_source} \n"

      local cmd="${OC} import-image -n ${SUBM_NAMESPACE} ${img}:${SUBM_VER_TAG} --from=${img_source} --confirm"

      watch_and_retry "$cmd" 3m "Image Name:\s+${img}:${SUBM_VER_TAG}"
  done

  BUG "SubM Gateway image name should be 'submariner-gateway'" \
  "Rename SubM Gateway image to 'submariner' " \
  "https://github.com/submariner-io/submariner-operator/pull/941
  https://github.com/submariner-io/submariner-operator/issues/1018"

  echo "# Adding custom images to subctl join command"
  subctl_join="${subctl_join} --image-override submariner-operator=${REGISTRY_URL}/${SUBM_IMG_OPERATOR}:${SUBM_VER_TAG}"

  # BUG ? : this is a potential bug - overriding with comma separated:
  # subctl_join="${subctl_join} --image-override \
  # submariner=${REGISTRY_URL}/${SUBM_IMG_GATEWAY}:${SUBM_VER_TAG},\
  # submariner-route-agent=${REGISTRY_URL}/${SUBM_IMG_ROUTE}:${SUBM_VER_TAG}, \
  # submariner-networkplugin-syncer=${REGISTRY_URL}/${SUBM_IMG_NETWORK}:${SUBM_VER_TAG},\
  # lighthouse-agent=${REGISTRY_URL}/${SUBM_IMG_LIGHTHOUSE}:${SUBM_VER_TAG},\
  # lighthouse-coredns=${REGISTRY_URL}/${SUBM_IMG_COREDNS}:${SUBM_VER_TAG},\
  # submariner-globalnet=${REGISTRY_URL}/${SUBM_IMG_GLOBALNET}:${SUBM_VER_TAG},\
  # submariner-operator=${REGISTRY_URL}/${SUBM_IMG_OPERATOR}:${SUBM_VER_TAG},\
  # submariner-bundle=${REGISTRY_URL}/${SUBM_IMG_BUNDLE}:${SUBM_VER_TAG}"

  echo "# Write the \"--image-override\" parameters into the join command file: $join_cmd_file"
  echo "$subctl_join" > "$join_cmd_file"

}

# ------------------------------------------

function set_subm_version_tag_var() {
# update the variable value of $SUBM_VER_TAG (or the $1 input var name)
  trap_to_debug_commands;

  # Get variable name (default is "SUBM_VER_TAG")
  local tag_var_name="${1:-SUBM_VER_TAG}"
  # Set subm_version_tag as the actual value of tag_var_name
  local subm_version_tag="${!tag_var_name}"

  echo "# Retrieve correct tag for Subctl version \$${tag_var_name} : $subm_version_tag"
  if [[ "$subm_version_tag" =~ latest|devel ]]; then
    subm_version_tag=$(get_latest_subctl_version_tag)
  elif [[ "$subm_version_tag" =~ ^[0-9] ]]; then
    echo "# Version ${subm_version_tag} is considered as 'v${subm_version_tag}' tag"
    subm_version_tag=v${subm_version_tag}
  fi

  if [[ -n "$REGISTRY_TAG_MATCH" ]] ; then
    echo "# REGISTRY_TAG_MATCH variable was set to extract from '$subm_version_tag' the regex match: $REGISTRY_TAG_MATCH"
    subm_version_tag=v$(echo $subm_version_tag | grep -Po "$REGISTRY_TAG_MATCH")
    echo "# New \$${tag_var_name} for registry images: $subm_version_tag"
  fi

  # Reevaluate $tag_var_name value
  local eval_cmd="export ${tag_var_name}=${subm_version_tag}"
  eval $eval_cmd
}

# ------------------------------------------

function run_subctl_join_on_cluster_a() {
# Join Submariner member - AWS cluster A (public)
  PROMPT "Joining cluster A to Submariner Broker"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  run_subctl_join_cmd_from_file "${SUBCTL_JOIN_CLUSTER_A_FILE}"
}

# ------------------------------------------

function run_subctl_join_on_cluster_b() {
# Join Submariner member - OSP cluster B (on-prem)
  PROMPT "Joining cluster B to Submariner Broker"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  run_subctl_join_cmd_from_file "${SUBCTL_JOIN_CLUSTER_B_FILE}"

}

# ------------------------------------------

function run_subctl_join_on_cluster_c() {
# Join Submariner member - cluster C (on-prem)
  PROMPT "Joining cluster C to Submariner Broker"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  run_subctl_join_cmd_from_file "${SUBCTL_JOIN_CLUSTER_C_FILE}"

}

# ------------------------------------------

function run_subctl_join_cmd_from_file() {
# Join Submariner member - of current cluster kubeconfig
  trap_to_debug_commands;

  echo "# Read subctl join command from file: $1"
  local subctl_join="$(< $1)"

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

  # export KUBECONFIG="${KUBECONFIG}:${KUBECONF_BROKER}"
  ${OC} config view

  echo -e "\n# Executing Subctl Join command on current cluster: \n ${subctl_join}"

  $subctl_join

}

# ------------------------------------------

function test_submariner_resources_cluster_a() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  test_submariner_resources_status "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_submariner_resources_cluster_b() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  test_submariner_resources_status "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_submariner_resources_cluster_c() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  test_submariner_resources_status "${CLUSTER_C_NAME}"
}

# ------------------------------------------

function test_submariner_resources_status() {
# Check submariner-gateway on the Operator pod
  trap_to_debug_commands;
  local cluster_name="$1"
  local submariner_status=UP

  PROMPT "Testing that Submariner CRDs and resources were created on cluster ${cluster_name}"
  ${OC} get crds | grep submariners || submariner_status=DOWN
      # ...
      # submariners.submariner.io                                   2019-11-28T14:09:56Z

  ${OC} get namespace ${SUBM_NAMESPACE} -o json  || submariner_status=DOWN

  ${OC} get Submariner -n ${SUBM_NAMESPACE} -o yaml || submariner_status=DOWN

  ${OC} get all -n ${SUBM_NAMESPACE} --show-labels |& (! highlight "Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|No resources found") \
  || submariner_status=DOWN
  # TODO: consider checking for "Terminating" pods

  if [[ "$submariner_status" = DOWN ]] ; then
    echo "### Potential Bugs ###"

    BUG "Globalnet pod might have terminated after deployment" \
    "No workaround, ignore ERROR state (Globalnet pod will be restarted)" \
    "https://github.com/submariner-io/submariner/issues/903"

    BUG "Submariner operator failed to provision the Cluster CRD" \
    "No workaround yet" \
    "https://bugzilla.redhat.com/show_bug.cgi?id=1921824"

    FAILURE "Submariner installation failure occurred on $cluster_name.
    Resources/CRDs were not installed, or Submariner pods have crashed."
  fi

}

# ------------------------------------------

function test_public_ip_on_gateway_node() {
# Testing that Submariner Gateway node received public (external) IP
  PROMPT "Testing that Submariner Gateway node received public (external) IP"
  trap_to_debug_commands;

  # Should be run on the Broker cluster
  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

  local public_ip=$(get_external_ips_of_worker_nodes)
  echo "# Before VM reboot - Gateway public (external) IP should be: $public_ip"

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
  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

  echo "# Get all AWS running VMs, that were assigned as 'submariner-gw' in OCP cluster $CLUSTER_A_NAME"
  gateway_aws_instance_ids="$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=${CLUSTER_A_NAME}-*-submariner-gw-* Name=instance-state-name,Values=running \
  --output text --query Reservations[*].Instances[*].InstanceId \
  | tr '\r\n' ' ')"

  [[ -n "$gateway_aws_instance_ids" ]] || FATAL "No running VM instances of 'submariner-gw' in OCP cluster $CLUSTER_A_NAME"

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
  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

  echo "# Watching Submariner Gateway pod - It should create new Gateway:"

  local gw_label='app=submariner-gateway'
  # For Subctl <= 0.8 : 'app=submariner-engine' is expected as the Gateway pod label"
  [[ $(subctl version | grep --invert-match "v0.8") ]] || gw_label="app=submariner-engine"

  # local submariner_gateway_pod="`get_running_pod_by_label "$gw_label" "$SUBM_NAMESPACE" `"
  local cmd="${OC} get pod -n ${SUBM_NAMESPACE} -l $gw_label -o jsonpath='{.items[0].metadata.name}'"
  watch_and_retry "$cmd" 3m
  local submariner_gateway_pod=$($cmd | tr -d \')

  local regex="All controllers stopped or exited"
  # Watch submariner-gateway pod logs for 200 (10 X 20) seconds
  watch_pod_logs "$submariner_gateway_pod" "${SUBM_NAMESPACE}" "$regex" 10 || :

  local public_ip=$(get_external_ips_of_worker_nodes)
  echo -e "\n\n# The new Gateway public (external) IP should be: $public_ip \n"
  verify_gateway_public_ip "$public_ip"

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

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  test_submariner_cable_driver "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_cable_driver_cluster_b() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  test_submariner_cable_driver "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_cable_driver_cluster_c() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  test_submariner_cable_driver "${CLUSTER_C_NAME}"
}

# ------------------------------------------

function test_submariner_cable_driver() {
# Check submariner cable driver
  trap_to_debug_commands;
  cluster_name="$1"

  PROMPT "Testing Cable-Driver ${subm_cable_driver:+\"$subm_cable_driver\" }on ${cluster_name}"

  local gw_label='app=submariner-gateway'
  # For Subctl <= 0.8 : 'app=submariner-engine' is expected as the Gateway pod label"
  [[ $(subctl version | grep --invert-match "v0.8") ]] || gw_label="app=submariner-engine"

  # local submariner_gateway_pod="`get_running_pod_by_label "$gw_label" "$SUBM_NAMESPACE" `"
  local cmd="${OC} get pod -n ${SUBM_NAMESPACE} -l $gw_label -o jsonpath='{.items[0].metadata.name}'"
  watch_and_retry "$cmd" 3m
  local submariner_gateway_pod=$($cmd | tr -d \')

  local regex="(cable.* started|Status:connected)"
  # Watch submariner-gateway pod logs for 200 (10 X 20) seconds
  watch_pod_logs "$submariner_gateway_pod" "${SUBM_NAMESPACE}" "$regex" 10

}

# ------------------------------------------

function test_ha_status_cluster_a() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  test_ha_status "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_ha_status_cluster_b() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  test_ha_status "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_ha_status_cluster_c() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  test_ha_status "${CLUSTER_C_NAME}"
}

# ------------------------------------------

function test_ha_status() {
# Check submariner HA status
  trap_to_debug_commands;
  cluster_name="$1"
  local submariner_status=UP

  PROMPT "Check HA status of Submariner and Gateway resources on ${cluster_name}"

  ${OC} describe cm -n openshift-dns || submariner_status=DOWN

  ${OC} get clusters -n ${SUBM_NAMESPACE} -o wide || submariner_status=DOWN

  # TODO: Need to get current cluster ID
  #${OC} describe cluster "${cluster_id}" -n ${SUBM_NAMESPACE} || submariner_status=DOWN

  ### Checking "Gateway" resource ###
  BUG "API 'describe Gateway' does not show Gateway crashing and cable-driver failure" \
  "No workaround" \
  "https://github.com/submariner-io/submariner/issues/777"

  cmd="${OC} describe Gateway -n ${SUBM_NAMESPACE}"
  local regex="Ha Status:\s*active"
  watch_and_retry "$cmd" 3m "$regex"

  submariner_gateway_info="$(${OC} describe Gateway -n ${SUBM_NAMESPACE})"
  # echo "$submariner_gateway_info" |& highlight "Ha Status:\s*active" || submariner_status=DOWN
  echo "$submariner_gateway_info" |& (! highlight "Status Failure\s*\w+") || submariner_status=DOWN

  ### Checking "Submariner" resource ###
  cmd="${OC} describe Submariner -n ${SUBM_NAMESPACE}"
  local regex="Status:\s*connect" || submariner_status=DOWN
  # Attempt cmd for 3 minutes (grepping for 'Connections:' and print 30 lines afterwards), looking for Status connected
  watch_and_retry "$cmd | grep -A 30 'Connections:'" 3m "$regex" || submariner_status=DOWN

  submariner_gateway_info="$(${OC} describe Submariner -n ${SUBM_NAMESPACE})"
  # echo "$submariner_gateway_info" |& highlight "Status:\s*connected" || submariner_status=DOWN
  echo "$submariner_gateway_info" |& (! highlight "Status Failure\s*\w+") || submariner_status=DOWN

  if [[ "$submariner_status" = DOWN ]] ; then
    BUG "Submariner-operator might loop on error in controller_submariner: failed to update the Submariner status " \
    "No workaround" \
    "https://github.com/submariner-io/submariner-operator/issues/1047"

    FATAL "Submariner HA failure occurred."
  fi

}

# ------------------------------------------

function test_submariner_connection_cluster_a() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  test_submariner_connection_established "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_submariner_connection_cluster_b() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  test_submariner_connection_established "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_submariner_connection_cluster_c() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  test_submariner_connection_established "${CLUSTER_C_NAME}"
}

# ------------------------------------------

function test_submariner_connection_established() {
# Check submariner cable driver
  trap_to_debug_commands;
  cluster_name="$1"

  PROMPT "Check Submariner Gateway established connection on ${cluster_name}"

  local gw_label='app=submariner-gateway'
  # For Subctl <= 0.8 : 'app=submariner-engine' is expected as the Gateway pod label"
  [[ $(subctl version | grep --invert-match "v0.8") ]] || gw_label="app=submariner-engine"

  # local submariner_gateway_pod="`get_running_pod_by_label "$gw_label" "$SUBM_NAMESPACE" `"
  local cmd="${OC} get pod -n ${SUBM_NAMESPACE} -l $gw_label -o jsonpath='{.items[0].metadata.name}'"
  watch_and_retry "$cmd" 3m
  local submariner_gateway_pod=$($cmd | tr -d \')

  echo "# Tailing logs in Submariner-Gateway pod [$submariner_gateway_pod] to verify connection between clusters"
  # ${OC} logs $submariner_gateway_pod -n ${SUBM_NAMESPACE} | grep "received packet" -C 2 || submariner_status=DOWN

  local regex="(Successfully installed Endpoint cable .* remote IP|Status:connected|CableName:.*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)"
  # Watch submariner-gateway pod logs for 400 (20 X 20) seconds
  watch_pod_logs "$submariner_gateway_pod" "${SUBM_NAMESPACE}" "$regex" 20 || submariner_status=DOWN

  ${OC} describe pod $submariner_gateway_pod -n ${SUBM_NAMESPACE} || submariner_status=DOWN

  [[ "$submariner_status" != DOWN ]] || FATAL "Submariner clusters are not connected."
}


# ------------------------------------------

function test_ipsec_status_cluster_a() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  test_ipsec_status "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_ipsec_status_cluster_b() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  test_ipsec_status "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_ipsec_status_cluster_c() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  test_ipsec_status "${CLUSTER_C_NAME}"
}

# ------------------------------------------

function test_ipsec_status() {
# Check submariner cable driver
  trap_to_debug_commands;
  cluster_name="$1"

  PROMPT "Testing IPSec Status of the Active Gateway in ${cluster_name}"

  local active_gateway_node=$(subctl show gateways | awk '/active/ {print $1}')

  local gw_label='app=submariner-gateway'
  # For Subctl <= 0.8 : 'app=submariner-engine' is expected as the Gateway pod label"
  [[ $(subctl version | grep --invert-match "v0.8") ]] || gw_label="app=submariner-engine"

  local active_gateway_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l $gw_label -o wide | awk -v gw_node="$active_gateway_node" '$0 ~ gw_node { print $1 }')
  # submariner-gateway-r288v
  > "$TEMP_FILE"

  echo "# Verify IPSec status on Active Node [${active_gateway_node}] Gateway Pod [${active_gateway_pod}]:"
  ${OC} exec $active_gateway_pod -n ${SUBM_NAMESPACE} -- bash -c "ipsec status" |& tee -a "$TEMP_FILE" || :

  local loaded_con="`grep "Total IPsec connections:" "$TEMP_FILE" | grep -Po "loaded \K([0-9]+)" | tail -1`"
  local active_con="`grep "Total IPsec connections:" "$TEMP_FILE" | grep -Po "active \K([0-9]+)" | tail -1`"

  if [[ ! "$active_con" = "$loaded_con" ]] ; then
    BUG "Not all Submariner IPsec connections were established" \
     "No workaround yet, it is caused by LibreSwan bug 1081" \
    "https://bugzilla.redhat.com/show_bug.cgi?id=1920408"
    # No workaround yet
    FATAL "IPSec tunnel error: $loaded_con Loaded connections, but only $active_con Active"
  fi

}

# ------------------------------------------

function test_globalnet_status_cluster_a() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  test_globalnet_status "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_globalnet_status_cluster_b() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  test_globalnet_status "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_globalnet_status_cluster_c() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  test_globalnet_status "${CLUSTER_C_NAME}"
}

# ------------------------------------------

function test_globalnet_status() {
  # Check Globalnet controller pod status
  trap_to_debug_commands;
  cluster_name="$1"

  PROMPT "Testing GlobalNet controller, Global IPs and Endpoints status on ${cluster_name}"

  # globalnet_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-globalnet -o jsonpath="{.items[0].metadata.name}")
  # [[ -n "$globalnet_pod" ]] || globalnet_status=DOWN
  globalnet_pod="`get_running_pod_by_label 'app=submariner-globalnet' "$SUBM_NAMESPACE" `"


  echo "# Tailing logs in GlobalNet pod [$globalnet_pod] to verify that Global IPs were allocated to cluster services"

  local regex="(Allocating globalIp|Starting submariner-globalnet)"
  # Watch globalnet pod logs for 200 (10 X 20) seconds
  watch_pod_logs "$globalnet_pod" "${SUBM_NAMESPACE}" "$regex" 10 || globalnet_status=DOWN

  echo "# Tailing logs in GlobalNet pod [$globalnet_pod], to see if Endpoints were removed (due to Submariner Gateway restarts)"

  regex="remove endpoint"
  (! watch_pod_logs "$globalnet_pod" "${SUBM_NAMESPACE}" "$regex" 1 "1s") || globalnet_status=DOWN

  [[ "$globalnet_status" != DOWN ]] || FATAL "GlobalNet pod error on ${SUBM_NAMESPACE} namespace, or globalIp / Endpoints failure occurred."
}


# ------------------------------------------

function test_lighthouse_status_cluster_a() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  test_lighthouse_status "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_lighthouse_status_cluster_b() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  test_lighthouse_status "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_lighthouse_status_cluster_c() {
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  test_lighthouse_status "${CLUSTER_C_NAME}"
}

# ------------------------------------------

function test_lighthouse_status() {
  # Check Lighthouse (the pod for service-discovery) status
  trap_to_debug_commands;
  cluster_name="$1"

  PROMPT "Testing Lighthouse agent status on ${cluster_name}"

  # lighthouse_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-lighthouse-agent -o jsonpath="{.items[0].metadata.name}")
  # [[ -n "$lighthouse_pod" ]] || FATAL "Lighthouse pod was not created on ${SUBM_NAMESPACE} namespace."
  lighthouse_pod="`get_running_pod_by_label 'app=submariner-lighthouse-agent' "$SUBM_NAMESPACE" `"

  echo "# Tailing logs in Lighthouse pod [$lighthouse_pod] to verify Service-Discovery sync with Broker"
  local regex="agent .* started"
  # Watch lighthouse pod logs for 100 (5 X 20) seconds
  watch_pod_logs "$lighthouse_pod" "${SUBM_NAMESPACE}" "$regex" 5 || FAILURE "Lighthouse status is not as expected"

  # TODO: Can also test app=submariner-lighthouse-coredns  for the lighthouse DNS status
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
  # TODO: Fix no wait on: watch_and_retry "$cmd | grep -E '$globalnet_tag'" 3m "$ipv4_regex"
  watch_and_retry "$cmd | grep '$globalnet_tag'" 3m "$ipv4_regex"

  $cmd | highlight "$globalnet_tag" || \
  BUG "GlobalNet annotation and IP was not set on $obj_type : $obj_id ${namespace:+(namespace : $namespace)}"

  # Set the external variable $GLOBAL_IP with the GlobalNet IP
  # GLOBAL_IP=$($cmd | grep -E "$globalnet_tag" | awk '{print $NF}')
  export GLOBAL_IP=$($cmd | grep "$globalnet_tag" | grep -Eoh "$ipv4_regex")
}

# ------------------------------------------

function test_clusters_connected_by_service_ip() {
  PROMPT "After Submariner is installed:
  Identify Netshoot pod on cluster A, and Nginx service on cluster B"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  # ${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --field-selector status.phase=Running | awk 'FNR == 2 {print $1}' > "$TEMP_FILE"
  # netshoot_pod_cluster_a="$(< $TEMP_FILE)"
  netshoot_pod_cluster_a="`get_running_pod_by_label "run=${NETSHOOT_CLUSTER_A}" "$TEST_NS" `"

  echo "# NETSHOOT_CLUSTER_A: $netshoot_pod_cluster_a"
    # netshoot-785ffd8c8-zv7td

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  echo "${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')"
  # nginx_IP_cluster_b=$(${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')
  ${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}' > "$TEMP_FILE"
  nginx_IP_cluster_b="$(< $TEMP_FILE)"
  echo "# Nginx service on cluster B, will be identified by its IP (without DNS from service-discovery): ${nginx_IP_cluster_b}:${NGINX_PORT}"
    # nginx_IP_cluster_b: 100.96.43.129

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  CURL_CMD="${TEST_NS:+-n $TEST_NS} ${netshoot_pod_cluster_a} -- curl --output /dev/null --max-time 30 --verbose ${nginx_IP_cluster_b}:${NGINX_PORT}"

  if [[ ! "$globalnet" =~ ^(y|yes)$ ]] ; then
    PROMPT "Testing connection without GlobalNet: From Netshoot on AWS cluster A (public), to Nginx service IP on OSP cluster B (on-prem)"

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
    \n# Nginx internal IP (${nginx_IP_cluster_b}:${NGINX_PORT}) on cluster B, should NOT be reachable outside cluster, if using GlobalNet."

    ${OC} exec ${CURL_CMD} |& (! highlight "Failed to connect" && FAILURE "$msg") || echo -e "$msg"
  fi
}

# ------------------------------------------

function test_clusters_connected_overlapping_cidrs() {
### Run Connectivity tests between the On-Premise and Public clusters ###
# To validate that now Submariner made the connection possible!
  PROMPT "Testing GlobalNet annotation - Nginx service on OSP cluster B (on-prem) should get a GlobalNet IP"
  trap_to_debug_commands;

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"

  # Should fail if NGINX_CLUSTER_B was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_global_ip_created_for_svc_or_pod svc "$NGINX_CLUSTER_B" $TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on Nginx service (${NGINX_CLUSTER_B}${TEST_NS:+.$TEST_NS})"
  nginx_global_ip="$GLOBAL_IP"

  PROMPT "Testing GlobalNet annotation - Netshoot pod on AWS cluster A (public) should get a GlobalNet IP"
  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  # netshoot_pod_cluster_a=$(${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} \
  # --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')
  netshoot_pod_cluster_a="`get_running_pod_by_label "run=${NETSHOOT_CLUSTER_A}" "$TEST_NS" `"

  # Should fail if netshoot_pod_cluster_a was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_global_ip_created_for_svc_or_pod pod "$netshoot_pod_cluster_a" $TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on Netshoot Pod (${netshoot_pod_cluster_a}${TEST_NS:+ in $TEST_NS})"
  netshoot_global_ip="$GLOBAL_IP"

  # TODO: Ping to the netshoot_global_ip


  PROMPT "Testing GlobalNet connectivity - From Netshoot pod ${netshoot_pod_cluster_a} (IP ${netshoot_global_ip}) on cluster A
  To Nginx service on cluster B, by its Global IP: $nginx_global_ip:${NGINX_PORT}"

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  ${OC} exec ${netshoot_pod_cluster_a} ${TEST_NS:+-n $TEST_NS} \
  -- curl --output /dev/null --max-time 30 --verbose ${nginx_global_ip}:${NGINX_PORT}

  #TODO: validate annotation of globalIp in the node
}

# ------------------------------------------

function test_clusters_connected_full_domain_name() {
### Nginx service on cluster B, will be identified by its Domain Name ###
# This is to test service-discovery (Lighthouse) of NON-headless $NGINX_CLUSTER_B service, on the default namespace

  trap_to_debug_commands;

  # Set FQDN on clusterset.local when using Service-Discovery (lighthouse)
  local nginx_cl_b_dns="${NGINX_CLUSTER_B}${TEST_NS:+.$TEST_NS}.svc.${MULTI_CLUSTER_DOMAIN}"

  PROMPT "Testing Service-Discovery: From Netshoot pod on cluster A${TEST_NS:+ (Namespace $TEST_NS)}
  To the default Nginx service on cluster B${TEST_NS:+ (Namespace ${TEST_NS:-default})}, by DNS hostname: $nginx_cl_b_dns"

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

  echo "# Try to ping ${NGINX_CLUSTER_B} until getting expected FQDN: $nginx_cl_b_dns (and IP)"
  #TODO: Validate both GlobalIP and svc.${MULTI_CLUSTER_DOMAIN} with   ${OC} get all
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

  echo "# Try to CURL from ${NETSHOOT_CLUSTER_A} to ${nginx_cl_b_dns}:${NGINX_PORT} :"
  ${OC} exec ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_cl_b_dns}:${NGINX_PORT}"

  # TODO: Test connectivity with https://github.com/tsliwowicz/go-wrk

}

# ------------------------------------------

function test_clusters_cannot_connect_short_service_name() {
### Negative test for nginx_cl_b_short_dns FQDN ###

  trap_to_debug_commands;

  local nginx_cl_b_short_dns="${NGINX_CLUSTER_B}${TEST_NS:+.$TEST_NS}"

  PROMPT "Testing Service-Discovery:
  There should be NO DNS resolution from cluster A to the local Nginx address on cluster B: $nginx_cl_b_short_dns (FQDN without \"clusterset\")"

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

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
  PROMPT "Install NEW Netshoot pod on AWS cluster A${TEST_NS:+ (Namespace $TEST_NS)}"
  export "KUBECONFIG=${KUBECONF_CLUSTER_A}" # Can also use --context ${CLUSTER_A_NAME} on all further oc commands

  [[ -z "$TEST_NS" ]] || create_namespace "$TEST_NS"

  ${OC} delete pod ${NEW_NETSHOOT_CLUSTER_A} --ignore-not-found ${TEST_NS:+-n $TEST_NS} || :

  ${OC} run ${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --image ${NETSHOOT_IMAGE} \
  --pod-running-timeout=5m --restart=Never -- sleep 5m

  echo "# Wait up to 3 minutes for NEW Netshoot pod [${NEW_NETSHOOT_CLUSTER_A}] to be ready:"
  ${OC} wait --timeout=3m --for=condition=ready pod -l run=${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
  ${OC} describe pod ${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
}

# ------------------------------------------

function test_new_netshoot_global_ip_cluster_a() {
### Check that $NEW_NETSHOOT_CLUSTER_A on the $TEST_NS is annotated with GlobalNet IP ###

  trap_to_debug_commands;
  PROMPT "Testing GlobalNet annotation - NEW Netshoot pod on AWS cluster A (public) should get a GlobalNet IP"
  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

  # netshoot_pod=$(${OC} get pods -l run=${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} \
  # --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')
  # get_running_pod_by_label "run=${NEW_NETSHOOT_CLUSTER_A}" "${TEST_NS}"

  # Should fail if NEW_NETSHOOT_CLUSTER_A was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_global_ip_created_for_svc_or_pod pod "$NEW_NETSHOOT_CLUSTER_A" $TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on NEW Netshoot Pod (${NEW_NETSHOOT_CLUSTER_A}${TEST_NS:+ in $TEST_NS})"
}

# ------------------------------------------

function install_nginx_headless_namespace_cluster_b() {
### Install $NGINX_CLUSTER_B on the $HEADLESS_TEST_NS namespace ###

  trap_to_debug_commands;
  PROMPT "Install HEADLESS Nginx service on OSP cluster B${HEADLESS_TEST_NS:+ (Namespace $HEADLESS_TEST_NS)}"
  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"

  echo "# Creating ${NGINX_CLUSTER_B}:${NGINX_PORT} in ${HEADLESS_TEST_NS}, using ${NGINX_IMAGE}, and disabling it's cluster-ip (with '--cluster-ip=None'):"

  install_nginx_service "${NGINX_CLUSTER_B}" "${NGINX_IMAGE}" "${HEADLESS_TEST_NS}" "--port=${NGINX_PORT} --cluster-ip=None"
}

# ------------------------------------------

function test_nginx_headless_global_ip_cluster_b() {
### Check that $NGINX_CLUSTER_B on the $HEADLESS_TEST_NS is annotated with GlobalNet IP ###

  trap_to_debug_commands;

  PROMPT "Testing GlobalNet annotation - The HEADLESS Nginx service on OSP cluster B should get a GlobalNet IP"

  if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then
    BUG "HEADLESS Service is not supported with GlobalNet" \
     "No workaround yet - Skip the whole test" \
    "https://github.com/submariner-io/lighthouse/issues/273"
    # No workaround yet
    FAILURE "Mark this test as failed, but continue"
  fi

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"

  # Should fail if NGINX_CLUSTER_B was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_global_ip_created_for_svc_or_pod svc "$NGINX_CLUSTER_B" $HEADLESS_TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FAILURE "GlobalNet error on the HEADLESS Nginx service (${NGINX_CLUSTER_B}${HEADLESS_TEST_NS:+.$HEADLESS_TEST_NS})"

  # TODO: Ping to the new_nginx_global_ip
  # new_nginx_global_ip="$GLOBAL_IP"
}

# ------------------------------------------

function test_clusters_connected_headless_service_on_new_namespace() {
### Nginx service on cluster B, will be identified by its Domain Name (with service-discovery) ###

  trap_to_debug_commands;

  # Set FQDN on clusterset.local when using Service-Discovery (lighthouse)
  local nginx_headless_cl_b_dns="${NGINX_CLUSTER_B}${HEADLESS_TEST_NS:+.$HEADLESS_TEST_NS}.svc.${MULTI_CLUSTER_DOMAIN}"

  PROMPT "Testing Service-Discovery: From NEW Netshoot pod on cluster A${TEST_NS:+ (Namespace $TEST_NS)}
  To the HEADLESS Nginx service on cluster B${HEADLESS_TEST_NS:+ (Namespace $HEADLESS_TEST_NS)}, by DNS hostname: $nginx_headless_cl_b_dns"

  if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then

    BUG "HEADLESS Service is not supported with GlobalNet" \
     "No workaround yet - Skip the whole test" \
    "https://github.com/submariner-io/lighthouse/issues/273"
    # No workaround yet - skipping test
    return

  else

    export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

    echo "# Try to ping HEADLESS ${NGINX_CLUSTER_B} until getting expected FQDN: $nginx_headless_cl_b_dns (and IP)"
    #TODO: Validate both GlobalIP and svc.${MULTI_CLUSTER_DOMAIN} with   ${OC} get all
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

    echo "# Try to CURL from ${NEW_NETSHOOT_CLUSTER_A} to ${nginx_headless_cl_b_dns}:${NGINX_PORT} :"
    ${OC} exec ${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_headless_cl_b_dns}:${NGINX_PORT}"

    # TODO: Test connectivity with https://github.com/tsliwowicz/go-wrk

  fi

}

# ------------------------------------------

function test_clusters_cannot_connect_headless_short_service_name() {
### Negative test for HEADLESS nginx_cl_b_short_dns FQDN ###

  trap_to_debug_commands;

  local nginx_cl_b_short_dns="${NGINX_CLUSTER_B}${HEADLESS_TEST_NS:+.$HEADLESS_TEST_NS}"

  PROMPT "Testing Service-Discovery:
  There should be NO DNS resolution from cluster A to the local Nginx address on cluster B: $nginx_cl_b_short_dns (FQDN without \"clusterset\")"

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"

  msg="# Negative Test - ${nginx_cl_b_short_dns}:${NGINX_PORT} should not be reachable (FQDN without \"clusterset\")."

  ${OC} exec ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} \
  -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_cl_b_short_dns}:${NGINX_PORT}" \
  |& (! highlight "command terminated with exit code" && FATAL "$msg") || echo -e "$msg"
    # command terminated with exit code 28

}

# ------------------------------------------

function test_subctl_show_and_validate_on_merged_kubeconfigs() {
### Test subctl show commands on merged kubeconfig ###
  PROMPT "Testing SUBCTL show command on merged kubeconfig of multiple clusters"
  trap_to_debug_commands;

  local subctl_info

  export KUBECONFIG="${KUBECONF_CLUSTER_A}:${KUBECONF_CLUSTER_B}:${KUBECONF_CLUSTER_C}"

  ${OC} config get-contexts

  subctl show versions || subctl_info=ERROR

  subctl show networks || subctl_info=ERROR

  subctl show endpoints || subctl_info=ERROR

  subctl show connections || subctl_info=ERROR

  subctl show gateways || subctl_info=ERROR

  # For Subctl > 0.8 : Run subctl diagnose
  if [[ $(subctl version | grep --invert-match "v0.8") ]] ; then
    BUG "subctl diagnose to return relevant exit code on Submariner failures" \
    "No workaround is required" \
    "https://github.com/submariner-io/submariner-operator/issues/1310"

    subctl diagnose all || subctl_info=ERROR
  fi

  if [[ "$subctl_info" = ERROR ]] ; then
    FAILURE "Subctl show/diagnose failed on merged kubeconfig"

    BUG "Subctl error obtaining the Submariner resource: Unauthorized" \
    "It may happened due to merged kubeconfigs - ignoring failures" \
    "https://bugzilla.redhat.com/show_bug.cgi?id=1950960"
  fi

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

  # go test -v -cover \
  # ./pkg/apis/submariner.io/v1 \
  # ./pkg/cable/libreswan \
  # ./pkg/cableengine/syncer \
  # ./pkg/controllers/datastoresyncer \
  # ./pkg/controllers/tunnel \
  # ./pkg/event \
  # ./pkg/event/controller \
  # ./pkg/globalnet/controllers/ipam \
  # ./pkg/routeagent/controllers/route \
  # ./pkg/util \
  # -ginkgo.v -ginkgo.trace \
  # -ginkgo.reportPassed ${junit_params}

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

  local test_params=$([[ "$globalnet" =~ ^(y|yes)$ ]] && echo "--globalnet")

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

  export KUBECONFIG="${KUBECONF_CLUSTER_A}:${KUBECONF_CLUSTER_B}:${KUBECONF_CLUSTER_C}"

  ${OC} config get-contexts
    # CURRENT   NAME              CLUSTER            AUTHINFO   NAMESPACE
    # *         admin             user-cluster-a   admin
    #           admin_cluster_b   user-cl1         admin

  export GO111MODULE="on"
  go env

  local junit_params
  if [[ "$create_junit_xml" =~ ^(y|yes)$ ]]; then
    echo -e "\n# Junit report will be created at: $junit_output_file \n"
    junit_params="-ginkgo.reportFile $junit_output_file"
  fi

  test_params="$test_params
  --dp-context ${CLUSTER_A_NAME} --dp-context ${CLUSTER_B_NAME}
  --submariner-namespace ${SUBM_NAMESPACE}
  --connection-timeout 30 --connection-attempts 3"

  local msg="# Running End-to-End tests with GO in project: \n# $e2e_project_path
  \n# Ginkgo test parameters: $test_params"

  echo -e "$msg \n# Output will be printed both to stdout and to $E2E_LOG file."
  echo -e "$msg" >> "$E2E_LOG"

  go test -v ./test/e2e \
  -timeout 120m \
  -ginkgo.v -ginkgo.trace \
  -ginkgo.randomizeAllSpecs \
  -ginkgo.noColor \
  -ginkgo.reportPassed ${junit_params} \
  -ginkgo.skip "\[redundancy\]" \
  -args $test_params | tee -a "$E2E_LOG"

}

# ------------------------------------------

function test_subctl_benchmarks() {
  PROMPT "Testing subctl benchmark: latency and throughput tests"
  trap_to_debug_commands;

  # TODO: Add tests for Cluster C

  subctl benchmark latency ${KUBECONF_CLUSTER_A} ${KUBECONF_CLUSTER_B} || \
  FAILURE "Submariner benchmark latency tests have ended with failures, please investigate."

  subctl benchmark throughput ${KUBECONF_CLUSTER_A} ${KUBECONF_CLUSTER_B} || \
  FAILURE "Submariner benchmark throughput tests have ended with failures, please investigate."

}

# ------------------------------------------

function test_submariner_e2e_with_subctl() {
# Run E2E Tests of Submariner:
  PROMPT "Testing Submariner End-to-End tests with SubCtl command"
  trap_to_debug_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_A}:${KUBECONF_CLUSTER_B}:${KUBECONF_CLUSTER_C}"

  ${OC} config get-contexts

  [[ -x "$(command -v subctl)" ]] || FATAL "No SubCtl installation found. Try to run again with option '--subctl-version'"
  subctl version

  BUG "No Subctl option to set -ginkgo.reportFile" \
  "No workaround yet..." \
  "https://github.com/submariner-io/submariner-operator/issues/509"

  echo "# SubCtl E2E output will be printed both to stdout and to the file $E2E_LOG"
  # subctl verify --disruptive-tests --verbose ${KUBECONF_CLUSTER_A} ${KUBECONF_CLUSTER_B} | tee -a "$E2E_LOG"
  subctl verify --only service-discovery,connectivity --verbose ${KUBECONF_CLUSTER_A} ${KUBECONF_CLUSTER_B} | tee -a "$E2E_LOG"

}

# ------------------------------------------

function upload_junit_xml_to_polarion() {
  trap_to_debug_commands;
  local junit_file="$1"
  echo -e "\n### Uploading test results to Polarion from Junit file: $junit_file ###\n"

  create_polarion_testcases_doc_from_junit "https://$POLARION_SERVER/polarion" "$POLARION_AUTH" "$junit_file" \
  "$POLARION_PROJECT_ID" "$POLARION_TEAM_NAME" "$POLARION_USR" "$POLARION_COMPONENT_ID" "$POLARION_TESTCASES_DOC"

  create_polarion_testrun_result_from_junit "https://$POLARION_SERVER/polarion" "$POLARION_AUTH" \
  "$junit_file" "$POLARION_PROJECT_ID" "$POLARION_TEAM_NAME" "$POLARION_TESTRUN_TEMPLATE"

}

# ------------------------------------------

function create_all_test_results_in_polarion() {
  PROMPT "Upload all test results to Polarion"
  trap_to_debug_commands;

  # Get test exit status (from file $TEST_STATUS_FILE)
  test_status="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat $TEST_STATUS_FILE)"
  echo -e "\n# Publishing to Polarion should be run only if $TEST_STATUS_FILE is not empty: [${test_status}] \n"

  # Temp file to store Polarion output
  local polarion_output="`mktemp`_polarion"
  local polarion_rc=0

  # Upload SYSTEM tests to Polarion
  echo "# Upload Junit results of SYSTEM (Shell) tests to Polarion:"

  # Redirect output to stdout and to $polarion_output, in order to get polarion testrun url into report
  upload_junit_xml_to_polarion "$SHELL_JUNIT_XML" |& tee "$polarion_output" || polarion_rc=1

  add_polarion_testrun_url_to_report_description "$polarion_output"


  # Upload Ginkgo E2E tests to Polarion
  if [[ (! "$skip_tests" =~ ((e2e|all)(,|$))+) && -s "$E2E_JUNIT_XML" ]] ; then

    echo "# Upload Junit results of Submariner E2E (Ginkgo) tests to Polarion:"

    # Redirecting with TEE to stdout and to $polarion_output, in order to get polarion testrun url into report
    upload_junit_xml_to_polarion "$E2E_JUNIT_XML" |& tee "$polarion_output" || polarion_rc=1
    add_polarion_testrun_url_to_report_description "$polarion_output"

    echo "# Upload Junit results of Lighthouse E2E (Ginkgo) tests to Polarion:"

    # Redirecting with TEE to stdout and to $polarion_output, in order to get polarion testrun url into report
    upload_junit_xml_to_polarion "$LIGHTHOUSE_JUNIT_XML" |& tee "$polarion_output" || polarion_rc=1
    add_polarion_testrun_url_to_report_description "$polarion_output"

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

function add_polarion_testrun_url_to_report_description() {
# Helper function to search polarion testrun url in input log file, to add later to the HTML report
  trap_to_debug_commands;

  local polarion_output="$1"

  echo "# Add new Polarion Test run results to the Html report description: "
  local results_link=$(grep -Poz '(?s)Test suite.*\n.*Polarion results published[^\n]*' "$polarion_output" | sed -z 's/\.\n.* to:/:\n/' || :)

  if [[ -n "$results_link" ]] ; then
    echo "$results_link" | sed -r 's/(https:[^ ]*)/\1\&tab=records/g' >> "$POLARION_REPORTS" || :
  else
    echo "Error reading Polarion Test results link $results_link" 1>&2
  fi

}

# ------------------------------------------

function env_teardown() {
  # Run tests and environment functions at the end (call with trap exit)

  ${junit_cmd} test_products_versions_cluster_a || :

  [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_products_versions_cluster_b || :

  [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_products_versions_cluster_c || :

}

# ------------------------------------------

function test_products_versions_cluster_a() {
  PROMPT "Show products versions on cluster A"

  export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
  test_products_versions "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_products_versions_cluster_b() {
  PROMPT "Show products versions on cluster B"

  export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
  test_products_versions "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_products_versions_cluster_c() {
  PROMPT "Show products versions on cluster C"

  export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
  test_products_versions "${CLUSTER_C_NAME}"
}

# ------------------------------------------

function test_products_versions() {
# Show OCP clusters versions, and Submariner version
  trap '' DEBUG # DONT trap_to_debug_commands

  local cluster_name="$1"

  echo -e "\n### OCP Cluster ${cluster_name} ###"
  ${OC} version

  echo -e "\n### Submariner components ###\n"

  subctl version || :

  subctl show versions || :

  # Show images info of running pods
  print_images_info_of_namespace_pods "${SUBM_NAMESPACE}"

  # Show image-stream tags
  print_image_tags_info "${SUBM_NAMESPACE}"

  # # Show REGISTRY_MIRROR images
  # ${OC} get images | grep "${REGISTRY_MIRROR}" |\
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

  # Show Libreswan (cable driver) version in the active gateway pod
  local gw_label='app=submariner-gateway'
  # For Subctl <= 0.8 : 'app=submariner-engine' is expected as the Gateway pod label"
  [[ $(subctl version | grep --invert-match "v0.8") ]] || gw_label="app=submariner-engine"

  local submariner_gateway_pod="`get_running_pod_by_label "$gw_label" "$SUBM_NAMESPACE" 2>/dev/null || :`"

  if [[ -n "$submariner_gateway_pod" ]] ; then
    echo -e "\n### Linux version on the running '$gw_label' pod: $submariner_gateway_pod ###"
    ${OC} exec $submariner_gateway_pod -n ${SUBM_NAMESPACE} -- bash -c "cat /etc/os-release" | awk -F\" '/PRETTY_NAME/ {print $2}' || :
    echo -e "\n\n"

    echo -e "\n### LibreSwan version on the running '$gw_label' pod: $submariner_gateway_pod ###"
    ${OC} exec $submariner_gateway_pod -n ${SUBM_NAMESPACE} -- bash -c "rpm -qa libreswan" || :
    echo -e "\n\n"
  fi

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

    echo -e "\n############################## Openshift information ##############################\n"

    export KUBECONFIG="${KUBECONF_CLUSTER_A}:${KUBECONF_CLUSTER_B}:${KUBECONF_CLUSTER_C}"

    # oc version
    BUG "OC client version 4.5.1 cannot use merged kubeconfig" \
    "use an older OC client, or run oc commands for each cluster separately" \
    "https://bugzilla.redhat.com/show_bug.cgi?id=1857202"
    # Workaround:
    OC="/usr/bin/oc"

    ${OC} config view || :
    ${OC} status || :
    ${OC} version || :

    echo -e "\n############################## Submariner information (subctl show and diagnose) ##############################\n"

    subctl show all || :

    subctl diagnose all || :

    export "KUBECONFIG=${KUBECONF_CLUSTER_A}"
    print_resources_and_pod_logs "${CLUSTER_A_NAME}"

    if [[ -s "$CLUSTER_B_YAML" ]] ; then
      export "KUBECONFIG=${KUBECONF_CLUSTER_B}"
      print_resources_and_pod_logs "${CLUSTER_B_NAME}"
    fi

    if [[ -s "$CLUSTER_C_YAML" ]] ; then
      export "KUBECONFIG=${KUBECONF_CLUSTER_C}"
      print_resources_and_pod_logs "${CLUSTER_C_NAME}"
    fi

  ) |& tee -a $log_file

}

# ------------------------------------------

function print_resources_and_pod_logs() {
  trap_to_debug_commands;
  local cluster_name="$1"

  PROMPT "Submariner logs and OCP events on ${cluster_name}"

  echo -e "
  \n################################################################################################ \
  \n#                             Openshift Nodes on ${cluster_name}                               # \
  \n################################################################################################ \
  \n"

  ${OC} get nodes || :

  echo -e "
  \n################################################################################################ \
  \n#                  Submariner Gateway and Deployments on ${cluster_name}                       # \
  \n################################################################################################ \
  \n"

  ${OC} get all -n ${SUBM_NAMESPACE} --show-labels || :

  ${OC} describe Submariner -n ${SUBM_NAMESPACE} || :
  # ${OC} get Submariner -o yaml -n ${SUBM_NAMESPACE} || :

  ${OC} describe Gateway -n ${SUBM_NAMESPACE} || :

  ${OC} describe deployments -n ${SUBM_NAMESPACE} || :
  #  ${OC} get deployments -o yaml -n ${SUBM_NAMESPACE} || :

  echo -e "
  \n################################################################################################ \
  \n#             Submariner Daemons, Replicas and configurations on ${cluster_name}               # \
  \n################################################################################################ \
  \n"

  ${OC} get daemonsets -A || :

  ${OC} describe ds -n ${SUBM_NAMESPACE} || :

  ${OC} describe rs -n ${SUBM_NAMESPACE} || :

  ${OC} describe cm -n openshift-dns || :

  # TODO: Loop on each cluster: ${OC} describe cluster "${cluster_name}" -n ${SUBM_NAMESPACE} || :

  # for pod in $(${OC} get pods -A \
  # -l 'name in (submariner-operator,submariner-gateway,submariner-globalnet,kube-proxy)' \
  # -o jsonpath='{.items[0].metadata.namespace} {.items[0].metadata.name}' ; do
  #     echo "######################: Logs for Pod $pod :######################"
  #     ${OC}  -n $ns describe pod $name
  #     ${OC}  -n $namespace logs $pod
  # done

  echo -e "
  \n################################################################################################ \
  \n#                             Openshift Machines on ${cluster_name}                              # \
  \n################################################################################################ \
  \n"

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

  echo -e "
  \n################################################################################################ \
  \n#                             Submariner LOGS on ${cluster_name}                              # \
  \n################################################################################################ \
  \n"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "name=submariner-operator"

  local gw_label='app=submariner-gateway'
  # For Subctl <= 0.8 : 'app=submariner-engine' is expected as the Gateway pod label"
  [[ $(subctl version | grep --invert-match "v0.8") ]] || gw_label="app=submariner-engine"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" $gw_label

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-globalnet"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-lighthouse-agent"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-lighthouse-coredns"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-routeagent"

  print_pod_logs_in_namespace "$cluster_name" "kube-system" "k8s-app=kube-proxy"

  print_pod_logs_in_namespace "$cluster_name" "kube-system" "component=kube-controller-manager"

  echo -e "\n############################## End of Submariner logs collection on ${cluster_name} ##############################\n"

  echo -e "\n############################## ALL Openshift events on ${cluster_name} ##############################\n"

  ${OC} get events -A --sort-by='.metadata.creationTimestamp' \
  -o custom-columns=FirstSeen:.firstTimestamp,LastSeen:.lastTimestamp,Count:.count,From:.source.component,Type:.type,Reason:.reason,Message:.message || :

}

# ------------------------------------------

# Functions to debug this script

function test_debug_pass() {
  trap_to_debug_commands;
  PROMPT "PASS test for DEBUG"

  if [[ -n "TRUE" ]] ; then
    BUG "A dummy bug" \
     "A workaround" \
    "A link"

    # Test FAILURE() that should not break script
    FAILURE "PASS_HERE"
  fi

  echo "should not get here..."

}

function test_debug_fail() {
  trap_to_debug_commands;
  PROMPT "FAIL test for DEBUG"
  echo "Should not get here if calling after a bad exit code (e.g. FAILURE or FATAL)"
  # find ${CLUSTER_A_DIR} -name "*.log" -print0 | xargs -0 cat

  local TEST=1
  if [[ -n "$TEST" ]] ; then
    return 1
  fi
}

function test_debug_fatal() {
  trap_to_debug_commands;
  PROMPT "FATAL test for DEBUG"
  FATAL "Terminating script since test_debug_fail() did not"
}

# ------------------------------------------


####################################################################################
#                    Main - Submariner Deploy and Tests                            #
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

# TODO: Check each $CLUSTER_A/B/C_YAML to determine if it's OCPUP install or OCP install

# Setting Cluster A and Broker config ($WORKDIR and $CLUSTER_A_NAME were set in subm_variables file)
export KUBECONF_BROKER=${WORKDIR}/${BROKER_CLUSTER_NAME}/auth/kubeconfig
export CLUSTER_A_DIR=${WORKDIR}/${CLUSTER_A_NAME}
export KUBECONF_CLUSTER_A=${CLUSTER_A_DIR}/auth/kubeconfig

# Setting Cluster B config ($OCPUP_DIR and $CLUSTER_B_YAML were set in subm_variables file)
export CLUSTER_B_DIR=${OCPUP_DIR}/.config/$(awk '/clusterName:/ {print $NF}' "${CLUSTER_B_YAML}")
export KUBECONF_CLUSTER_B=${CLUSTER_B_DIR}/auth/kubeconfig

# Setting Cluster C config ($WORKDIR and $CLUSTER_C_NAME were set in subm_variables file)
export CLUSTER_C_DIR=${WORKDIR}/${CLUSTER_C_NAME}
export KUBECONF_CLUSTER_C=${CLUSTER_C_DIR}/auth/kubeconfig

# Printing output both to stdout and to $SYS_LOG with tee
# TODO: consider adding timestamps with: ts '%H:%M:%.S' -s
(
  # Print planned steps according to CLI/User inputs
  ${junit_cmd} show_test_plan

  # Setup and verify environment
  setup_workspace

  # Set script trap functions
  set_trap_functions

  # # Debug functions
  # ${junit_cmd} test_debug_pass
  # ${junit_cmd} test_debug_fail
  # rc=$?
  # BUG "test_debug_fail - Exit code: $rc" \
  # "If RC $rc = 5 - junit_cmd should continue execution"
  # ${junit_cmd} test_debug_pass
  # ${junit_cmd} test_debug_fatal

  ### Destroy / Create / Clean OCP Clusters (if not requested to skip_ocp_setup) ###

  if [[ ! "$skip_ocp_setup" =~ ^(y|yes)$ ]]; then

    # Running download_ocp_installer if requested
    [[ ! "$get_ocp_installer" =~ ^(y|yes)$ ]] || ${junit_cmd} download_ocp_installer ${OCP_VERSION}

    # Running build_ocpup_tool_latest if requested
    [[ ! "$get_ocpup_tool" =~ ^(y|yes)$ ]] || ${junit_cmd} build_ocpup_tool_latest

    # Running reset_cluster_a if requested
    if [[ "$reset_cluster_a" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} destroy_aws_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_NAME"

      ${junit_cmd} prepare_install_aws_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_YAML" "$CLUSTER_A_NAME"

      ${junit_cmd} create_aws_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_NAME"

    else
      # Running destroy_aws_cluster and create_aws_cluster separately
      if [[ "$destroy_cluster_a" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} destroy_aws_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_NAME"

      fi

      if [[ "$create_cluster_a" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} prepare_install_aws_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_YAML" "$CLUSTER_A_NAME"

        ${junit_cmd} create_aws_cluster "$CLUSTER_A_DIR" "$CLUSTER_A_NAME"

      fi
    fi

    # Running reset_cluster_b if requested
    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      if [[ "$reset_cluster_b" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} destroy_osp_cluster

        ${junit_cmd} create_osp_cluster

      else
        # Running destroy_osp_cluster and create_osp_cluster separately
        if [[ "$destroy_cluster_b" =~ ^(y|yes)$ ]] ; then

          ${junit_cmd} destroy_osp_cluster

        fi

        if [[ "$create_cluster_b" =~ ^(y|yes)$ ]] ; then

          ${junit_cmd} create_osp_cluster

        fi
      fi
    fi

    # Running reset_cluster_c if requested
    if [[ -s "$CLUSTER_C_YAML" ]] ; then

      if [[ "$reset_cluster_c" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} destroy_aws_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_NAME"

        ${junit_cmd} prepare_install_aws_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_YAML" "$CLUSTER_C_NAME"

        ${junit_cmd} create_aws_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_NAME"

      else
        # Running destroy_aws_cluster and create_cluster_c separately
        if [[ "$destroy_cluster_c" =~ ^(y|yes)$ ]] ; then

          ${junit_cmd} destroy_aws_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_NAME"

        fi

        if [[ "$create_cluster_c" =~ ^(y|yes)$ ]] ; then

          ${junit_cmd} prepare_install_aws_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_YAML" "$CLUSTER_C_NAME"

          ${junit_cmd} create_aws_cluster "$CLUSTER_C_DIR" "$CLUSTER_C_NAME"

        fi
      fi
    fi

    # Verify clusters status after OCP reset/create

    ${junit_cmd} test_kubeconfig_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_kubeconfig_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_kubeconfig_cluster_c

    ### Cleanup Submariner from all clusters ###

    # Running cleanup on cluster A if requested
    if [[ "$clean_cluster_a" =~ ^(y|yes)$ ]] && [[ ! "$destroy_cluster_a" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} clean_submariner_namespace_and_resources_cluster_a

      ${junit_cmd} clean_node_labels_and_machines_cluster_a

      ${junit_cmd} delete_old_submariner_images_from_cluster_a

    fi

    # Running cleanup on cluster B if requested
    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      if [[ "$clean_cluster_b" =~ ^(y|yes)$ ]] && [[ ! "$destroy_cluster_b" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} clean_submariner_namespace_and_resources_cluster_b

        ${junit_cmd} clean_node_labels_and_machines_cluster_b

        ${junit_cmd} delete_old_submariner_images_from_cluster_b

      fi
    fi

    # Running cleanup on cluster C if requested
    if [[ -s "$CLUSTER_C_YAML" ]] ; then

      if [[ "$clean_cluster_c" =~ ^(y|yes)$ ]] && [[ ! "$destroy_cluster_c" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} clean_submariner_namespace_and_resources_cluster_c

        ${junit_cmd} clean_node_labels_and_machines_cluster_c

        ${junit_cmd} delete_old_submariner_images_from_cluster_c

      fi
    fi

    ${junit_cmd} open_firewall_ports_on_the_broker_node

    # TODO: Run only if it's an openstack (on-prem) cluster
    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} open_firewall_ports_on_openstack_cluster_b

    ${junit_cmd} label_gateway_on_broker_nodes_with_external_ip

    ${junit_cmd} configure_images_prune_cluster_a

    if [[ -s "$CLUSTER_B_YAML" ]] ; then

      ${junit_cmd} label_first_gateway_cluster_b

      ${junit_cmd} configure_images_prune_cluster_b

    fi

    if [[ -s "$CLUSTER_C_YAML" ]] ; then

      ${junit_cmd} label_first_gateway_cluster_c

      ${junit_cmd} configure_images_prune_cluster_c

    fi

    # Overriding Submariner images with custom images from registry, if requested with --registry-images
    if [[ "$registry_images" =~ ^(y|yes)$ ]] ; then

      # ${junit_cmd} remove_submariner_images_from_local_registry_with_podman

      ${junit_cmd} configure_custom_registry_cluster_a

      ${junit_cmd} upload_custom_images_to_registry_cluster_a

      if [[ -s "$CLUSTER_B_YAML" ]] ; then

        ${junit_cmd} configure_custom_registry_cluster_b

        ${junit_cmd} upload_custom_images_to_registry_cluster_b

      fi

      if [[ -s "$CLUSTER_C_YAML" ]] ; then

        ${junit_cmd} configure_custom_registry_cluster_c

        ${junit_cmd} upload_custom_images_to_registry_cluster_c

      fi

    fi

  else
    # Verify clusters status even if OCP setup/cleanup was skipped

    ${junit_cmd} test_kubeconfig_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_kubeconfig_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_kubeconfig_cluster_c

  fi
  ### END of OCP Clusters Setup ###

  # Running basic pre-submariner tests (only required for sys tests on new/cleaned clusters)
  if [[ ! "$skip_tests" =~ ((sys|all)(,|$))+ ]] && [[ -s "$CLUSTER_B_YAML" ]] ; then

    # TODO: Need to add tests for cluster C

    ${junit_cmd} configure_namespace_for_submariner_tests_on_cluster_a

    ${junit_cmd} configure_namespace_for_submariner_tests_on_cluster_b

    ${junit_cmd} install_netshoot_app_on_cluster_a

    ${junit_cmd} install_nginx_svc_on_cluster_b

    ${junit_cmd} test_basic_cluster_connectivity_before_submariner

    ${junit_cmd} test_clusters_disconnected_before_submariner
  fi


  ### Deploy Submariner on the clusters (if not requested to skip_install) ###

  echo -e "# OCP clusters and environment setup is ready.
  \n# From this point, if script fails - \$TEST_STATUS_FILE is considered FAILED, and will be reported to Polarion.
  \n# ($TEST_STATUS_FILE with exit code 1)"

  echo 1 > $TEST_STATUS_FILE

  # Running download_and_install_subctl
  if [[ "$download_subctl" =~ ^(y|yes)$ ]] ; then
    ${junit_cmd} download_and_install_subctl "$SUBM_VER_TAG"
  fi

  if [[ ! "$skip_install" =~ ^(y|yes)$ ]]; then

    # Running build_operator_latest if requested  # [DEPRECATED]
    # [[ ! "$build_operator" =~ ^(y|yes)$ ]] || ${junit_cmd} build_operator_latest

    ${junit_cmd} test_subctl_command

    # ${junit_cmd} label_gateway_on_broker_nodes_with_external_ip
    #
    # [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} label_first_gateway_cluster_b
    #
    # [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} label_first_gateway_cluster_c

    ${junit_cmd} set_join_parameters_for_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} set_join_parameters_for_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} set_join_parameters_for_cluster_c

    # # Overriding Submariner images with custom images from registry
    # if [[ "$registry_images" =~ ^(y|yes)$ ]]; then
    #
    #   ${junit_cmd} upload_custom_images_to_registry_cluster_a
    #
    #   [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} upload_custom_images_to_registry_cluster_b
    #
    #   [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} upload_custom_images_to_registry_cluster_c
    #
    # fi

    ${junit_cmd} install_broker_cluster_a

    ${junit_cmd} test_broker_before_join

    ${junit_cmd} run_subctl_join_on_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} run_subctl_join_on_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} run_subctl_join_on_cluster_c

  fi

  ### Running High-level / E2E / Unit Tests (if not requested to skip sys / all tests) ###

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

    ${junit_cmd} test_ipsec_status_cluster_a

    [[ ! -s "$CLUSTER_B_YAML" ]] || ${junit_cmd} test_ipsec_status_cluster_b

    [[ ! -s "$CLUSTER_C_YAML" ]] || ${junit_cmd} test_ipsec_status_cluster_c

    ${junit_cmd} test_subctl_show_and_validate_on_merged_kubeconfigs

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

      # TODO: Add tests for Cluster C

      ${junit_cmd} test_clusters_connected_by_service_ip

      ${junit_cmd} install_new_netshoot_cluster_a

      ${junit_cmd} install_nginx_headless_namespace_cluster_b

      if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} test_new_netshoot_global_ip_cluster_a

        ${junit_cmd} test_nginx_headless_global_ip_cluster_b
      fi

      # Test the default (pre-installed) netshoot and nginx with service-discovery

      ${junit_cmd} export_nginx_default_namespace_cluster_b

      ${junit_cmd} test_clusters_connected_full_domain_name

      ${junit_cmd} test_clusters_cannot_connect_short_service_name

      # Test the new netshoot and headless nginx service discovery

      if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then

          ${junit_cmd} test_clusters_connected_overlapping_cidrs

          # TODO: Test headless service with GLobalnet - when the feature of is supported
          BUG "HEADLESS Service is not supported with GlobalNet" \
           "No workaround yet - Skip the whole test" \
          "https://github.com/submariner-io/lighthouse/issues/273"
          # No workaround yet

      else
        ${junit_cmd} export_nginx_headless_namespace_cluster_b

        ${junit_cmd} test_clusters_connected_headless_service_on_new_namespace

        ${junit_cmd} test_clusters_cannot_connect_headless_short_service_name
      fi

    fi

    echo -e "# From this point, if script fails - \$TEST_STATUS_FILE is considered UNSTABLE, and will be reported to Polarion.
    \n# ($TEST_STATUS_FILE with exit code 2)"

    echo 2 > $TEST_STATUS_FILE
  fi


  ### Running Submariner tests with Ginkgo or with subctl commands

  if [[ ! "$skip_tests" =~ all ]]; then

    ### Running benchmark tests with subctl

    ${junit_cmd} test_subctl_benchmarks

    ### Compiling Submariner projects in order to run Ginkgo tests with GO

    if [[ "$build_go_tests" =~ ^(y|yes)$ ]] ; then
      verify_golang || FATAL "No Golang installation found. Try to run again with option '--config-golang'"

      ${junit_cmd} build_submariner_repos
    fi

    ### Running Unit-tests in Submariner project with Ginkgo

    if [[ ! "$skip_tests" =~ pkg ]] && [[ "$build_go_tests" =~ ^(y|yes)$ ]]; then
      ${junit_cmd} test_submariner_packages

      if tail -n 5 "$E2E_LOG" | grep "FAIL" ; then
        ginkgo_tests_status=FAILED
        BUG "Submariner Unit-Tests FAILED."
      fi

    fi

    if [[ ! "$skip_tests" =~ e2e ]]; then

      if [[ "$build_go_tests" =~ ^(y|yes)$ ]] ; then

      ### Running E2E tests in Submariner and Lighthouse projects with Ginkgo

        ${junit_cmd} test_submariner_e2e_with_go

        if tail -n 5 "$E2E_LOG" | grep 'FAIL!' ; then
          ginkgo_tests_status=FAILED
          BUG "Lighthouse End-to-End Ginkgo tests have FAILED"
        fi

        ${junit_cmd} test_lighthouse_e2e_with_go

        if tail -n 5 "$E2E_LOG" | grep 'FAIL!' ; then
          ginkgo_tests_status=FAILED
          BUG "Submariner End-to-End Ginkgo tests have FAILED"
        fi

      else

      ### Running E2E tests with subctl

        ${junit_cmd} test_submariner_e2e_with_subctl

        if tail -n 5 "$E2E_LOG" | grep 'FAIL!' ; then
          ginkgo_tests_status=FAILED
          BUG "SubCtl End-to-End tests have FAILED"
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


#####################################################################################
#   End Main - Now publish to Polarion, Create HTML report, and archive artifacts   #
#####################################################################################

# ------------------------------------------

cd ${SCRIPT_DIR}

# Get test exit status (from file $TEST_STATUS_FILE)
test_status="$([[ ! -s "$TEST_STATUS_FILE" ]] || cat $TEST_STATUS_FILE)"
echo -e "\n# Publishing to Polarion should be run only if $TEST_STATUS_FILE is not empty: [${test_status}] \n"

if [[ -n "$test_status" ]] ; then
  # Update the script exit code according to system tests status
  export SCRIPT_RC="$test_status"

  ### Upload Junit xmls to Polarion (if requested by user CLI)  ###
  if [[ "$upload_to_polarion" =~ ^(y|yes)$ ]] ; then
    # Redirecting output both to stdout and SYS_LOG
    create_all_test_results_in_polarion |& tee -a "$SYS_LOG" || :
  fi
fi

# ------------------------------------------

### Creating HTML report from console output ###

echo "# Creating HTML Report from:
# SYS_LOG = $SYS_LOG
# REPORT_NAME = $REPORT_NAME
# REPORT_FILE = $REPORT_FILE
"

# prompt message (this is the last print into $SYS_LOG)
message="Creating HTML Report"

# If $TEST_STATUS_FILE is not 0 (all Tests passed) or 2 (some tests passed) - it means that system tests have failed
if [[ "$test_status" != @(0|2) ]] ; then
  message="$message - System tests failed with exit status: $test_status"
  color="$RED"
fi
PROMPT "$message" "$color" |& tee -a "$SYS_LOG"

# Clean SYS_LOG from sh2ju debug lines (+++), if CLI option: --debug was NOT used
[[ "$script_debug_mode" =~ ^(yes|y)$ ]] || sed -i 's/+++.*//' "$SYS_LOG"


### Run log_to_html() to create REPORT_FILE (html) from SYS_LOG

if [[ -n "$REPORT_FILE" ]] ; then
  echo "# Remove path and replace all spaces from REPORT_FILE: '$REPORT_FILE'"
  REPORT_FILE="$(basename ${REPORT_FILE// /_})"
fi

if [[ -s "$POLARION_REPORTS" ]] ; then
  echo "# set REPORT_DESCRIPTION for html report:"
  cat "$POLARION_REPORTS"

  REPORT_DESCRIPTION="Polarion results:
  $(< "$POLARION_REPORTS")"
fi

log_to_html "$SYS_LOG" "$REPORT_NAME" "$REPORT_FILE" "$REPORT_DESCRIPTION"


# ------------------------------------------

### Collecting artifacts ###

# If REPORT_FILE was not passed externally, set it as the latest html file that was created
REPORT_FILE="${REPORT_FILE:-$(ls -1 -tu *.html | head -1)}"

# Compressing report to tar.gz
report_archive="${REPORT_FILE%.*}_${DATE_TIME}.tar.gz"

echo -e "# Compressing Report, Log, Kubeconfigs and $BROKER_INFO into: ${report_archive}"

# Copy required file to local directory
[[ ! -f "$KUBECONF_CLUSTER_A" ]] || cp -f "$KUBECONF_CLUSTER_A" "kubconf_${CLUSTER_A_NAME}"
[[ ! -f "$KUBECONF_CLUSTER_B" ]] || cp -f "$KUBECONF_CLUSTER_B" "kubconf_${CLUSTER_B_NAME}"
[[ ! -f "$WORKDIR/$BROKER_INFO" ]] || cp -f "$WORKDIR/$BROKER_INFO" "subm_${BROKER_INFO}"

find ${CLUSTER_A_DIR} -type f -name "*.log" -exec \
sh -c 'cp "{}" "cluster_a_$(basename "$(dirname "{}")")$(basename "{}")"' \;

find ${CLUSTER_B_DIR} -type f -name "*.log" -exec \
sh -c 'cp "{}" "cluster_b_$(basename "$(dirname "{}")")$(basename "{}")"' \;

tar --dereference --hard-dereference -cvzf $report_archive $(ls \
 "$REPORT_FILE" \
 "$SYS_LOG" \
 kubconf_* \
 subm_* \
 *.xml \
 *.log \
 2>/dev/null)

echo -e "# Archive \"$report_archive\" now contains:"
tar tvf $report_archive

echo -e "# To view in your Browser, run:\n tar -xvf ${report_archive}; firefox ${REPORT_FILE}"

echo "# Exiting script with \$SCRIPT_RC return code: [$SCRIPT_RC]"
exit $SCRIPT_RC

# ------------------------------------------
