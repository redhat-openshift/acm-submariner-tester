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
# - To validate, login to AWS openshift-dev account via the web console:                              #
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
  * Download OCP Installer version:                    --get-ocp-installer [latest / x.y.z]
  * Download latest OCPUP Tool:                        --get-ocpup-tool
  * Skip OCP clusters setup (destroy/create/clean):    --skip-ocp-setup
  * Install Golang if missing:                         --config-golang
  * Install AWS-CLI and configure access:              --config-aws-cli

- Submariner installation options:

  * Install latest release of Submariner:              --install-subctl
  * Install development release of Submariner:         --install-subctl-devel
  * Skip Submariner installation:                      --skip-install
  * Configure and test Service Discovery:              --service-discovery
  * Configure and test GlobalNet:                      --globalnet
  * Use specific IPSec (cable driver):                 --cable-driver [libreswan / strongswan]

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

- To run interactively (enter options manually):

  `./setup_subm.sh`


- Examples with pre-defined options:

  `./setup_subm.sh --clean-cluster-a --clean-cluster-b --install-subctl-devel --globalnet`

  * Reuse (clean) existing clusters
  * Install latest Submariner release
  * Configure GlobalNet (for overlapping clusters CIDRs)
  * Run Submariner E2E tests (with subctl)


  `./setup_subm.sh --get-ocp-installer 4.5.1 --reset-cluster-a --clean-cluster-b --install-subctl --service-discovery --build-tests --junit`

  * Download OCP installer version 4.5.1
  * Recreate new cluster on AWS (cluster A)
  * Clean existing cluster on OSP (cluster B)
  * Install latest Submariner (master development)
  * Configure Service-Discovery
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

# XML output files for Junit test results
export SHELL_JUNIT_XML="$(basename "${0%.*}")_junit.xml"
export E2E_JUNIT_XML="$SCRIPT_DIR/subm_e2e_junit.xml"
export PKG_JUNIT_XML="$SCRIPT_DIR/subm_pkg_junit.xml"
export LIGHTHOUSE_JUNIT_XML="$SCRIPT_DIR/lighthouse_e2e_junit.xml"

# Common test variables
export NEW_NETSHOOT_CLUSTER_A="${NETSHOOT_CLUSTER_A}-new" # A NEW Netshoot pod on cluster A
export HEADLESS_TEST_NS="${TEST_NS}-headless" # Namespace for the HEADLESS $NGINX_CLUSTER_B service

### Store dynamic variable values in local files

# File to store test status
export TEST_STATUS_RC="$SCRIPT_DIR/test_status.out"
echo 1 > $TEST_STATUS_RC

# File to store OCP cluster A version
export CLUSTER_A_VERSION="$SCRIPT_DIR/cluster_a.ver"
> $CLUSTER_A_VERSION

# File to store OCP cluster B version
export CLUSTER_B_VERSION="$SCRIPT_DIR/cluster_b.ver"
> $CLUSTER_B_VERSION

# File to store SubCtl version
export SUBCTL_VERSION="$SCRIPT_DIR/subctl.ver"
> $SUBCTL_VERSION

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
  --install-subctl)
    get_subctl=YES
    shift ;;
  --install-subctl-devel)
    install_subctl_devel=YES
    shift ;;
  --build-operator) # [DEPRECATED]
    build_operator=YES
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
  --service-discovery)
    service_discovery=YES
    shift ;;
  --globalnet)
    globalnet=YES
    shift ;;
  --cable-driver)
    check_cli_args "$2"
    subm_cable_driver="$2" # libreswan / strongswan
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

    # User input: $reset_cluster_a - to destroy_aws_cluster_a AND create_aws_cluster_a
    while [[ ! "$reset_cluster_a" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to destroy & create AWS cluster A ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      reset_cluster_a=${input:-no}
    done

    # User input: $clean_cluster_a - to clean_aws_cluster_a
    if [[ "$reset_cluster_a" =~ ^(no|n)$ ]]; then
      while [[ ! "$clean_cluster_a" =~ ^(yes|no)$ ]]; do
        echo -e "\n${YELLOW}Do you want to clean AWS cluster A ? ${NO_COLOR}
        Enter \"yes\", or nothing to skip: "
        read -r input
        clean_cluster_a=${input:-no}
      done
    fi

    # User input: $reset_cluster_b - to destroy_osp_cluster_b AND create_osp_cluster_b
    while [[ ! "$reset_cluster_b" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to destroy & create OSP cluster B ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      reset_cluster_b=${input:-no}
    done

    # User input: $clean_cluster_b - to clean_osp_cluster_b
    if [[ "$reset_cluster_b" =~ ^(no|n)$ ]]; then
      while [[ ! "$clean_cluster_b" =~ ^(yes|no)$ ]]; do
        echo -e "\n${YELLOW}Do you want to clean OSP cluster B ? ${NO_COLOR}
        Enter \"yes\", or nothing to skip: "
        read -r input
        clean_cluster_b=${input:-no}
      done
    fi
  fi # End of skip_ocp_setup options

  # User input: $service_discovery - to deploy with --service-discovery
  while [[ ! "$service_discovery" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to install Service-Discovery (lighthouse) ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    service_discovery=${input:-no}
  done

  # User input: $globalnet - to deploy with --globalnet
  while [[ ! "$globalnet" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to install Global Net ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    globalnet=${input:-no}
  done

  # User input: $build_operator - to build_operator_latest # [DEPRECATED]
  # while [[ ! "$build_operator" =~ ^(yes|no)$ ]]; do
  #   echo -e "\n${YELLOW}Do you want to pull Submariner-Operator repository (\"master\" branch) and build subctl ? ${NO_COLOR}
  #   Enter \"yes\", or nothing to skip: "
  #   read -r input
  #   build_operator=${input:-no}
  # done

  # User input: $get_subctl - to download_subctl_latest_release
  while [[ ! "$get_subctl" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to get the latest release of SubCtl ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    get_subctl=${input:-no}
  done

  # User input: $install_subctl_devel - to download_subctl_latest_devel
  while [[ ! "$install_subctl_devel" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to get the latest development of SubCtl (Submariner-Operator \"master\" branch) ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    install_subctl_devel=${input:-no}
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
  while [[ ! "$skip_tests" =~ ^((sys|e2e|pkg|all)(,|$))+ ]]; do
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
build_operator=${build_operator:-NO} # [DEPRECATED]
build_go_tests=${build_go_tests:-NO}
get_subctl=${get_subctl:-NO}
install_subctl_devel=${install_subctl_devel:-NO}
destroy_cluster_a=${destroy_cluster_a:-NO}
create_cluster_a=${create_cluster_a:-NO}
reset_cluster_a=${reset_cluster_a:-NO}
clean_cluster_a=${clean_cluster_a:-NO}
destroy_cluster_b=${destroy_cluster_b:-NO}
create_cluster_b=${create_cluster_b:-NO}
reset_cluster_b=${reset_cluster_b:-NO}
clean_cluster_b=${clean_cluster_b:-NO}
service_discovery=${service_discovery:-NO}
globalnet=${globalnet:-NO}
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
    - destroy_aws_cluster_a: $destroy_cluster_a
    - create_aws_cluster_a: $create_cluster_a
    - reset_aws_cluster_a: $reset_cluster_a
    - clean_aws_cluster_a: $clean_cluster_a

    OSP cluster B (on-prem):
    - destroy_osp_cluster_b: $destroy_cluster_b
    - create_osp_cluster_b: $create_cluster_b
    - reset_osp_cluster_b: $reset_cluster_b
    - clean_osp_cluster_b: $clean_cluster_b
    "
  fi

  if [[ "$skip_install" =~ ^(y|yes)$ ]]; then
    echo -e "\n# Skipping deployment and preparations: $skip_install \n"
  else
    echo "### Will execute Submariner deployment and environment preparations:

    OCP and Submariner setup and test tools:
    - config_golang: $config_golang
    - config_aws_cli: $config_aws_cli
    - build_ocpup_tool_latest: $get_ocpup_tool
    - build_operator_latest: $build_operator # [DEPRECATED]
    - build_submariner_repos: $build_go_tests
    - download_subctl_latest_release: $get_subctl
    - download_subctl_latest_devel: $install_subctl_devel
    "

    echo -e "# Submariner deployment and environment setup for the tests:

    - test_kubeconfig_aws_cluster_a
    - test_kubeconfig_osp_cluster_b
    - install_subctl_command
    - install_netshoot_app_on_cluster_a
    - install_nginx_svc_on_cluster_b
    - test_basic_cluster_connectivity_before_submariner
    - test_clusters_disconnected_before_submariner
    - configure_aws_ports_for_submariner_broker (\"prep_for_subm.sh\")
    - label_gateway_on_broker_nodes_with_external_ip
    - label_first_gateway_cluster_b
    - install_broker_aws_cluster_a
    - join_submariner_cluster_a
    - join_submariner_cluster_b
    $([[ ! "$service_discovery" =~ ^(y|yes)$ ]] || echo "- test Service-Discovery")
    $([[ ! "$globalnet" =~ ^(y|yes)$ ]] || echo "- test globalnet") \
    "
  fi

  # TODO: Should add function to manipulate opetshift clusters yamls, to have overlapping CIDRs

  if [[ "$skip_tests" =~ ^((sys|all)(,|$))+ ]]; then
    echo -e "\n# Skipping high-level (system) tests: $skip_tests \n"
  else
  echo -e "\n### Will execute: High-level (System) tests of Submariner:

    - test_submariner_resources_cluster_a
    - test_submariner_resources_cluster_b
    - test_disaster_recovery_of_gateway_nodes
    - test_cable_driver_cluster_a
    - test_cable_driver_cluster_b
    - test_subctl_show_on_merged_kubeconfigs
    - test_ha_status_cluster_a
    - test_ha_status_cluster_b
    - test_submariner_connection_cluster_a
    - test_submariner_connection_cluster_b
    - test_globalnet_status_cluster_a: $globalnet
    - test_globalnet_status_cluster_b: $globalnet
    - export_nginx_default_namespace_cluster_b: $service_discovery
    - export_nginx_headless_namespace_cluster_b: $service_discovery
    - test_lighthouse_status_cluster_a: $service_discovery
    - test_lighthouse_status_cluster_b: $service_discovery
    - test_clusters_connected_by_service_ip
    - install_new_netshoot_cluster_a
    - install_nginx_headless_namespace_cluster_b
    - test_clusters_connected_overlapping_cidrs: $globalnet
    - test_new_netshoot_global_ip_cluster_a: $globalnet
    - test_nginx_headless_global_ip_cluster_b: $globalnet
    - test_clusters_connected_full_domain_name: $service_discovery
    - test_clusters_cannot_connect_short_service_name: $service_discovery
    - test_clusters_connected_headless_service_on_new_namespace: $service_discovery
    - test_clusters_cannot_connect_headless_short_service_name: $service_discovery
    "
  fi

  if [[ "$skip_tests" =~ ^((pkg|all)(,|$))+ ]]; then
    echo -e "\n# Skipping Submariner unit-tests: $skip_tests \n"
  else
    echo -e "\n### Will execute: Unit-tests (Ginkgo Packages) of Submariner:

    - test_submariner_packages
    "
  fi

  if [[ "$skip_tests" =~ ^((e2e|all)(,|$))+ ]]; then
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
    # If variable is not null / "key" / "secret" / "password"
    if ! [[ -z "$var_value" || "$var_name" =~ (key|secret|password) ]] ; then
      # Trim value (string), if it is longer than 500 char
      (( ${#var_value} < 500 )) || var_value="${var_value:0:500}..."
      # Print the value without non-ascii chars
      echo -e "$var_name = $var_value" | tr -dC '[:print:]\t\n'
    fi
  done

}


# ------------------------------------------

function setup_workspace() {
  PROMPT "Creating workspace, verifying GO-lang, and configuring AWS and Polarion access"
  # DONT trap_commands - Includes credentials, hide from output

  # Create WORKDIR and local BIN dir (if not yet exists)
  mkdir -p ${WORKDIR}
  mkdir -p $HOME/.local/bin

  # Add local BIN dir to PATH
  [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

  # # CD to main working directory
  # cd ${WORKDIR}

  # Installing GoLang with Anaconda if $config_golang = yes/y
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

  # Installing if $config_aws_cli = yes/y
  if [[ "$config_aws_cli" =~ ^(y|yes)$ ]] ; then
    PROMPT "Installing AWS-CLI, and setting Profile [$AWS_PROFILE_NAME] and Region [$AWS_REGION]"
    configure_aws_access \
    "${AWS_PROFILE_NAME}" "${AWS_REGION}" "${AWS_KEY}" "${AWS_SECRET}" "${WORKDIR}" "${GOBIN}"
  fi

  # Set Polarion credentials if $upload_to_polarion = yes/y
  if [[ "$upload_to_polarion" =~ ^(y|yes)$ ]] ; then
    local polauth=$(echo "${POLARION_USR}:${POLARION_PWD}" | base64 --wrap 0)
    echo "--header \"Authorization: Basic ${polauth}\"" > "$POLARION_AUTH"
  fi

  # Trim trailing and leading spaces from $TEST_NS
  TEST_NS="$(echo "$TEST_NS" | xargs)"

  # # CD to previous directory
  # cd -
}

# ------------------------------------------

function download_ocp_installer() {
### Download OCP installer ###
  PROMPT "Downloading OCP Installer $OCP_VERSION"
  # The nightly builds available at: https://openshift-release-artifacts.svc.ci.openshift.org/
  trap_commands;

  # Optional param: $1 => $OCP_VERSION (default = latest)
  ocp_major_version="$(echo "$1" | cut -s -d '.' -f 1)" # Get the major digit of OCP version
  ocp_major_version="${ocp_major_version:-4}" # if no major version was found (e.g. "latest"), the default OCP is 4
  OCP_VERSION="${1:-latest}"

  cd ${WORKDIR}

  BUG "OCP 4.4.8 failure on generate asset \"Platform Permissions Check\"" \
  "Run OCP Installer 4.4.6 instead" \
  "https://bugzilla.redhat.com/show_bug.cgi?id=1850099"

  ocp_url="https://mirror.openshift.com/pub/openshift-v${ocp_major_version}/clients/ocp/${OCP_VERSION}/"
  ocp_install_gz=$(curl $ocp_url | grep -Eoh "openshift-install-linux-.+\.tar\.gz" | cut -d '"' -f 1)
  oc_client_gz=$(curl $ocp_url | grep -Eoh "openshift-client-linux-.+\.tar\.gz" | cut -d '"' -f 1)

  [[ -n "$ocp_install_gz" && -n "$oc_client_gz" ]] || FATAL "Failed to retrieve OCP installer [$OCP_VERSION] from $ocp_url"

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
  trap_commands;

  verify_golang || FATAL "No Golang installation found. Try to run again with option '--config-golang'"

  # TODO: Need to fix ocpup alias

  cd ${WORKDIR}
  # rm -rf ocpup # We should not remove directory, as it may included previous install config files
  git clone https://github.com/dimaunx/ocpup || echo "# OCPUP directory already exists"
  cd ocpup

  # To cleanup GOLANG mod files:
    # go clean -cache -modcache -i -r

  #git fetch && git reset --hard && git clean -fdx && git checkout --theirs . && git pull
  git fetch && git reset --hard && git checkout --theirs . && git pull

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
  trap_commands;

  verify_golang || FATAL "No Golang installation found. Try to run again with option '--config-golang'"

  build_go_repo "https://github.com/submariner-io/submariner"

  build_go_repo "https://github.com/submariner-io/lighthouse"
}

# ------------------------------------------

function build_operator_latest() {  # [DEPRECATED]
### Building latest Submariner-Operator code and SubCTL tool ###
  PROMPT "Building latest Submariner-Operator code and SubCTL tool"
  trap_commands;

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
  git fetch && git reset --hard && git clean -fdx && git checkout --theirs . && git pull
  # git log --pretty=fuller

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
  wget -O - https://github.com/submariner-io/shipyard/archive/master.tar.gz | tar xz --strip=2 "shipyard-master/scripts/shared"
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

function download_subctl_latest_release() {
  ### Download SubCtl - Submariner installer - Latest RC release ###
    PROMPT "Testing \"getsubctl.sh\" to download and use latest SubCtl RC release"
    download_subctl_by_tag 'v[0-9]'
}

# ------------------------------------------

function download_subctl_latest_devel() {
  ### Download SubCtl - Submariner installer - Latest DEVEL release ###
    PROMPT "Testing \"getsubctl.sh\" to download and use latest SubCtl DEVEL (built from Submariner-Operator \"master\" branch)"
    download_subctl_by_tag "devel"
  }

# ------------------------------------------

function download_subctl_by_tag() {
  ### Download SubCtl - Submariner installer ###
    trap_commands;

    local subctl_tag="${1:-v[0-9]}" # If not specifying a tag, it will download latest version released
    local regex="tag/\K.*${subctl_tag}[^\"]*"
    local repo_url="https://github.com/submariner-io/submariner-operator"
    local repo_tag="`curl "$repo_url/tags/" | grep -Po -m 1 "$regex"`"

    cd ${WORKDIR}

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

    echo "# Copy subctl from user HOME bin into ${GOBIN}:"
    mkdir -p $GOBIN
    # cp -f ./subctl $GOBIN/
    /usr/bin/install "$HOME/.local/bin/subctl" $GOBIN/subctl

    echo "# Add user HOME bin to system PATH:"
    export PATH="$HOME/.local/bin:$PATH"

    echo "# Store SubCtl version in $SUBCTL_VERSION"
    subctl version > "$SUBCTL_VERSION"

}

# ------------------------------------------

function test_subctl_command() {
  trap_commands;
  # Get SubCTL version (from file $SUBCTL_VERSION)
  local subctl_version="$([[ ! -s "$SUBCTL_VERSION" ]] || cat "$SUBCTL_VERSION")"

  PROMPT "Verifying Submariner CLI tool ${subctl_version:+ ($subctl_version)}"

  [[ -x "$(command -v subctl)" ]] || FATAL "No SubCtl installation found. Try to run again with option '--install-subctl'"
  subctl version

  BUG "Subctl devel is tagged with old version v0.6.1_" \
  "Ignore issue" \
  "https://github.com/submariner-io/submariner/issues/870"

  subctl --help

}

# ------------------------------------------

function prepare_install_aws_cluster_a() {
### Prepare installation files for AWS cluster A (public) ###
  PROMPT "Preparing installation files for AWS cluster A (public)"
  trap_commands;
  # Using existing OCP install-config.yaml - make sure to have it in the workspace.

  cd ${WORKDIR}
  [[ -f openshift-install ]] || FATAL "OCP Installer is missing. Try to run again with option '--get-ocp-installer [latest / x.y.z]'"

  if [[ -d "$CLUSTER_A_DIR" ]] && [[ -n `ls -A "$CLUSTER_A_DIR"` ]] ; then
    FATAL "$CLUSTER_A_DIR directory contains previous deployment configuration. It should be initially removed."
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

  mkdir -p "${CLUSTER_A_DIR}"
  local ocp_install_yaml="${CLUSTER_A_DIR}/install-config.yaml"
  cp -f "${CLUSTER_A_YAML}" "$ocp_install_yaml"
  chmod 777 "$ocp_install_yaml"

  echo "# Update the OCP installer configuration (YAML) of AWS cluster A"

  change_yaml_key_value "$ocp_install_yaml" "region" "$AWS_REGION"

  # TODO: change more {keys : values} in $ocp_install_yaml, with external variables file

}

# ------------------------------------------

function create_aws_cluster_a() {
### Create AWS cluster A (public) with OCP installer ###
  PROMPT "Creating AWS cluster A (public) with OCP installer"
  trap_commands;

  # Run OCP installer with the user-cluster-a.yaml:
  cd ${CLUSTER_A_DIR}
  ../openshift-install create cluster --log-level debug

  # To tail all OpenShift Installer logs (in a new session):
    # find . -name "*.log" | xargs tail -f

  # Login to the new created cluster:
    # $ grep "Access the OpenShift web-console" -r . --include='*.log' -A 1
      # "Access the OpenShift web-console here: https://console-openshift-console.apps..."
      # "Login to the console with user: kubeadmin, password: ..."
}

# ------------------------------------------

function create_osp_cluster_b() {
### Create Openstack cluster B (on-prem) with OCPUP tool ###
  PROMPT "Creating Openstack cluster B (on-prem) with OCP-UP tool"
  trap_commands;

  cd "${OCPUP_DIR}"
  [[ -x "$(command -v ocpup)" ]] || FATAL "OCPUP tool is missing. Try to run again with option '--get-ocpup-tool'"

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

  ocpup  create clusters ${DEBUG_FLAG} --config "$ocpup_yml" &
  pid=$!
  tail --pid=$pid -f --retry .config/${ocpup_cluster_name}/.openshift_install.log &
  tail --pid=$pid -f /dev/null

  # To tail all OpenShift Installer logs (in a new session):
    # find . -name "*openshift_install.log" | xargs tail --pid=$pid -f # tail ocpup/.config/${ocpup_cluster_name}/.openshift_install.log

  # Login to the new created cluster:
  # $ grep "Access the OpenShift web-console" -r . --include='*.log' -A 1
    # "Access the OpenShift web-console here: https://console-openshift-console.apps..."
    # "Login to the console with user: kubeadmin, password: ..."
}

# ------------------------------------------

function test_kubeconfig_aws_cluster_a() {
# Check that AWS cluster A (public) is up and running

  # Get OCP cluster A version (from file $CLUSTER_A_VERSION)
  cl_a_version="$([[ ! -s "$CLUSTER_A_VERSION" ]] || cat "$CLUSTER_A_VERSION")"

  PROMPT "Testing status of AWS cluster A${cl_a_version:+ (OCP Version $cl_a_version)}"
  trap_commands;

  kubconf_a;
  test_cluster_status
  cl_a_version=$(${OC} version | awk '/Server Version/ { print $3 }')
  echo "$cl_a_version" > "$CLUSTER_A_VERSION"

  # ${OC} set env dc/dcname TZ=Asia/Jerusalem
}

function kubconf_a() {
# Alias of KubeConfig for AWS cluster A (public) (AWS):
  trap_commands;
  export "KUBECONFIG=${KUBECONF_CLUSTER_A}";
}

# ------------------------------------------

function test_kubeconfig_osp_cluster_b() {
# Check that OSP cluster B (on-prem) is up and running

  # Get OCP cluster B version (from file $CLUSTER_B_VERSION)
  cl_b_version="$([[ ! -s "$CLUSTER_B_VERSION" ]] || cat "$CLUSTER_B_VERSION")"

  PROMPT "Testing status of OSP cluster B${cl_b_version:+ (OCP Version $cl_b_version)}"
  trap_commands;

  kubconf_b;
  test_cluster_status
  cl_b_version=$(${OC} version | awk '/Server Version/ { print $3 }')
  echo "$cl_b_version" > "$CLUSTER_B_VERSION"

  # ${OC} set env dc/dcname TZ=Asia/Jerusalem
}

function kubconf_b() {
# Alias of KubeConfig for OSP cluster B (on-prem) (OpenStack):
  trap_commands;
  export "KUBECONFIG=${KUBECONF_CLUSTER_B}";
}

# ------------------------------------------

function test_cluster_status() {
  # Verify that current kubeconfig cluster is up and healthy
  trap_commands;

  [[ -f ${KUBECONFIG} ]] || FATAL "Openshift deployment configuration is missing: ${KUBECONFIG}"

  # Set the default namespace to "${TEST_NS}" (if TEST_NS parameter was previously set)
  if [[ $TEST_NS ]] ; then
    echo "# Backup current KUBECONFIG to: ${KUBECONFIG}.bak"
    cp -f "${KUBECONFIG}" "${KUBECONFIG}.bak"

    BUG "On OCP version < 4.4.6 : If running inside different cluster, OC can use wrong project name by default" \
    "Set the default namespace to \"${TEST_NS}\"" \
    "https://bugzilla.redhat.com/show_bug.cgi?id=1826676"

    echo "# Create namespace for Submariner tests: ${TEST_NS}"
    ${OC} create namespace "${TEST_NS}" || : # Ignore none-zero exit code (if namespace already exists

    echo "# Change the default namespace in [${KUBECONFIG}] to: ${TEST_NS}"
    cur_context="$(${OC} config current-context)"
    ${OC} config set "contexts.${cur_context}.namespace" "${TEST_NS}"
  else
    export TEST_NS=default
  fi

  ${OC} config view
  ${OC} status || FATAL "Openshift cluster is not installed, or not accessible with: ${KUBECONFIG}"
  ${OC} version
  ${OC} get all
    # NAME                 TYPE           CLUSTER-IP   EXTERNAL-IP                            PORT(S)   AGE
    # service/kubernetes   clusterIP      172.30.0.1   <none>                                 443/TCP   39m
    # service/openshift    ExternalName   <none>       kubernetes.default.svc.cluster.local   <none>    32m
}

# ------------------------------------------

function destroy_aws_cluster_a() {
### Destroy your previous AWS cluster A (public) ###
  PROMPT "Destroying previous AWS cluster A (public)"
  trap_commands;
  # Temp - CD to main working directory
  cd ${WORKDIR}

  aws --version || FATAL "AWS-CLI is missing. Try to run again with option '--config-aws-cli'"

  # Only if your AWS cluster still exists (less than 48 hours passed) - run destroy command:
  # TODO: should first check if it was not already purged, because it can save a lot of time.
  if [[ -d "${CLUSTER_A_DIR}" ]]; then
    echo "# Previous OCP Installation found: ${CLUSTER_A_DIR}"
    # cd "${CLUSTER_A_DIR}"
    if [[ -f "${CLUSTER_A_DIR}/metadata.json" ]] ; then
      echo "# Destroying OCP cluster ${CLUSTER_A_NAME}:"
      timeout 10m ./openshift-install destroy cluster --log-level debug --dir "${CLUSTER_A_DIR}" || \
      ( [[ $? -eq 124 ]] && \
      BUG "WARNING: OCP destroy timeout exceeded - loop state while destroying cluster" \
      "Force exist OCP destroy process" \
      "Please submit a new bug for OCP installer (in Bugzilla)" )
    fi
    # cd ..

    echo "# Backup previous OCP install-config directory of cluster ${CLUSTER_A_NAME}"
    parent_dir=$(dirname -- "$CLUSTER_A_DIR")
    base_dir=$(basename -- "$CLUSTER_A_DIR")
    backup_and_remove_dir "$CLUSTER_A_DIR" "${parent_dir}/_${base_dir}_${DATE_TIME}"

    # Remove existing OCP install-config directory:
    #rm -r "_${CLUSTER_A_DIR}/" || echo "# Old config dir removed."
    echo "# Deleting all previous ${CLUSTER_A_DIR} config directories (older than 1 day):"
    # find -type d -maxdepth 1 -name "_*" -mtime +1 -exec rm -rf {} \;
    delete_old_files_or_dirs "${parent_dir}/_${base_dir}_*" "d" 1
  else
    echo "# OCP cluster config (metadata.json) was not found in ${CLUSTER_A_DIR}. Skipping cluster Destroy."
  fi

  BUG "WARNING: OCP destroy command does not remove the previous DNS record sets from AWS Route53" \
  "Delete previous DNS record sets from AWS Route53" \
  "---"
  # Workaround:

  # set AWS DNS record sets to be deleted
  AWS_DNS_ALIAS1="api.${CLUSTER_A_NAME}.${AWS_ZONE_NAME}."
  AWS_DNS_ALIAS2="\052.apps.${CLUSTER_A_NAME}.${AWS_ZONE_NAME}."

  echo -e "# Deleting AWS DNS record sets from Route53:
  # $AWS_DNS_ALIAS1
  # $AWS_DNS_ALIAS2
  "

  # curl -LO https://github.com/manosnoam/shift-stack-helpers/raw/master/delete_aws_dns_alias_zones.sh
  # chmod +x delete_aws_dns_alias_zones.sh
  # ./delete_aws_dns_alias_zones.sh "${CLUSTER_A_NAME}"
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

function destroy_osp_cluster_b() {
### If Required - Destroy your previous Openstack cluster B (on-prem) ###
  PROMPT "Destroying previous Openstack cluster B (on-prem)"
  trap_commands;

  cd "${OCPUP_DIR}"
  [[ -x "$(command -v ocpup)" ]] || FATAL "OCPUP tool is missing. Try to run again with option '--get-ocpup-tool'"

  if [[ -f "${CLUSTER_B_DIR}/metadata.json" ]] ; then
    echo -e "# Using an existing OCPUP yaml configuration file: \n${CLUSTER_B_YAML}"
    cp -f "${CLUSTER_B_YAML}" ./ || FATAL "OCPUP yaml configuration file is missing."

    ocpup_yml=$(basename -- "$CLUSTER_B_YAML")
    ls -l "$ocpup_yml"

    local ocpup_cluster_name="$(awk '/clusterName:/ {print $NF}' $ocpup_yml)"

    ocpup  destroy clusters ${DEBUG_FLAG} --config "$ocpup_yml" & # running on the background (with timeout)
    pid=$! # while the background process runs, tail its log
    # tail --pid=$pid -f .config/${ocpup_cluster_name}/.openshift_install.log && tail -f /proc/$pid/fd/1

    # Wait until the background process finish
    #tail --pid=$pid -f --retry ${OCPUP_DIR}/.config/${ocpup_cluster_name}/.openshift_install.log &
    #tail --pid=$pid -f /dev/null # wait until the background process finish

    timeout --foreground 20m tail --pid=$pid -f --retry "${OCPUP_DIR}/.config/${ocpup_cluster_name}/.openshift_install.log"

    # To tail all OpenShift Installer logs (in a new session):
      # find . -name "*openshift_install.log" | xargs tail --pid=$pid -f # tail ocpup/.config/${ocpup_cluster_name}/.openshift_install.log

    echo "# Backup previous OCP install-config directory of cluster ${CLUSTER_B_NAME} "
    backup_and_remove_dir ".config"
  else
    echo "# OCP cluster config (metadata.json) was not found in ${CLUSTER_B_DIR}. Skipping cluster Destroy."
  fi
}


# ------------------------------------------

function clean_aws_cluster_a() {
### Run cleanup of previous Submariner on AWS cluster A (public) ###
  PROMPT "Cleaning previous Submariner (Namespaces, OLM, CRDs, ServiceExports) on AWS cluster A (public)"
  trap_commands;
  kubconf_a;

  BUG "Deploying broker will fail if previous submariner-operator namespaces and CRDs already exist" \
  "Run cleanup (oc delete) of any existing resource of submariner-operator" \
  "https://github.com/submariner-io/submariner-operator/issues/88
  https://github.com/submariner-io/submariner-website/issues/272"

  delete_submariner_namespace_and_crds;
  delete_e2e_namespaces

  PROMPT "Remove previous Submariner Gateway Node's Labels and MachineSets from AWS cluster A (public)"

  # BUG "Curl between pod to service on same cluster can fail, if Submariner (with globalnet) was previously installed" \
  # "Remove iptables rules from each gateway node" \
  # "https://github.com/submariner-io/submariner/issues/929"
  # # Workaround:
  # remove_submariner_iptables_from_gw_nodes

  remove_submariner_gateway_labels
  remove_submariner_machine_sets

  # Todo: Should also include globalnet network cleanup:
  #
  # 1 If you are using vanilla Submariner, please delete the following iptable chains from the nat/filter table of worker nodes
  #   SUBMARINER-INPUT
  #   SUBMARINER-POSTROUTING
  #
  # 2 The following chains will have to be deleted if you are using Globalnet:
  #   SUBMARINER-GN-INGRESS
  #   SUBMARINER-GN-EGRESS
  #   SUBMARINER-GN-MARK
  #
  # 3 its recommended that you delete the vx-submariner interface from all the nodes.

}

# ------------------------------------------

function clean_osp_cluster_b() {
### Run cleanup of previous Submariner on OSP cluster B (on-prem) ###
  PROMPT "Cleaning previous Submariner (Namespaces, OLM, CRDs, ServiceExports) on OSP cluster B (on-prem)"
  trap_commands;

  kubconf_b;
  delete_submariner_namespace_and_crds;

  BUG "Low disk-space on OCP cluster that was running for few weeks" \
  "Delete old E2E namespaces" \
  "https://github.com/submariner-io/submariner-website/issues/341
  https://github.com/submariner-io/shipyard/issues/355"

  delete_e2e_namespaces

  PROMPT "Remove previous Submariner Gateway Node's Labels and MachineSets from OSP cluster B (on-prem)"

  # BUG "Curl between pod to service on same cluster can fail, if Submariner (with globalnet) was previously installed" \
  # "Remove iptables rules from each gateway node" \
  # "https://github.com/submariner-io/submariner/issues/929"
  # # Workaround:
  # remove_submariner_iptables_from_gw_nodes

  remove_submariner_gateway_labels

  BUG "Submariner-gw machine failure: Configuration not supported" \
  "No Workaround yet..." \
  "https://github.com/submariner-io/submariner/issues/885"

  remove_submariner_machine_sets
}

# ------------------------------------------

function delete_submariner_namespace_and_crds() {
### Run cleanup of previous Submariner on current KUBECONFIG cluster ###
  trap_commands;

  delete_namespace_and_crds "${SUBM_NAMESPACE}" "submariner"

  # Required if Broker cluster is not a Dataplane cluster as well:
  delete_namespace_and_crds "${BROKER_NAMESPACE}"

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

function delete_e2e_namespaces() {
### Delete previous Submariner E2E namespaces from current cluster ###
  trap_commands;

  local e2e_namespaces="$(oc get ns -o=custom-columns=NAME:.metadata.name | grep e2e-tests)"

  echo "# Deleting all 'e2e-tests' namespaces: $e2e_namespaces"

  oc delete --timeout=30s ns $e2e_namespaces || echo "All 'e2e-tests' namespaces already deleted"

}

# ------------------------------------------

function remove_submariner_gateway_labels() {
  trap_commands;

  echo "# Remove previous submariner gateway labels from all node in the cluster:"

  ${OC} label --all node submariner.io/gateway-
}

# ------------------------------------------

function remove_submariner_machine_sets() {
  trap_commands;

  echo "# Remove previous machineset (if it has a template with submariner gateway label)"

  local subm_machineset="`${OC} get machineset -A -o jsonpath='{.items[?(@.spec.template.spec.metadata.labels.submariner\.io\gateway=="true")].metadata.name}' `"
  local ns="`${OC} get machineset -A -o jsonpath='{.items[?(@.spec.template.spec.metadata.labels.submariner\.io\gateway=="true")].metadata.namespace}'`"

  if [[ -n "$subm_machineset" && -n "$ns" ]] ; then
    ${OC} delete machineset $subm_machineset -n $ns || :
  fi

  ${OC} get machineset -A -o wide
}

# ------------------------------------------

function remove_submariner_iptables_from_gw_nodes() {
  trap_commands;

  ${OC} get nodes -l "submariner.io/gateway=true" | awk 'NR>1 {print $1}' | \
  while read node_name; do

    local pod_name="remove-iptables-${node_name%%.*}"
    echo "# Delete GlobalNet iptables from node $node_name (via Netshoot pod $node_name)"
    # ${OC} run netshoot-hostmount-$(uuidgen) ${TEST_NS:+-n $TEST_NS} --image nicolaka/netshoot --generator=run-pod/v1 --overrides='{

    ${OC} run $pod_name ${TEST_NS:+-n $TEST_NS} --image nicolaka/netshoot --attach=true --rm -i \
    --restart=Never --pod-running-timeout=1m --request-timeout=1m --overrides='{
    	"spec": {
    		"hostNetwork": true,
    		"nodeName": "'$node_name'",
    		"containers": [{
    			"args": [
    				"/bin/bash", "-c",
    			       	"iptables -t nat -F SUBMARINER-GN-EGRESS; iptables -t nat -F SUBMARINER-GN-INGRESS; iptables -t nat -F SUBMARINER-GN-MARK;"
    			],
    			"stdin": true,
    			"stdinOnce": true,
    			"terminationMessagePath": "/dev/termination-log",
    			"terminationMessagePolicy": "File",
    			"tty": true,
    			"securityContext": {
    				"allowPrivilegeEscalation": true,
    				"privileged": true,
    				"runAsUser": 0,
    				"capabilities": {
    					"add": ["ALL"]
    				}
    			},
    			"name": "'$pod_name'",
    			"image": "nicolaka/netshoot",
    			"volumeMounts": [{
    				"mountPath": "/host",
    				"name": "host-slash",
    				"readOnly": true
    			}]
    		}],
    	  "restartPolicy": "Never",
    		"volumes": [{
    			"hostPath": {
    				"path": "/",
    				"type": ""
    			},
    		"name": "host-slash"
    		}]
    	}
    }' -- /bin/bash

  done

}

# ------------------------------------------

function install_netshoot_app_on_cluster_a() {
  PROMPT "Install Netshoot application on AWS cluster A (public)"
  trap_commands;

  kubconf_a;

  ${OC} delete pod ${NETSHOOT_CLUSTER_A}  --ignore-not-found ${TEST_NS:+-n $TEST_NS} || :

  if [[ -n $TEST_NS ]] ; then
    # ${OC} delete --timeout=30s namespace "${TEST_NS}" --ignore-not-found || : # || : to ignore none-zero exit code
    delete_namespace_and_crds "${TEST_NS}"
    ${OC} create namespace "${TEST_NS}" || : # || : to ignore none-zero exit code
  fi

  # NETSHOOT_CLUSTER_A=netshoot-cl-a # Already exported in global subm_variables

  # Deployment is terminated after netshoot is loaded - need to "oc run" with infinite loop
  # ${OC} delete deployment ${NETSHOOT_CLUSTER_A}  --ignore-not-found ${TEST_NS:+-n $TEST_NS}
  # ${OC} create deployment ${NETSHOOT_CLUSTER_A}  --image nicolaka/netshoot ${TEST_NS:+-n $TEST_NS}
  ${OC} run ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --image nicolaka/netshoot -- sleep infinity

  echo "# Wait up to 3 minutes for Netshoot pod [${NETSHOOT_CLUSTER_A}] to be ready:"
  ${OC} wait --timeout=3m --for=condition=ready pod -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
  ${OC} describe pod  ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
}

# ------------------------------------------

function install_nginx_svc_on_cluster_b() {
  PROMPT "Install Nginx service on OSP cluster B${TEST_NS:+ (Namespace $TEST_NS)}"
  trap_commands;

  kubconf_b;

  install_nginx_service "${NGINX_CLUSTER_B}" "${TEST_NS}" "--port=8080"
}

# ------------------------------------------

function test_basic_cluster_connectivity_before_submariner() {
### Pre-test - Demonstrate that the clusters aren’t connected without Submariner ###
  PROMPT "Before Submariner is installed: Verifying IP connectivity on the SAME cluster"
  trap_commands;

  # Trying to connect from cluster A to cluster B, will fails (after 5 seconds).
  # It’s also worth looking at the clusters to see that Submariner is nowhere to be seen.

  kubconf_b;
  echo -e "\n# Get IP of ${NGINX_CLUSTER_B} on OSP cluster B${TEST_NS:+(Namespace: $TEST_NS)} to verify connectivity:\n"

  ${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS}
  nginx_IP_cluster_b=$(${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')
    # nginx_cluster_b_ip: 100.96.43.129

  local netshoot_pod=netshoot-cl-b-new # A new Netshoot pod on cluster b
  echo "# Install $netshoot_pod on OSP cluster B, and verify connectivity on the SAME cluster, to $nginx_IP_cluster_b:8080"

  ${OC} delete pod ${netshoot_pod} --ignore-not-found ${TEST_NS:+-n $TEST_NS} || :

  ${OC} run ${netshoot_pod} --attach=true --restart=Never --pod-running-timeout=2m --request-timeout=2m --rm -i \
  ${TEST_NS:+-n $TEST_NS} --image nicolaka/netshoot -- /bin/bash -c "curl --max-time 60 --verbose ${nginx_IP_cluster_b}:8080"
}

# ------------------------------------------

function test_clusters_disconnected_before_submariner() {
### Pre-test - Demonstrate that the clusters aren’t connected without Submariner ###
  PROMPT "Before Submariner is installed:
  Verifying that Netshoot pod on AWS cluster A (public), cannot reach Nginx service on OSP cluster B (on-prem)"
  trap_commands;

  # Trying to connect from cluster A to cluster B, will fails (after 5 seconds).
  # It’s also worth looking at the clusters to see that Submariner is nowhere to be seen.

  kubconf_b;
  # nginx_IP_cluster_b=$(${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')
  ${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}' > "$TEMP_FILE"
  nginx_IP_cluster_b="$(< $TEMP_FILE)"
    # nginx_cluster_b_ip: 100.96.43.129

  kubconf_a;
  # ${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --field-selector status.phase=Running | awk 'FNR == 2 {print $1}' > "$TEMP_FILE"
  # netshoot_pod_cluster_a="$(< $TEMP_FILE)"
  netshoot_pod_cluster_a="`get_running_pod_by_label "run=${NETSHOOT_CLUSTER_A}" $TEST_NS `"

  msg="# Negative Test - Clusters should NOT be able to connect without Submariner."

  ${OC} exec $netshoot_pod_cluster_a ${TEST_NS:+-n $TEST_NS} -- \
  curl --output /dev/null --max-time 20 --verbose $nginx_IP_cluster_b:8080 \
  |& (! highlight "command terminated with exit code" && FATAL "$msg") || echo -e "$msg"
    # command terminated with exit code 28
}

# ------------------------------------------

function open_firewall_ports_on_the_broker_node() {
### Open AWS Firewall ports on the gateway node with terraform (prep_for_subm.sh) ###
  # Readme: https://github.com/submariner-io/submariner/tree/master/tools/openshift/ocp-ipi-aws
  PROMPT "Running \"prep_for_subm.sh\" - to open Firewall ports on the Broker node in AWS cluster A (public)"
  trap_commands;

  # # Installing Terraform
  # install_local_terraform "${WORKDIR}"

  BUG "Terraform v0.13.x is not supported when using prep_for_subm.sh" \
  "Use Terraform v0.12.29" \
  "https://github.com/submariner-io/submariner/issues/847"
  # Workaround:
  install_local_terraform "${WORKDIR}" "0.12.29"

  local git_user="submariner-io"
  local git_project="submariner"
  local commit_or_branch=master # "7ffe6146081d5a7f14ea103e5f290411d3746a4a" # "master" #
  local prep_for_subm_dir="tools/openshift/ocp-ipi-aws"

  download_github_file_or_dir "$git_user" "$git_project" "$commit_or_branch" "$prep_for_subm_dir"

  # cd "$prep_for_subm_dir"
  BUG "'prep_for_subm.sh' ignores local yamls and always download from master" \
  "Copy 'ocp-ipi-aws' directory (including 'prep_for_subm.sh') into 'submariner_prep' under OCP install dir" \
  "https://github.com/submariner-io/submariner/issues/880"
  # Workaround:

  echo "# Copy 'ocp-ipi-aws' directory (including 'prep_for_subm.sh') to $CLUSTER_A_DIR/submariner_prep"
  cp -rf "$prep_for_subm_dir" "$CLUSTER_A_DIR/submariner_prep"
  cd "$CLUSTER_A_DIR/submariner_prep/"

  sed -r 's/0\.12\.12/0\.12\.29/g' -i versions.tf

  kubconf_a;

  export IPSEC_NATT_PORT=${IPSEC_NATT_PORT:-4501}
  export IPSEC_IKE_PORT=${IPSEC_IKE_PORT:-501}
  export GW_INSTANCE_TYPE=${GW_INSTANCE_TYPE:-m4.xlarge}

  # bash -x ./prep_for_subm.sh "${CLUSTER_A_DIR}" -auto-approve
  echo "# Running 'prep_for_subm.sh ${CLUSTER_A_DIR} -auto-approve' script to apply Terraform 'ec2-resources.tf'"
  BUG "Duplicate security group rule was found, when applying Terraform ec2-resources.tf more than once" \
  "No workaround yet (it will probably fail later when searching External-IP)" \
  "https://github.com/submariner-io/submariner/issues/849"
  # Workaound:
  bash -x ./prep_for_subm.sh "${CLUSTER_A_DIR}" -auto-approve || :

  # Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
  #
  # Outputs:
  #
  # machine_set_config_file = ~/automation/ocp-install/user-cluster-a/ocp-ipi-aws/submariner-gw-machine-set-us-east-1e.yaml
  # submariner_security_group = user-cluster-a-8scqd-submariner-gw-sg
  # target_public_subnet = subnet-016d75737faa4b219
  #
  # Applying machineset changes to deploy gateway node:
  # oc --context=admin apply -f submariner-gw-machine-set-us-east-1e.yaml
  # machineset.machine.openshift.io/user-cluster-a-8scqd-submariner-gw-us-east-1e created

}

# ------------------------------------------

function label_gateway_on_broker_nodes_with_external_ip() {
### Label a Gateway node on AWS cluster A (public) ###
  PROMPT "Adding Gateway label to all worker nodes with an External-IP on AWS cluster A (public)"
  trap_commands;

  BUG "If one of the gateway nodes does not have External-IP, submariner will fail to connect later" \
  "Make sure one node with External-IP has a gateway label" \
  "https://github.com/submariner-io/submariner-operator/issues/253"

  kubconf_a;
  # TODO: Check that the Gateway label was created with "prep_for_subm.sh" on AWS cluster A (public) ?
  gateway_label_all_nodes_external_ip
}

function label_first_gateway_cluster_b() {
### Label a Gateway node on OSP cluster B (on-prem) ###
  PROMPT "Adding Gateway label to the first worker node on OSP cluster B (on-prem)"
  trap_commands;

  kubconf_b;
  gateway_label_first_worker_node
}

function gateway_label_first_worker_node() {
### Adding submariner gateway label to the first worker node ###
  trap_commands;

  # gw_node1=$(${OC} get nodes -l node-role.kubernetes.io/worker | awk 'FNR == 2 {print $1}')
  ${OC} get nodes -l node-role.kubernetes.io/worker | awk 'FNR == 2 {print $1}' > "$TEMP_FILE"
  gw_node1="$(< $TEMP_FILE)"
  echo "# Adding submariner gateway labels to first worker node: $gw_node1"
    # gw_node1: user-cl1-bbmkg-worker-8mx4k

  # TODO: Run only If there's no Gateway label already:
  ${OC} label node $gw_node1 "submariner.io/gateway=true" --overwrite
    # node/user-cl1-bbmkg-worker-8mx4k labeled

  # ${OC} get nodes -l "submariner.io/gateway=true" |& highlight "Ready"
      # NAME                          STATUS   ROLES    AGE     VERSION
      # ip-10-0-89-164.ec2.internal   Ready    worker   5h14m   v1.14.6+c07e432da
  ${OC} wait --timeout=3m --for=condition=ready nodes -l submariner.io/gateway=true || :
  ${OC} get nodes -l submariner.io/gateway=true
}

function gateway_label_all_nodes_external_ip() {
### Adding submariner gateway label to all worker nodes with an External-IP ###
  trap_commands;

  # Filter all node names that have External-IP (column 7 is not none), and ignore header fields
  # Run 200 attempts, and wait for output to include regex of IPv4
  watch_and_retry "${OC} get nodes -l node-role.kubernetes.io/worker -o wide | awk '{print \$7}'" \
  200 '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || external_ips=NONE

  if [[ "$external_ips" = NONE ]] ; then
    failed_machines=$(oc get Machine -A -o jsonpath='{.items[?(@.status.phase!="Running")].metadata.name}')
    FATAL "EXTERNAL-IP was not created yet (by \"prep_for_subm.sh\" script).
    ${failed_machines:+ Failed Machines: \n$failed_machines}"
  fi

  # [[ -n "$gw_nodes" ]] || FATAL "External-IP was not created yet (by \"prep_for_subm.sh\" script)."

  gw_nodes=$(${OC} get nodes -l node-role.kubernetes.io/worker -o wide | awk '$7!="<none>" && NR>1 {print $1}')
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
  ${OC} wait --timeout=3m --for=condition=ready nodes -l submariner.io/gateway=true || :
  ${OC} get nodes -l submariner.io/gateway=true
}

# ------------------------------------------

function install_broker_aws_cluster_a() {
### Installing Submariner Broker on AWS cluster A (public) ###
  # TODO - Should test broker deployment also on different Public cluster (C), rather than on Public cluster A.
  # TODO: Call kubeconfig of broker cluster
  trap_commands;

  DEPLOY_CMD="subctl deploy-broker "

  if [[ "$service_discovery" =~ ^(y|yes)$ ]]; then
    PROMPT "Adding Service-Discovery to Submariner Deploy command"

    BUG "kubecontext must be identical to broker-cluster-context, otherwise kubefedctl will fail" \
    "Modify KUBECONFIG context name on the public cluster for the broker, and use the same name for kubecontext and broker-cluster-context" \
    "https://github.com/submariner-io/submariner-operator/issues/193"
    sed -z "s#name: [a-zA-Z0-9-]*\ncurrent-context: [a-zA-Z0-9-]*#name: ${CLUSTER_A_NAME}\ncurrent-context: ${CLUSTER_A_NAME}#" -i.bak ${KUBECONF_CLUSTER_A}

    DEPLOY_CMD="${DEPLOY_CMD} --service-discovery --kubecontext ${CLUSTER_A_NAME}"
    # subctl deploy-broker --kubecontext <BROKER-CONTEXT-NAME>  --kubeconfig <MERGED-KUBECONFIG> \
    # --dataplane --service-discovery --broker-cluster-context <BROKER-CONTEXT-NAME> --clusterid  <CLUSTER-ID-FOR-TUNNELS>
  fi

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
  kubconf_a;

  cd ${WORKDIR}
  #cd $GOPATH/src/github.com/submariner-io/submariner-operator

  echo "# Remove previous broker-info.subm (if exists)"
  rm broker-info.subm.* || echo "# Previous ${BROKER_INFO} already removed"

  echo "# Executing deploy command: ${DEPLOY_CMD}"
  $DEPLOY_CMD
}

# ------------------------------------------

function test_broker_before_join() {
  PROMPT "Verify Submariner CRDs created, but no pods were yet created"
  trap_commands;

  export KUBECONFIG="${KUBECONF_BROKER}"

  # Now looking at Broker cluster, it should show that CRDs, but no pods in namespace
  ${OC} get crds | grep 'submariner.io'

  ${OC} describe crds \
  clusters.submariner.io \
  endpoints.submariner.io \
  serviceimports.multicluster.x-k8s.io || :

  # serviceexports.lighthouse.submariner.io \
  # servicediscoveries.submariner.io \
  # submariners.submariner.io \
  # gateways.submariner.io \

  if [[ ! "$skip_ocp_setup" =~ ^(y|yes)$ ]]; then
    ${OC} get pods -n ${SUBM_NAMESPACE} --show-labels |& highlight "No resources found" \
     || FATAL "Submariner Broker (deploy before join) should not create resources in namespace ${SUBM_NAMESPACE}."
  fi
}

# ------------------------------------------

function export_nginx_default_namespace_cluster_b() {
  PROMPT "Create ServiceExport for $NGINX_CLUSTER_B on OSP cluster B, without specifying Namespace"
  trap_commands;

  kubconf_b;

  echo -e "# The ServiceExport should be created on the default Namespace, as configured in KUBECONFIG:
  \n# $KUBECONF_CLUSTER_B : ${TEST_NS:-default}"

  export_service_in_lighthouse "$NGINX_CLUSTER_B"
}

# ------------------------------------------

function export_nginx_headless_namespace_cluster_b() {
  PROMPT "Create ServiceExport for the HEADLESS $NGINX_CLUSTER_B on OSP cluster B, in the Namespace '$HEADLESS_TEST_NS'"
  trap_commands;

  kubconf_b;

  echo "# The ServiceExport should be created on the default Namespace, as configured in KUBECONFIG:
  \n# $KUBECONF_CLUSTER_B : ${HEADLESS_TEST_NS}"

  export_service_in_lighthouse "$NGINX_CLUSTER_B" "$HEADLESS_TEST_NS"
}

# ------------------------------------------

function export_service_in_lighthouse() {
  trap_commands;
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

  # ${OC} rollout status serviceexport "${svc_name}" ${namespace:+ -n $namespace}
  # ${OC} wait --timeout=3m --for=condition=ready serviceexport "${svc_name}" ${namespace:+ -n $namespace}
  BUG "Rollout status failed: ServiceExport is not a registered version" \
  "Skip checking for ServiceExport creation status" \
  "https://github.com/submariner-io/submariner/issues/640"
  # Workaround:
  # Do not run this rollout status, but watch pod description:
  local cmd="${OC} describe serviceexport $svc_name ${namespace:+-n $namespace}"
  #local regex='Service was successfully synced to the broker'
  local regex='Type:\s+Exported'
  watch_and_retry "$cmd" 3m "$regex"

  echo "# Show $svc_name ServiceExport information:"
  ${OC} get serviceexport "${svc_name}" ${namespace:+ -n $namespace} -o wide

  BUG "kubectl get serviceexport with '-o wide' does not show more info" \
  "Use '-o yaml' instead" \
  "https://github.com/submariner-io/submariner/issues/739"
  # Workaround:
  ${OC} get serviceexport "${svc_name}" ${namespace:+ -n $namespace} -o yaml

  echo -e "\n# Describe Lighthouse Exported Services:\n"
  ${OC} describe serviceexports --all-namespaces

}

# ------------------------------------------

function join_submariner_cluster_a() {
# Join Submariner member - AWS cluster A (public)
  PROMPT "Joining cluster A to Submariner Broker (also on cluster A)"
  trap_commands;

  kubconf_a;
  join_submariner_current_cluster "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function join_submariner_cluster_b() {
# Join Submariner member - OSP cluster B (on-prem)
  PROMPT "Joining cluster B to Submariner Broker (on cluster A)"
  trap_commands;

  kubconf_b;
  join_submariner_current_cluster "${CLUSTER_B_NAME}"

}

# ------------------------------------------

function join_submariner_current_cluster() {
# Join Submariner member - of current cluster kubeconfig
  trap_commands;
  local cluster_name="$1"

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

  # BUG "Generate a cluster id if one is not provided" \
  # "Pass '--clusterid ${current_cluster_context_name}' to subctl join command" \
  # "https://github.com/submariner-io/submariner-operator/issues/539"

  # JOIN_CMD="subctl join --clusterid ${current_cluster_context_name} \
  JOIN_CMD="subctl join \
  ./${BROKER_INFO} ${subm_cable_driver:+--cable-driver $subm_cable_driver} \
  --ikeport ${IPSEC_IKE_PORT} --nattport ${IPSEC_NATT_PORT}"

  if [[ "$install_subctl_devel" =~ ^(y|yes)$ ]]; then
      BUG "operator image 'devel' should be the default when using subctl devel binary" \
      "Add '--version devel' to JOIN_CMD" \
      "https://github.com/submariner-io/submariner-operator/issues/563"
      # Workaround
      JOIN_CMD="${JOIN_CMD} --version devel"
  fi

  echo "# Adding '--enable-pod-debugging' and '--ipsec-debug' to the ${JOIN_CMD} for tractability"
  JOIN_CMD="${JOIN_CMD} --enable-pod-debugging --ipsec-debug"

  echo "# Executing join command on cluster $cluster_name: ${JOIN_CMD}"
  $JOIN_CMD

}

# ------------------------------------------

function test_products_versions() {
# Show OCP clusters versions, and Submariner version
  trap_commands;

  PROMPT "Show all installed products versions"

  echo "Submariner:"
  subctl version

  echo -e "\nOCP cluster A (AWS):"
  kubconf_a;
  ${OC} version

  echo -e "\nOCP cluster B (OSP):"
  kubconf_b;
  ${OC} version

}

# ------------------------------------------

function test_submariner_resources_cluster_a() {
  trap_commands;

  kubconf_a;
  test_submariner_resources_status "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_submariner_resources_cluster_b() {
  trap_commands;

  kubconf_b;
  test_submariner_resources_status "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_submariner_resources_status() {
# Check submariner-engine on the Operator pod
  trap_commands;
  local cluster_name="$1"
  local submariner_status=UP

  PROMPT "Testing that Submariner CRDs and resources were created on cluster ${cluster_name}"
  ${OC} get crds | grep submariners || submariner_status=DOWN
      # ...
      # submariners.submariner.io                                   2019-11-28T14:09:56Z

  ${OC} get namespace ${SUBM_NAMESPACE} -o json  || submariner_status=DOWN

  ${OC} get Submariner -n ${SUBM_NAMESPACE} -o yaml || submariner_status=DOWN

  ${OC} get all -n ${SUBM_NAMESPACE} --show-labels |& (! highlight "Error") \
  || BUG "Globalnet pod might have terminated after deployment" \
  "No workaround, ignore ERROR state (Globalnet pod will be restarted)" \
  "https://github.com/submariner-io/submariner/issues/903"

  ${OC} get all -n ${SUBM_NAMESPACE} --show-labels |& (! highlight "CrashLoopBackOff|No resources found") \
  || submariner_status=DOWN
  # TODO: consider checking for "Terminating" pods

  if [[ "$submariner_status" = DOWN ]] ; then
    FATAL "Submariner installation failure occurred on $cluster_name.
    Resources/CRDs were not installed, or Submariner pods have crashed."
  fi

}

# ------------------------------------------

function test_disaster_recovery_of_gateway_nodes() {
# Check that submariner tunnel works if broker nodes External-IPs (on gateways) is changed
  PROMPT "Testing Disaster Recovery: Reboot Submariner-Gateway VM, to verify re-allocation of public (external) IP"
  trap_commands;

  aws --version || FATAL "AWS-CLI is missing. Try to run again with option '--config-aws-cli'"

  kubconf_a;

  local public_ip=$(${OC} get nodes -l node-role.kubernetes.io/worker -o wide | awk '$7!="<none>" && NR>1 {print $7}')
  echo "# Before VM reboot - Gateway public (external) IP should be: $public_ip"
  verify_gateway_public_ip "$public_ip"

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

  echo "# Watching Submariner Engine pod - It should create new Gateway:"

  submariner_engine_pod="`get_running_pod_by_label 'app=submariner-engine' $SUBM_NAMESPACE `"
  regex="All controllers stopped or exited"
  # Watch submariner-engine pod logs for 200 (10 X 20) seconds
  watch_pod_logs "$submariner_engine_pod" "${SUBM_NAMESPACE}" "$regex" 10 || :

  public_ip=$(${OC} get nodes -l node-role.kubernetes.io/worker -o wide | awk '$7!="<none>" && NR>1 {print $7}')
  echo -e "\n\n# After VM reboot - Gateway public (external) IP should be: $public_ip \n"
  verify_gateway_public_ip "$public_ip"

}

# ------------------------------------------

function verify_gateway_public_ip() {
# sub-function for test_disaster_recovery_of_gateway_nodes
  trap_commands;

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
  trap_commands;

  kubconf_a;
  test_submariner_cable_driver "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_cable_driver_cluster_b() {
  trap_commands;

  kubconf_b;
  test_submariner_cable_driver "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_submariner_cable_driver() {
# Check submariner cable driver
  trap_commands;
  cluster_name="$1"

  PROMPT "Testing Cable-Driver ${subm_cable_driver:+\"$subm_cable_driver\" }on ${cluster_name}"

  # local submariner_engine_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-engine -o jsonpath="{.items[0].metadata.name}")
  submariner_engine_pod="`get_running_pod_by_label 'app=submariner-engine' $SUBM_NAMESPACE `"
  local regex="(cable.* started|Status:connected)"
  # Watch submariner-engine pod logs for 200 (10 X 20) seconds
  watch_pod_logs "$submariner_engine_pod" "${SUBM_NAMESPACE}" "$regex" 10

  if [[ "${subm_cable_driver}" =~ strongswan ]] ; then
    echo "# Verify StrongSwan URI: "
    ${OC} exec $submariner_engine_pod -n ${SUBM_NAMESPACE} -- bash -c \
    "swanctl --list-sas --uri unix:///var/run/charon.vici" |& (! highlight "CONNECTING, IKEv2" ) || :
  fi

}

# ------------------------------------------

function test_ha_status_cluster_a() {
  trap_commands;

  kubconf_a;
  test_ha_status "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_ha_status_cluster_b() {
  trap_commands;

  kubconf_b;
  test_ha_status "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_ha_status() {
# Check submariner HA status
  trap_commands;
  cluster_name="$1"
  local submariner_status=UP

  PROMPT "Check HA status and IPSEC tunnel of Submariner and Gateway resources on ${cluster_name}"

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
  local regex="Status:\s*connect"
  # Attempt cmd for 3 minutes (grepping for 'Connections:' and print 14 lines afterwards), looking for Status connected
  watch_and_retry "$cmd | grep -A 14 'Connections:'" 3m "$regex"

  submariner_gateway_info="$(${OC} describe Submariner -n ${SUBM_NAMESPACE})"
  # echo "$submariner_gateway_info" |& highlight "Status:\s*connected" || submariner_status=DOWN
  echo "$submariner_gateway_info" |& (! highlight "Status Failure\s*\w+") || submariner_status=DOWN

  if [[ "$submariner_status" = DOWN ]] ; then
    FATAL "Submariner HA failure occurred."
  fi

}


# ------------------------------------------

function test_submariner_connection_cluster_a() {
  trap_commands;

  kubconf_a;
  test_submariner_connection_established "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_submariner_connection_cluster_b() {
  trap_commands;

  kubconf_b;
  test_submariner_connection_established "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_submariner_connection_established() {
# Check submariner cable driver
  trap_commands;
  cluster_name="$1"

  PROMPT "Check Submariner Engine established connection on ${cluster_name}"

  # local submariner_engine_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-engine -o jsonpath="{.items[0].metadata.name}")
  submariner_engine_pod="`get_running_pod_by_label 'app=submariner-engine' $SUBM_NAMESPACE `"

  ${OC} describe pod $submariner_engine_pod -n ${SUBM_NAMESPACE} || submariner_status=DOWN

  echo "# Tailing logs in Submariner-Engine pod [$submariner_engine_pod] to verify connection between clusters"
  # ${OC} logs $submariner_engine_pod -n ${SUBM_NAMESPACE} | grep "received packet" -C 2 || submariner_status=DOWN

  local regex="(Successfully installed Endpoint cable .* remote IP|Status:connected|CableName:.*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)"
  # Watch submariner-engine pod logs for 400 (20 X 20) seconds
  watch_pod_logs "$submariner_engine_pod" "${SUBM_NAMESPACE}" "$regex" 20 || submariner_status=DOWN

  [[ "$submariner_status" != DOWN ]] || FATAL "Submariner clusters are not connected."
}


# ------------------------------------------

function test_globalnet_status_cluster_a() {
  trap_commands;

  kubconf_a;
  test_globalnet_status "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_globalnet_status_cluster_b() {
  trap_commands;

  kubconf_b;
  test_globalnet_status "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_globalnet_status() {
  # Check Globalnet controller pod status
  trap_commands;
  cluster_name="$1"

  PROMPT "Testing GlobalNet controller, Global IPs and Endpoints status on ${cluster_name}"

  # globalnet_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-globalnet -o jsonpath="{.items[0].metadata.name}")
  # [[ -n "$globalnet_pod" ]] || globalnet_status=DOWN
  globalnet_pod="`get_running_pod_by_label 'app=submariner-globalnet' $SUBM_NAMESPACE `"


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
  trap_commands;

  kubconf_a;
  test_lighthouse_status "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_lighthouse_status_cluster_b() {
  trap_commands;

  kubconf_b;
  test_lighthouse_status "${CLUSTER_B_NAME}"
}

# ------------------------------------------

function test_lighthouse_status() {
  # Check Lighthouse (the pod for service-discovery) status
  trap_commands;
  cluster_name="$1"

  PROMPT "Testing Lighthouse agent status on ${cluster_name}"

  # lighthouse_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-lighthouse-agent -o jsonpath="{.items[0].metadata.name}")
  # [[ -n "$lighthouse_pod" ]] || FATAL "Lighthouse pod was not created on ${SUBM_NAMESPACE} namespace."
  lighthouse_pod="`get_running_pod_by_label 'app=submariner-lighthouse-agent' $SUBM_NAMESPACE`"

  echo "# Tailing logs in Lighthouse pod [$lighthouse_pod] to verify Service-Discovery sync with Broker"
  local regex="agent .* started"
  # Watch lighthouse pod logs for 100 (5 X 20) seconds
  watch_pod_logs "$lighthouse_pod" "${SUBM_NAMESPACE}" "$regex" 5

  # TODO: Can also test app=submariner-lighthouse-coredns  for the lighthouse DNS status
}


# ------------------------------------------

function test_svc_pod_global_ip_created() {
  # Check that the Service or Pod was annotated with GlobalNet IP
  # Set external variable GLOBAL_IP if there's a GlobalNet IP
  trap_commands

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
  trap_commands;

  kubconf_a;
  # ${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --field-selector status.phase=Running | awk 'FNR == 2 {print $1}' > "$TEMP_FILE"
  # netshoot_pod_cluster_a="$(< $TEMP_FILE)"
  netshoot_pod_cluster_a="`get_running_pod_by_label "run=${NETSHOOT_CLUSTER_A}" $TEST_NS `"

  echo "# NETSHOOT_CLUSTER_A: $netshoot_pod_cluster_a"
    # netshoot-785ffd8c8-zv7td

  kubconf_b;
  echo "${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')"
  # nginx_IP_cluster_b=$(${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}')
  ${OC} get svc -l app=${NGINX_CLUSTER_B} ${TEST_NS:+-n $TEST_NS} | awk 'FNR == 2 {print $3}' > "$TEMP_FILE"
  nginx_IP_cluster_b="$(< $TEMP_FILE)"
  echo "# Nginx service on cluster B, will be identified by its IP (without --service-discovery): $nginx_IP_cluster_b:8080"
    # nginx_IP_cluster_b: 100.96.43.129

  kubconf_a;
  CURL_CMD="${TEST_NS:+-n $TEST_NS} ${netshoot_pod_cluster_a} -- curl --output /dev/null --max-time 30 --verbose ${nginx_IP_cluster_b}:8080"

  if [[ ! "$globalnet" =~ ^(y|yes)$ ]] ; then
    PROMPT "Testing connection without GlobalNet: From Netshoot on AWS cluster A (public), to Nginx service IP on OSP cluster B (on-prem)"

    if ! ${OC} exec ${CURL_CMD} ; then
      FATAL "Submariner connection failure${subm_cable_driver:+ (Cable-driver=$subm_cable_driver)}.
      \n Maybe you installed clusters with overlapping CIDRs ?"
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
    \n# Nginx internal IP (${nginx_IP_cluster_b}:8080) on cluster B, should NOT be reachable outside cluster, if using GlobalNet."

    ${OC} exec ${CURL_CMD} |& (! highlight "Failed to connect" && FATAL "$msg") || echo -e "$msg"
  fi
}

# ------------------------------------------

function test_clusters_connected_overlapping_cidrs() {
### Run Connectivity tests between the On-Premise and Public clusters ###
# To validate that now Submariner made the connection possible!
  PROMPT "Testing GlobalNet annotation - Nginx service on OSP cluster B (on-prem) should get a GlobalNet IP"
  trap_commands;

  kubconf_b;

  # Should fail if NGINX_CLUSTER_B was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_svc_pod_global_ip_created svc "$NGINX_CLUSTER_B" $TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on Nginx service (${NGINX_CLUSTER_B}${TEST_NS:+.$TEST_NS})"
  nginx_global_ip="$GLOBAL_IP"

  PROMPT "Testing GlobalNet annotation - Netshoot pod on AWS cluster A (public) should get a GlobalNet IP"
  kubconf_a;
  # netshoot_pod_cluster_a=$(${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} \
  # --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')
  netshoot_pod_cluster_a="`get_running_pod_by_label "run=${NETSHOOT_CLUSTER_A}" $TEST_NS `"

  # Should fail if netshoot_pod_cluster_a was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_svc_pod_global_ip_created pod "$netshoot_pod_cluster_a" $TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on Netshoot Pod (${netshoot_pod_cluster_a}${TEST_NS:+ in $TEST_NS})"
  netshoot_global_ip="$GLOBAL_IP"

  # TODO: Ping to the netshoot_global_ip


  PROMPT "Testing GlobalNet connectivity - From Netshoot pod ${netshoot_pod_cluster_a} (IP ${netshoot_global_ip}) on cluster A
  To Nginx service on cluster B, by its Global IP: $nginx_global_ip:8080"

  kubconf_a;
  ${OC} exec ${netshoot_pod_cluster_a} ${TEST_NS:+-n $TEST_NS} \
  -- curl --output /dev/null --max-time 30 --verbose ${nginx_global_ip}:8080

  #TODO: validate annotation of globalIp in the node
}

# ------------------------------------------

function test_clusters_connected_full_domain_name() {
### Nginx service on cluster B, will be identified by its Domain Name, with --service-discovery ###
# This is to test service discovery of NON-headless $NGINX_CLUSTER_B sevice, on the default namespace

  trap_commands;

  # Set FQDN on clusterset.local when using Service-Discovery (lighthouse)
  local nginx_cl_b_dns="${NGINX_CLUSTER_B}${TEST_NS:+.$TEST_NS}.svc.${MULTI_CLUSTER_DOMAIN}"

  PROMPT "Testing Service-Discovery: From Netshoot pod on cluster A${TEST_NS:+ (Namespace $TEST_NS)}
  To the default Nginx service on cluster B${TEST_NS:+ (Namespace ${TEST_NS:-default})}, by DNS hostname: $nginx_cl_b_dns"

  kubconf_a

  echo "# Try to ping ${NGINX_CLUSTER_B} until getting expected FQDN: $nginx_cl_b_dns (and IP)"
  #TODO: Validate both GlobalIP and svc.${MULTI_CLUSTER_DOMAIN} with   ${OC} get all
      # NAME                 TYPE           CLUSTER-IP   EXTERNAL-IP                            PORT(S)   AGE
      # service/kubernetes   clusterIP      172.30.0.1   <none>                                 443/TCP   39m
      # service/openshift    ExternalName   <none>       kubernetes.default.svc.clusterset.local   <none>    32m

  cmd="${OC} exec ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} -- ping -c 1 $nginx_cl_b_dns"
  local regex="PING ${nginx_cl_b_dns}"
  watch_and_retry "$cmd" 3m "$regex"
    # PING netshoot-cl-a-new.test-submariner-new.svc.clusterset.local (169.254.59.89)

  echo "# Try to CURL from ${NETSHOOT_CLUSTER_A} to ${nginx_cl_b_dns}:8080 :"
  ${OC} exec ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_cl_b_dns}:8080"

  # TODO: Test connectivity with https://github.com/tsliwowicz/go-wrk

}

# ------------------------------------------

function test_clusters_cannot_connect_short_service_name() {
### Negative test for nginx_cl_b_short_dns FQDN ###

  trap_commands;

  local nginx_cl_b_short_dns="${NGINX_CLUSTER_B}${TEST_NS:+.$TEST_NS}"

  PROMPT "Testing Service-Discovery:
  There should be NO DNS resolution from cluster A to the local Nginx address on cluster B: $nginx_cl_b_short_dns (FQDN without \"clusterset\")"

  kubconf_a

  msg="# Negative Test - ${nginx_cl_b_short_dns}:8080 should not be reachable (FQDN without \"clusterset\")."

  ${OC} exec ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} \
  -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_cl_b_short_dns}:8080" \
  |& (! highlight "command terminated with exit code" && FATAL "$msg") || echo -e "$msg"
    # command terminated with exit code 28
}

# ------------------------------------------

function install_new_netshoot_cluster_a() {
### Install $NEW_NETSHOOT_CLUSTER_A on the $TEST_NS namespace ###

  trap_commands;
  PROMPT "Install NEW Netshoot pod on AWS cluster A${TEST_NS:+ (Namespace $TEST_NS)}"
  kubconf_a; # Can also use --context ${CLUSTER_A_NAME} on all further oc commands

  ${OC} delete pod ${NEW_NETSHOOT_CLUSTER_A} --ignore-not-found ${TEST_NS:+-n $TEST_NS} || :

  ${OC} run ${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} --image nicolaka/netshoot \
  --pod-running-timeout=5m --restart=Never -- sleep 5m

  echo "# Wait up to 3 minutes for NEW Netshoot pod [${NEW_NETSHOOT_CLUSTER_A}] to be ready:"
  ${OC} wait --timeout=3m --for=condition=ready pod -l run=${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
  ${OC} describe pod ${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS}
}

# ------------------------------------------

function test_new_netshoot_global_ip_cluster_a() {
### Check that $NEW_NETSHOOT_CLUSTER_A on the $TEST_NS is annotated with GlobalNet IP ###

  trap_commands;
  PROMPT "Testing GlobalNet annotation - NEW Netshoot pod on AWS cluster A (public) should get a GlobalNet IP"
  kubconf_a;

  # netshoot_pod=$(${OC} get pods -l run=${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} \
  # --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')
  # get_running_pod_by_label "run=${NEW_NETSHOOT_CLUSTER_A}" "${TEST_NS}"

  # Should fail if NEW_NETSHOOT_CLUSTER_A was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_svc_pod_global_ip_created pod "$NEW_NETSHOOT_CLUSTER_A" $TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on NEW Netshoot Pod (${NEW_NETSHOOT_CLUSTER_A}${TEST_NS:+ in $TEST_NS})"
}

# ------------------------------------------

function install_nginx_headless_namespace_cluster_b() {
### Install $NGINX_CLUSTER_B on the $HEADLESS_TEST_NS namespace ###

  trap_commands;
  PROMPT "Install HEADLESS Nginx service on OSP cluster B${HEADLESS_TEST_NS:+ (Namespace $HEADLESS_TEST_NS)}"
  kubconf_b;

  # Headless service is created when disabling it's cluster-ip with --cluster-ip=None
  install_nginx_service "${NGINX_CLUSTER_B}" "${HEADLESS_TEST_NS}" "--port=8080 --cluster-ip=None"
}

# ------------------------------------------

function test_nginx_headless_global_ip_cluster_b() {
### Check that $NGINX_CLUSTER_B on the $HEADLESS_TEST_NS is annotated with GlobalNet IP ###

  trap_commands;

  PROMPT "Testing GlobalNet annotation - The HEADLESS Nginx service on OSP cluster B should get a GlobalNet IP"

  if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then
    BUG "HEADLESS Service is not supported with GlobalNet" \
     "No workaround yet - Skip the whole test" \
    "https://github.com/submariner-io/lighthouse/issues/273"
    # No workaround yet
    return 1
  fi

  kubconf_b

  # Should fail if NGINX_CLUSTER_B was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_svc_pod_global_ip_created svc "$NGINX_CLUSTER_B" $HEADLESS_TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on the HEADLESS Nginx service (${NGINX_CLUSTER_B}${HEADLESS_TEST_NS:+.$HEADLESS_TEST_NS})"

  # TODO: Ping to the new_nginx_global_ip
  # new_nginx_global_ip="$GLOBAL_IP"
}

# ------------------------------------------

function test_clusters_connected_headless_service_on_new_namespace() {
### Nginx service on cluster B, will be identified by its Domain Name, with --service-discovery ###

  trap_commands;

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

    kubconf_a

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

    echo "# Try to CURL from ${NEW_NETSHOOT_CLUSTER_A} to ${nginx_headless_cl_b_dns}:8080 :"
    ${OC} exec ${NEW_NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_headless_cl_b_dns}:8080"

    # TODO: Test connectivity with https://github.com/tsliwowicz/go-wrk

  fi

}

# ------------------------------------------

function test_clusters_cannot_connect_headless_short_service_name() {
### Negative test for HEADLESS nginx_cl_b_short_dns FQDN ###

  trap_commands;

  local nginx_cl_b_short_dns="${NGINX_CLUSTER_B}${HEADLESS_TEST_NS:+.$HEADLESS_TEST_NS}"

  PROMPT "Testing Service-Discovery:
  There should be NO DNS resolution from cluster A to the local Nginx address on cluster B: $nginx_cl_b_short_dns (FQDN without \"clusterset\")"

  kubconf_a

  msg="# Negative Test - ${nginx_cl_b_short_dns}:8080 should not be reachable (FQDN without \"clusterset\")."

  ${OC} exec ${NETSHOOT_CLUSTER_A} ${TEST_NS:+-n $TEST_NS} \
  -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_cl_b_short_dns}:8080" \
  |& (! highlight "command terminated with exit code" && FATAL "$msg") || echo -e "$msg"
    # command terminated with exit code 28

}

# ------------------------------------------

function test_subctl_show_on_merged_kubeconfigs() {
### Test subctl show commands on merged kubeconfig ###
  PROMPT "Testing SUBCTL show command on merged kubeconfig of multiple clusters"
  trap_commands;

  local subctl_info

  BUG "Should be able to use default KUBECONFIGs of OCP installers, with identical context (\"admin\")" \
  "Modify KUBECONFIG context name on cluster A and B, to be unique (to prevent E2E failure)" \
  "https://github.com/submariner-io/submariner/issues/245"
  sed -z "s#name: [a-zA-Z0-9-]*\ncurrent-context: [a-zA-Z0-9-]*#name: ${CLUSTER_A_NAME}\ncurrent-context: ${CLUSTER_A_NAME}#" -i.bak ${KUBECONF_CLUSTER_A}
  sed -z "s#name: [a-zA-Z0-9-]*\ncurrent-context: [a-zA-Z0-9-]*#name: ${CLUSTER_B_NAME}\ncurrent-context: ${CLUSTER_B_NAME}#" -i.bak ${KUBECONF_CLUSTER_B}

  export KUBECONFIG="${KUBECONF_CLUSTER_A}:${KUBECONF_CLUSTER_B}"

  subctl show versions || subctl_info=ERROR

  subctl show networks || subctl_info=ERROR

  subctl show endpoints || subctl_info=ERROR

  subctl show connections || subctl_info=ERROR

  subctl show gateways || subctl_info=ERROR

  [[ "$subctl_info" != ERROR ]] || FATAL "Submariner HA failure occurred."
}

# ------------------------------------------

function test_submariner_packages() {
### Run Submariner Unit tests (mock) ###
  PROMPT "Testing Submariner Packages (Unit-Tests) with GO"
  trap_commands;

  cd $GOPATH/src/github.com/submariner-io/submariner

  export GO111MODULE="on"
  go env
  go test -v ./pkg -ginkgo.v -ginkgo.reportFile "$PKG_JUNIT_XML"

    # OR with local go modules:
      # GO111MODULE="on" go test -v ./pkg/... -ginkgo.v -ginkgo.reportFile junit_result.xml

}

# ------------------------------------------

function test_submariner_e2e_with_go() {
# Run E2E Tests of Submariner:
  PROMPT "Testing Submariner End-to-End tests with GO"
  trap_commands;

  cd $GOPATH/src/github.com/submariner-io/submariner

  export KUBECONFIG="${KUBECONF_CLUSTER_A}:${KUBECONF_CLUSTER_B}"

  ${OC} config get-contexts
    # CURRENT   NAME              CLUSTER            AUTHINFO   NAMESPACE
    # *         admin             user-cluster-a   admin
    #           admin_cluster_b   user-cl1         admin

  export GO111MODULE="on"
  go env

  go test -v ./test/e2e \
  -timeout 30m \
  -ginkgo.v -ginkgo.trace \
  -ginkgo.randomizeAllSpecs \
  -ginkgo.noColor \
  -ginkgo.reportPassed \
  -ginkgo.reportFile "$E2E_JUNIT_XML" \
  -args \
  --dp-context ${CLUSTER_A_NAME} --dp-context ${CLUSTER_B_NAME} \
  --submariner-namespace ${SUBM_NAMESPACE} \
  --connection-timeout 30 --connection-attempts 3 \
  || echo "# Warning: Test execution failure occurred"
}

# ------------------------------------------

function test_lighthouse_e2e_with_go() {
# Run E2E Tests of Lighthouse with Ginkgo (https://github.com/submariner-io/lighthouse/issues/211)
  PROMPT "Testing Lighthouse End-to-End tests with GO"
  trap_commands;

  cd $GOPATH/src/github.com/submariner-io/lighthouse

  export KUBECONFIG="${KUBECONF_CLUSTER_A}:${KUBECONF_CLUSTER_B}"

  ${OC} config get-contexts
    # CURRENT   NAME              CLUSTER            AUTHINFO   NAMESPACE
    # *         admin             user-cluster-a   admin
    #           admin_cluster_b   user-cl1         admin

  export GO111MODULE="on"
  go env

  go test -v ./test/e2e \
  -timeout 30m \
  -ginkgo.v -ginkgo.trace \
  -ginkgo.randomizeAllSpecs \
  -ginkgo.noColor \
  -ginkgo.reportPassed \
  -ginkgo.reportFile "$LIGHTHOUSE_JUNIT_XML" \
  -args \
  --dp-context ${CLUSTER_A_NAME} --dp-context ${CLUSTER_B_NAME} \
  --submariner-namespace ${SUBM_NAMESPACE} \
  --connection-timeout 30 --connection-attempts 3 \
  || echo "# Warning: Test execution failure occurred"
}

# ------------------------------------------

function test_submariner_e2e_with_subctl() {
# Run E2E Tests of Submariner:
  PROMPT "Testing Submariner End-to-End tests with SubCtl command"
  trap_commands;

  export KUBECONFIG="${KUBECONF_CLUSTER_A}:${KUBECONF_CLUSTER_B}"

  [[ -x "$(command -v subctl)" ]] || FATAL "No SubCtl installation found. Try to run again with option '--install-subctl'"
  subctl version

  BUG "No Subctl option to set -ginkgo.reportFile" \
  "No workaround yet..." \
  "https://github.com/submariner-io/submariner-operator/issues/509"

  # subctl verify --enable-disruptive --verbose ${KUBECONF_CLUSTER_A} ${KUBECONF_CLUSTER_B}
  subctl verify --only service-discovery,connectivity --verbose ${KUBECONF_CLUSTER_A} ${KUBECONF_CLUSTER_B}
}

# ------------------------------------------

function upload_junit_xml_to_polarion() {
  trap_commands;
  local junit_file="$1"
  echo -e "\n### Uploading test results to Polarion from Junit file: $junit_file ###\n"

  create_polarion_testcases_doc_from_junit "https://$POLARION_SERVER/polarion" "$POLARION_AUTH" \
  "$junit_file" "$POLARION_PROJECT_ID" "$POLARION_TEAM_NAME" "$POLARION_USR"

  create_polarion_testrun_result_from_junit "https://$POLARION_SERVER/polarion" "$POLARION_AUTH" \
  "$junit_file" "$POLARION_PROJECT_ID" "$POLARION_TEAM_NAME" "$POLARION_TESTRUN_TEMPLATE"

}

# ------------------------------------------

function create_all_test_results_in_polarion() {
  PROMPT "Upload all test results to Polarion"
  trap_commands;

  local polarion_rc=0

  # Upload SYSTEM tests to Polarion
  echo "# Upload Junit results of SYSTEM (Shell) tests to Polarion:"
  upload_junit_xml_to_polarion "$SCRIPT_DIR/$SHELL_JUNIT_XML" || polarion_rc=1


  # Upload E2E tests to Polarion

  if [[ (! "$skip_tests" =~ ^((e2e|all)(,|$))+) && -s "$E2E_JUNIT_XML" ]] ; then
    echo "# Upload Junit results of E2E (Ginkgo) tests to Polarion:"

    BUG "Polarion cannot parse junit xml which where created by Ginkgo tests" \
    "Rename in Ginkgo junit xml the 'passed' tags with 'system-out' tags" \
    "https://github.com/submariner-io/shipyard/issues/48"
    # Workaround:
    sed -r 's/(<\/?)(passed>)/\1system-out>/g' -i "$E2E_JUNIT_XML" || :

    upload_junit_xml_to_polarion "$E2E_JUNIT_XML" || polarion_rc=1
  fi

  # Upload UNIT tests to Polarion (skipping, not really required)

  # if [[ (! "$skip_tests" =~ ^((pkg|all)(,|$))+) && -s "$PKG_JUNIT_XML" ]] ; then
  #   echo "# Upload Junit results of PKG (Ginkgo) unit-tests to Polarion:"
  #   sed -r 's/(<\/?)(passed>)/\1system-out>/g' -i "$PKG_JUNIT_XML" || :
  #
  #   upload_junit_xml_to_polarion "$PKG_JUNIT_XML" || polarion_rc=1
  # fi

  return $polarion_rc
}


# ------------------------------------------

function collect_submariner_info() {
  # print submariner pods descriptions and logs
  # Ref: https://github.com/submariner-io/shipyard/blob/master/scripts/shared/post_mortem.sh

  local log_file="${1:-subm_pods.log}"

  (
    PROMPT "Collecting Submariner pods logs due to test failure" "$RED"
    trap_commands;

    df -h
    free -h

    export KUBECONFIG="${KUBECONF_CLUSTER_A}:${KUBECONF_CLUSTER_B}"

    # oc version
    BUG "OC client version 4.5.1 cannot use merged kubeconfig" \
    "use an older OC client, or run oc commands for each cluster separately" \
    "https://bugzilla.redhat.com/show_bug.cgi?id=1857202"
    # Workaround:
    # OC="/usr/bin/oc"
    oc version || :

    echo "Submariner info (subctl show all):"

    subctl show all || :

    kubconf_a;
    print_submariner_pod_logs "${CLUSTER_A_NAME}"

    kubconf_b;
    print_submariner_pod_logs "${CLUSTER_B_NAME}"
  ) |& tee -a $log_file

}

# ------------------------------------------

function print_submariner_pod_logs() {
  trap_commands;
  local cluster_name="$1"

  echo -e "\n############################## Printing Submariner logs on ${cluster_name} ##############################\n"

  ${OC} get all -n ${SUBM_NAMESPACE} || :
  ${OC} describe ds -n ${SUBM_NAMESPACE} || :
  ${OC} describe cm -n openshift-dns || :

  ${OC} get pods -n ${SUBM_NAMESPACE} --show-labels || :
  ${OC} get clusters -n ${SUBM_NAMESPACE} -o wide || :
  # TODO: Loop on each cluster: ${OC} describe cluster "${cluster_name}" -n ${SUBM_NAMESPACE} || :

  ${OC} get Submariner -o yaml -n ${SUBM_NAMESPACE} || :
  ${OC} get deployments -o yaml -n ${SUBM_NAMESPACE} || :

  ${OC} describe Submariner -n ${SUBM_NAMESPACE} || :

  ${OC} describe Gateway -n ${SUBM_NAMESPACE} || :

  ${OC} get Machine -A || :

  oc get Machine -A | awk '{
    if (NR>1) {
      namespace = $1
      machine = $2
      printf ("\n###################### Machine: %s (Namespece: %s) ######################\n", machine, namespace )
      cmd = "oc describe Machine " machine " -n " namespace
      printf ("\n$ %s\n\n", cmd)
      system("oc describe Machine "$2" -n "$1)
    }
  }'

  ${OC} get events -A --sort-by='.metadata.creationTimestamp' || :

  # for pod in $(${OC} get pods -A \
  # -l 'name in (submariner-operator,submariner-engine,submariner-globalnet,kube-proxy)' \
  # -o jsonpath='{.items[0].metadata.namespace} {.items[0].metadata.name}' ; do
  #     echo "######################: Logs for Pod $pod :######################"
  #     ${OC}  -n $ns describe pod $name
  #     ${OC}  -n $namespace logs $pod
  # done

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "name=submariner-operator"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-engine"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-globalnet"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-lighthouse-agent"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-lighthouse-coredns"

  print_pod_logs_in_namespace "$cluster_name" "$SUBM_NAMESPACE" "app=submariner-routeagent"

  print_pod_logs_in_namespace "$cluster_name" "kube-system" "k8s-app=kube-proxy"

  echo -e "\n############################## End of Submariner logs collection on ${cluster_name} ##############################\n"

}

# ------------------------------------------

# Function to debug this script
function FAIL_DEBUG() {
  find ${CLUSTER_A_DIR} -name "*.log" -0 | xargs cat
  FAIL_HERE
}

# ------------------------------------------


####################################################################################
#                    Main - Submariner Deploy and Tests                            #
####################################################################################

### Set script in debug/verbose mode, if used CLI option: --debug / -d ###
if [[ "$script_debug_mode" =~ ^(yes|y)$ ]]; then
  # Extra verbosity for oc commands:
  # https://kubernetes.io/docs/reference/kubectl/cheatsheet/#kubectl-output-verbosity-and-debugging
  export VERBOSE_FLAG="--v=2"
  export OC="$OC $VERBOSE_FLAG"

  # Debug flag for ocpup and aws commands
  export DEBUG_FLAG="--debug"

else
  # Clear trap_commands function
  trap_commands() { :; }
fi

cd ${SCRIPT_DIR}

# Setting Cluster A and Broker config ($WORKDIR and $CLUSTER_A_NAME were set in subm_variables file)
export KUBECONF_BROKER=${WORKDIR}/${BROKER_CLUSTER_NAME}/auth/kubeconfig
export CLUSTER_A_DIR=${WORKDIR}/${CLUSTER_A_NAME}
export KUBECONF_CLUSTER_A=${CLUSTER_A_DIR}/auth/kubeconfig

# Setting Cluster B config ($OCPUP_DIR and $CLUSTER_B_YAML were set in subm_variables file)
export CLUSTER_B_DIR=${OCPUP_DIR}/.config/$(awk '/clusterName:/ {print $NF}' "${CLUSTER_B_YAML}")
export KUBECONF_CLUSTER_B=${CLUSTER_B_DIR}/auth/kubeconfig

# Logging main output (enclosed with parenthesis) with tee
LOG_FILE="${REPORT_NAME// /_}" # replace all spaces with _
LOG_FILE="${LOG_FILE}_${DATE_TIME}.log" # can also consider adding timestemps with: ts '%H:%M:%.S' -s
> "$LOG_FILE"

# Printing output both to stdout and to $LOG_FILE with tee
# TODO: consider adding timestemps with: ts '%H:%M:%.S' -s
(

  # trap_function_on_error "collect_submariner_info" (if passing CLI option --print-logs)
  if [[ "$print_logs" =~ ^(y|yes)$ ]]; then
    trap_function_on_error "${junit_cmd} collect_submariner_info"
  fi

  # Print planned steps according to CLI/User inputs
  ${junit_cmd} show_test_plan

  # Debug function
  # ${junit_cmd} FAIL_DEBUG

  # Setup and verify environment
  setup_workspace

  ### Destroy / Create / Clean OCP Clusters (if not requested to skip_ocp_setup) ###

  if [[ ! "$skip_ocp_setup" =~ ^(y|yes)$ ]]; then

    # Running download_ocp_installer if requested
    [[ ! "$get_ocp_installer" =~ ^(y|yes)$ ]] || ${junit_cmd} download_ocp_installer ${OCP_VERSION}

    # Running build_ocpup_tool_latest if requested
    [[ ! "$get_ocpup_tool" =~ ^(y|yes)$ ]] || ${junit_cmd} build_ocpup_tool_latest

    # Running reset_cluster_a if requested
    if [[ "$reset_cluster_a" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} destroy_aws_cluster_a

      ${junit_cmd} prepare_install_aws_cluster_a

      ${junit_cmd} create_aws_cluster_a

    else
      # Running destroy_aws_cluster_a and create_aws_cluster_a separately
      if [[ "$destroy_cluster_a" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} destroy_aws_cluster_a

      fi

      if [[ "$create_cluster_a" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} prepare_install_aws_cluster_a

        ${junit_cmd} create_aws_cluster_a

      fi
    fi

    ${junit_cmd} test_kubeconfig_aws_cluster_a

    # Running reset_cluster_b if requested
    if [[ "$reset_cluster_b" =~ ^(y|yes)$ ]] ; then

      ${junit_cmd} destroy_osp_cluster_b

      ${junit_cmd} create_osp_cluster_b

    else
      # Running destroy_aws_cluster_b and create_aws_cluster_b separately
      [[ ! "$destroy_cluster_b" =~ ^(y|yes)$ ]] || ${junit_cmd} destroy_osp_cluster_b

      [[ ! "$create_cluster_b" =~ ^(y|yes)$ ]] || ${junit_cmd} create_osp_cluster_b
    fi

    ${junit_cmd} test_kubeconfig_osp_cluster_b

    ### Cleanup Submariner from all clusters ###

    # Running clean_aws_cluster_a if requested
    if [[ "$clean_cluster_a" =~ ^(y|yes)$ ]] && [[ ! "$destroy_cluster_a" =~ ^(y|yes)$ ]] ; then
      ${junit_cmd} clean_aws_cluster_a
    fi

    # Running clean_osp_cluster_b if requested
    if [[ "$clean_cluster_b" =~ ^(y|yes)$ ]] && [[ ! "$destroy_cluster_b" =~ ^(y|yes)$ ]] ; then
      ${junit_cmd} clean_osp_cluster_b
    fi

    # Running basic pre-submariner tests (only required for sys tests on new/cleaned clusters)
    if [[ ! "$skip_tests" =~ ^((sys|all)(,|$))+ ]]; then

      ${junit_cmd} install_netshoot_app_on_cluster_a

      ${junit_cmd} install_nginx_svc_on_cluster_b

      ${junit_cmd} test_basic_cluster_connectivity_before_submariner

      ${junit_cmd} test_clusters_disconnected_before_submariner
    fi

  fi


  ### Deploy Submariner on the clusters (if not requested to skip_install) ###

  if [[ ! "$skip_install" =~ ^(y|yes)$ ]]; then

    # Running build_operator_latest if requested  # [DEPRECATED]
    # [[ ! "$build_operator" =~ ^(y|yes)$ ]] || ${junit_cmd} build_operator_latest

    # Running download_subctl_latest_release if requested
    [[ ! "$get_subctl" =~ ^(y|yes)$ ]] || ${junit_cmd} download_subctl_latest_release

    # Running download_subctl_latest_release if requested
    [[ ! "$install_subctl_devel" =~ ^(y|yes)$ ]] || ${junit_cmd} download_subctl_latest_devel

    ${junit_cmd} test_subctl_command

    ${junit_cmd} open_firewall_ports_on_the_broker_node

    ${junit_cmd} label_gateway_on_broker_nodes_with_external_ip

    ${junit_cmd} label_first_gateway_cluster_b

    ${junit_cmd} install_broker_aws_cluster_a

    ${junit_cmd} test_broker_before_join

    ${junit_cmd} join_submariner_cluster_a

    ${junit_cmd} join_submariner_cluster_b
  fi

  ### Running High-level / E2E / Unit Tests (if not requested to skip sys / all tests) ###

  ${junit_cmd} test_products_versions

  if [[ ! "$skip_tests" =~ ^((sys|all)(,|$))+ ]]; then

    ### Running High-level (System) tests of Submariner ###

    ${junit_cmd} test_submariner_resources_cluster_a

    ${junit_cmd} test_submariner_resources_cluster_b

    ${junit_cmd} test_disaster_recovery_of_gateway_nodes

    ${junit_cmd} test_cable_driver_cluster_a

    ${junit_cmd} test_cable_driver_cluster_b

    ${junit_cmd} test_ha_status_cluster_a

    ${junit_cmd} test_ha_status_cluster_b

    ${junit_cmd} test_submariner_connection_cluster_a

    ${junit_cmd} test_submariner_connection_cluster_b

    ${junit_cmd} test_subctl_show_on_merged_kubeconfigs

    if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then
      ${junit_cmd} test_globalnet_status_cluster_a

      ${junit_cmd} test_globalnet_status_cluster_b
    fi

    if [[ "$service_discovery" =~ ^(y|yes)$ ]] ; then
      ${junit_cmd} test_lighthouse_status_cluster_a

      ${junit_cmd} test_lighthouse_status_cluster_b
    fi

  ### Running connectivity tests between the On-Premise and Public clusters,
  # To validate that now Submariner made the connection possible.

    ${junit_cmd} test_clusters_connected_by_service_ip

    ${junit_cmd} install_new_netshoot_cluster_a

    ${junit_cmd} install_nginx_headless_namespace_cluster_b

    if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then
      ${junit_cmd} test_clusters_connected_overlapping_cidrs

      ${junit_cmd} test_new_netshoot_global_ip_cluster_a

      ${junit_cmd} test_nginx_headless_global_ip_cluster_b || :
    fi

    if [[ "$service_discovery" =~ ^(y|yes)$ ]] ; then

      # Test the default (pre-installed) netshoot and nginx service discovery

      ${junit_cmd} export_nginx_default_namespace_cluster_b

      ${junit_cmd} test_clusters_connected_full_domain_name

      ${junit_cmd} test_clusters_cannot_connect_short_service_name

      # Test the new netshoot and headless nginx service discovery

      if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then

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

    echo "# From this point, if script fails - \$TEST_STATUS_RC is considered UNSTABLE
    \n# ($TEST_STATUS_RC with exit code 2)"

    echo 2 > $TEST_STATUS_RC
  fi

  ### Running Submariner Ginkgo tests
  if [[ ! "$skip_tests" =~ all ]]; then

    verify_golang || FATAL "No Golang installation found. Try to run again with option '--config-golang'"

    # Running build_submariner_repos if requested
    [[ ! "$build_go_tests" =~ ^(y|yes)$ ]] || ${junit_cmd} build_submariner_repos

    ### Running Unit-tests in Submariner project directory (Ginkgo)
    if [[ ! "$skip_tests" =~ pkg ]] && [[ "$build_go_tests" =~ ^(y|yes)$ ]]; then
      ${junit_cmd} test_submariner_packages || BUG "Submariner Unit-Tests FAILED."
    fi

    ### Running E2E tests in Submariner and Lighthouse projects directories (Ginkgo)
    if [[ ! "$skip_tests" =~ e2e ]]; then

      if [[ "$build_go_tests" =~ ^(y|yes)$ ]] ; then

        ${junit_cmd} test_submariner_e2e_with_go || \
        BUG "Ginkgo E2E tests of Submariner repository has FAILED." && e2e_tests_status=FAILED

        ${junit_cmd} test_lighthouse_e2e_with_go || \
        BUG "Ginkgo E2E tests of Lighthouse repository has FAILED." && e2e_tests_status=FAILED

      else
        ${junit_cmd} test_submariner_e2e_with_subctl || e2e_tests_status=FAILED
      fi

      if [[ "$e2e_tests_status" = FAILED ]] ; then
        FATAL "Submariner E2E Tests failure"
      fi

    fi
  fi


  # If script got to here - all tests of Submariner has passed ;-)
  echo 0 > $TEST_STATUS_RC

) |& tee -a "$LOG_FILE"


#####################################################################################
#   End Main - Now publish to Polarion, Create HTML report, and archive artifacts   #
#####################################################################################

# ------------------------------------------

cd ${SCRIPT_DIR}

### Upload Junit xmls to Polarion (if requested by user CLI)  ###
if [[ "$upload_to_polarion" =~ ^(y|yes)$ ]] ; then

  # Temp file to store Polarion output
  > "$TEMP_FILE"
  # Redirecting output both to stdout, TEMP_FILE and LOG_FILE
  create_all_test_results_in_polarion |& tee -a "$TEMP_FILE" "$LOG_FILE" || :

  echo "# Get Polarion testrun links: "
  polarion_search_string="Polarion results published to:"

  grep -Po "${polarion_search_string}\K.*" "$TEMP_FILE" >> "$POLARION_REPORTS" || :
  cat "$POLARION_REPORTS"

  # set REPORT_DESCRIPTION for html report
  REPORT_DESCRIPTION="Polarion results:
  $(< "$POLARION_REPORTS")"
fi

# ------------------------------------------

### Creating HTML report from console output ###

echo "# Creating HTML Report from:
# LOG_FILE = $LOG_FILE
# REPORT_NAME = $REPORT_NAME
# REPORT_FILE = $REPORT_FILE
"

# Get test exit status (from file $TEST_STATUS_RC)
test_status="$([[ ! -s "$TEST_STATUS_RC" ]] || cat $TEST_STATUS_RC)"

# prompt message (this is the last print into LOG_FILE
message="Creating HTML Report"
if [[ -z "$test_status" || "$test_status" -ne 0 ]] ; then
  message="$message - Test exit status: $test_status"
  color="$RED"
fi
PROMPT "$message" "$color" |& tee -a "$LOG_FILE"

# Clean LOG_FILE from sh2ju debug lines (+++), if CLI option: --debug was NOT used
[[ "$script_debug_mode" =~ ^(yes|y)$ ]] || sed -i 's/+++.*//' "$LOG_FILE"

# Call log_to_html to create REPORT_FILE (html) from LOG_FILE
log_to_html "$LOG_FILE" "$REPORT_NAME" "$REPORT_FILE" "$REPORT_DESCRIPTION"


# ------------------------------------------

### Collecting artifacts ###

# If REPORT_FILE was not passed externally, set it as the latest html file that was created
REPORT_FILE="${REPORT_FILE:-$(ls -1 -tu *.html | head -1)}"

# Compressing report to tar.gz
report_archive="${REPORT_FILE%.*}_${DATE_TIME}.tar.gz"

echo -e "# Compressing Report, Log, Kubeconfigs and $BROKER_INFO into: ${report_archive}"
[[ ! -f "$KUBECONF_CLUSTER_A" ]] || cp -f "$KUBECONF_CLUSTER_A" "kubconf_${CLUSTER_A_NAME}"
[[ ! -f "$KUBECONF_CLUSTER_B" ]] || cp -f "$KUBECONF_CLUSTER_B" "kubconf_${CLUSTER_B_NAME}"
tar -cvzf $report_archive $(ls \
 "$REPORT_FILE" \
 "$LOG_FILE" \
 kubconf_* \
 *.xml \
 "$WORKDIR/$BROKER_INFO" \
 2>/dev/null)

echo -e "# Archive \"$report_archive\" now contains:"
tar tvf $report_archive

echo -e "# To view in your Browser, run:\n tar -xvf ${report_archive}; firefox ${REPORT_FILE}"

echo "# Exiting script with \$test_status return code: [$test_status]"
exit $test_status

# ------------------------------------------
