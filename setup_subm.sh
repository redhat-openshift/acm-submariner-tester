#!/bin/bash
#######################################################################################################
#                                                                                                     #
# Setup Submariner on AWS and OSP (Upshift)                                                           #
# By Noam Manos, nmanos@redhat.com                                                                    #
# The script is based on the Submariner MVP Doc:                                                      #
# https://docs.google.com/document/d/1HCbyuNX8AELNyB6TE4H05Kj3gujwS4-Im3-BG796zIw                     #
#                                                                                                     #
# It is assumed that you have existing OCP "install-config.yaml" for both cluster A (OSP) and B (OSP),#
# in the current directory. For cluster B, use the existing config of OCPUP multi-cluster-networking. #                                                                         #
#                                                                                                     #
# For cluster A, you can create config with AWS pull secret and SSH public key. To do so:             #
#                                                                                                     #
# (1) Get access to Upshift account.                                                                  #
# - Follow PnT Resource Workflow:                                                                     #
# https://docs.engineering.redhat.com/display/HSSP/PnT+Resource+Request+Workflow+including+PSI        #
# - PSI Resource (Openstack, Upshift) request form:                                                   #
# https://docs.google.com/forms/d/e/1FAIpQLScxbNCO1fNFeIeFUghlCSr9uqVZncYwYmgSR2CLNIQv5AUTaw/viewform #
# - OpenShift on OpenStack (using PSI) Mojo page:                                                     #
# https://mojo.redhat.com/docs/DOC-1207953                                                            #
# - Login to Openstack Admin with your kerberos credentials (and your company domain.com):            #
# https://rhos-d.infra.prod.upshift.rdu2.redhat.com/dashboard/project/                                #
#                                                                                                     #
# (2) Get access to AWS account.                                                                      #
# - To get it, please fill AWS request form:                                                          #
# https://docs.google.com/forms/d/e/1FAIpQLSeBi_walgnC4555JEHk5rw-muFUiOf2VCWa1yuEgSl0vDeyQw/viewform #
# - To validate, login to AWS openshift-dev account via the web console:                              #
# https://{AWS Account ID}.signin.aws.amazon.com/console                                              #
#                                                                                                     #
# (3) Your Red Hat Openshift pull secret, found in:                                                   #
# https://cloud.redhat.com/openshift/install/aws/installer-provisioned                                #
# It is used by OCP Installer to download OCP images from Red Hat repositories.                       #
#                                                                                                     #
# (4) Your SSH Public Key, that you generated with " ssh-keygen -b 4096 "                             #
# cat ~/.ssh/id_rsa.pub                                                                               #
# Your SSH key is used by OCP Installer for authentication.                                           #
#                                                                                                     #
#                                                                                                     #
#######################################################################################################

# Script description
disclosure='----------------------------------------------------------------------

This is an interactive script to create Openshift clusters on OSP and AWS,
and test multi-cluster network connectivity with Submariner:

Running with pre-defined parameters (optional):

* Show this help menu:                               -h / --help
* Show debug info (verbose) for commands:            -d / --debug
# Build latest Submariner-Operator (SubCtl):         --build-operator  [DEPRECATED]
* Build latest Submariner E2E (test packages):       --build-e2e
* Download OCP Installer:                            --get-ocp-installer
* Specify OCP version:                               --ocp-version [x.x.x]
* Download latest OCPUP Tool:                        --get-ocpup-tool
* Download latest release of SubCtl:                 --get-subctl
* Download development release of SubCtl:            --get-subctl-devel
* Create AWS cluster A:                              --create-cluster-a
* Create OSP cluster B:                              --create-cluster-b
* Destroy existing AWS cluster A:                    --destroy-cluster-a
* Destroy existing OSP cluster B:                    --destroy-cluster-b
* Clean existing AWS cluster A:                      --clean-cluster-a
* Clean existing OSP cluster B:                      --clean-cluster-b
* Install Service-Discovery (lighthouse):            --service-discovery
* Install Global Net:                                --globalnet
* Use specific IPSec (cable driver):                 --cable-driver [libreswan / strongswan]
* Skip Submariner deployment:                        --skip-deploy
* Skip all tests execution:                          --skip-tests
* Install Golang if missing:                         --config-golang
* Install AWS-CLI and configure access:              --config-aws-cli
* Import additional variables from file:             --import-vars  [Variable file path]
* Record Junit Tests result (xml):                   --junit


Command examples:

$ ./setup_subm.sh

  Will run interactively (enter choices during execution).

$ ./setup_subm.sh --get-ocp-installer --ocp-version 4.4.6 --build-e2e --get-subctl --destroy-cluster-a --create-cluster-a --clean-cluster-b --service-discovery --globalnet --junit

  Will run:
  - New cluster on AWS (cluster A), with OCP 4.4.6
  - Clean existing cluster on OSP (cluster B)
  - Install latest Submariner release
  - Configure Service-Discovery and GlobalNet
  - Build and run latest E2E tests
  - Create Junit tests result (xml file)


----------------------------------------------------------------------'

####################################################################################

### Constants and external sources ###

# Set SCRIPT_DIR as current absolute path where this script runs in
export SCRIPT_DIR="$(dirname "$(realpath -s $0)")"

### Import Submariner setup variables ###
source "$SCRIPT_DIR/subm_variables"

### Import General Helpers Function ###
source "$SCRIPT_DIR/helper_functions"

# To trap inside functions
# set -T # might have issues with kubectl/oc commands

# To exit on error
set -e

# To expend aliases
shopt -s expand_aliases

# Date-time signature for log and report files
export DATE_TIME="$(date +%d%m%Y_%H%M)"

# Set script exit code in advance (saved in file)
export TEST_STATUS_RC="$SCRIPT_DIR/test_status.out"
echo 1 > $TEST_STATUS_RC

####################################################################################

### CLI Script inputs ###

check_cli_args() {
  [[ -n "$1" ]] || ( echo "# Missing arguments. Please see Help with: -h" && exit 1 )
}

shopt -s nocasematch # Case-insensitive match for string evaluations
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  export got_user_input=TRUE
  # Consume next (1st) argument
  case $1 in
  -h|--help)
    echo "# ${disclosure}" && exit 0
    shift ;;
  -d|--debug)
    export OC="${OC} -v=6" # verbose for oc commands
    shift ;;
  --get-ocp-installer)
    get_ocp_installer=YES
    shift ;;
  --ocp-version)
    check_cli_args "$2"
    export GET_OCP_VERSION="$2" # E.g as in https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
    shift 2 ;;
  --get-ocpup-tool)
    get_ocpup_tool=YES
    shift ;;
  --get-subctl)
    get_subctl=YES
    shift ;;
  --get-subctl-devel)
    get_subctl_devel=YES
    shift ;;
  --build-operator)
    build_operator=YES
    shift ;;
  --build-e2e)
    build_submariner_e2e=YES
    shift ;;
  --destroy-cluster-a)
    destroy_cluster_a=YES
    shift ;;
  --create-cluster-a)
    create_cluster_a=YES
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
    subm_cable_driver="--cable-driver $2" # libreswan OR strongswan
    shift 2 ;;
  --skip-deploy)
    skip_deploy=YES
    shift ;;
  --skip-tests)
    skip_tests=YES
    shift ;;
  --config-golang)
    config_golang=YES
    shift ;;
  --config-aws-cli)
    config_aws_cli=YES
    shift ;;
  --junit)
    junit_run="junit_run"
    shift ;;
  # -o|--optional-key-value)
  #   check_cli_args "$2"
  #   key="$2"
  #   [[ $key = x ]] && echo "Run x"
  #   [[ $key = y ]] && echo "Run y"
  #   shift 2 ;;
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

### Get User inputs, only for missing CLI inputs ###

if [[ -z "$got_user_input" ]]; then
  echo "# ${disclosure}"

  # User input: $get_ocp_installer - to download_ocp_installer
  while [[ ! "$get_ocp_installer" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to download OCP Installer ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    get_ocp_installer=${input:-no}
  done

  # User input: $GET_OCP_VERSION - to download_ocp_installer with specific version
  if [[ "$get_ocp_installer" =~ ^(yes|y)$ ]]; then
    while [[ ! "$GET_OCP_VERSION" =~ ^[0-9a-Z]+$ ]]; do
      echo -e "\n${YELLOW}Which OCP Installer version do you want to download ? ${NO_COLOR}
      Enter version number, or nothing to install latest version: "
      read -r input
      GET_OCP_VERSION=${input:-latest}
    done
  fi

  # User input: $get_ocpup_tool - to build_ocpup_tool_latest
  while [[ ! "$get_ocpup_tool" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to download OCPUP tool ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    get_ocpup_tool=${input:-no}
  done

  # User input: $create_cluster_a - to create_aws_cluster_a
  while [[ ! "$create_cluster_a" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to create AWS cluster A ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    create_cluster_a=${input:-no}
  done

  # User input: $destroy_cluster_a - to destroy_aws_cluster_a
  while [[ ! "$destroy_cluster_a" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to DESTROY AWS cluster A ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    destroy_cluster_a=${input:-no}
  done

  # User input: $clean_cluster_a - to clean_aws_cluster_a
  if [[ "$destroy_cluster_a" =~ ^(no|n)$ ]]; then
    while [[ ! "$clean_cluster_a" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to clean AWS cluster A ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      clean_cluster_a=${input:-no}
    done
  fi

  # User input: $destroy_cluster_b - to destroy_osp_cluster_b
  while [[ ! "$destroy_cluster_b" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to DESTROY OSP cluster B ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    destroy_cluster_b=${input:-no}
  done

  # User input: $create_cluster_b - to create_osp_cluster_b
  while [[ ! "$create_cluster_a" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to create OSP cluster B ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    create_cluster_b=${input:-no}
  done

  # User input: $clean_cluster_b - to clean_osp_cluster_b
  if [[ "$destroy_cluster_b" =~ ^(no|n)$ ]]; then
    while [[ ! "$clean_cluster_b" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to clean OSP cluster B ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      clean_cluster_b=${input:-no}
    done
  fi

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

  # User input: $build_operator - to build_operator_latest
  while [[ ! "$build_operator" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to pull Submariner-Operator repository (\"master\" branch) and build subctl ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    build_operator=${input:-no}
  done

  # User input: $get_subctl - to download_subctl_latest_release
  while [[ ! "$get_subctl" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to get the latest release of SubCtl ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    get_subctl=${input:-no}
  done

  # User input: $get_subctl_devel - to download_subctl_latest_devel
  while [[ ! "$get_subctl_devel" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to get the latest development of SubCtl (Submariner-Operator \"master\" branch) ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    get_subctl_devel=${input:-no}
  done

  # User input: $build_submariner_e2e - to build_submariner_e2e_latest
  while [[ ! "$build_submariner_e2e" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to pull and build latest Submariner repository (E2E tests) ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    build_submariner_e2e=${input:-YES}
  done

  # User input: $skip_deploy - to skip submariner deployment
  while [[ ! "$skip_deploy" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to run without deploying Submariner ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    skip_deploy=${input:-NO}
  done

  # User input: $skip_tests - to skip all test functions
  while [[ ! "$skip_tests" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to run without executing Submariner E2E and Unit-Tests ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    skip_tests=${input:-NO}
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

fi


### Set CLI/User inputs - Default to "NO" for any unset value ###

get_ocp_installer=${get_ocp_installer:-NO}
get_ocpup_tool=${get_ocpup_tool:-NO}
build_operator=${build_operator:-NO}
build_submariner_e2e=${build_submariner_e2e:-NO}
get_subctl=${get_subctl:-NO}
get_subctl_devel=${get_subctl_devel:-NO}
destroy_cluster_a=${destroy_cluster_a:-NO}
create_cluster_a=${create_cluster_a:-NO}
clean_cluster_a=${clean_cluster_a:-NO}
destroy_cluster_b=${destroy_cluster_b:-NO}
create_cluster_b=${create_cluster_b:-NO}
clean_cluster_b=${clean_cluster_b:-NO}
service_discovery=${service_discovery:-NO}
globalnet=${globalnet:-NO}


####################################################################################


### Main CI Functions ###

# ------------------------------------------

function print_test_plan() {
  PROMPT "Input parameters and Test Plan steps"

  if [[ "$skip_deploy" =~ ^(y|yes)$ ]]; then
    echo -e "\n# Skipping deployment and preparations: $skip_deploy \n"
  else
    echo "# Openshift clusters creation/cleanup before Submariner deployment:

    AWS cluster A (public):
    - destroy_aws_cluster_a: $destroy_cluster_a
    - create_aws_cluster_a: $create_cluster_a
    - clean_aws_cluster_a: $clean_cluster_a

    OSP cluster B (private):
    - destroy_osp_cluster_b: $destroy_cluster_b
    - create_osp_cluster_b: $create_cluster_b
    - clean_osp_cluster_b: $clean_cluster_b

    OCP and Submariner setup and test tools:
    - config_golang: $config_golang
    - config_aws_cli: $config_aws_cli
    - download_ocp_installer: $get_ocp_installer $GET_OCP_VERSION
    - build_ocpup_tool_latest: $get_ocpup_tool
    - build_operator_latest: $build_operator
    - build_submariner_e2e_latest: $build_submariner_e2e
    - download_subctl_latest_release: $get_subctl
    - download_subctl_latest_devel: $get_subctl_devel
    "

    echo -e "# Submariner deployment and environment setup for the tests:

    - test_kubeconfig_aws_cluster_a
    - test_kubeconfig_osp_cluster_b
    - test_subctl_command
    - install_netshoot_app_on_cluster_a
    - install_nginx_svc_on_cluster_b
    - test_basic_cluster_connectivity_before_submariner
    - test_clusters_disconnected_before_submariner
    - configure_aws_ports_for_submariner_broker ((\"prep_for_subm.sh\")
    - label_all_gateway_external_ip_cluster_a
    - label_first_gateway_cluster_b
    - install_broker_aws_cluster_a
    - join_submariner_cluster_a
    - join_submariner_cluster_b
    $([[ ! "$service_discovery" =~ ^(y|yes)$ ]] || echo "- test Service-Discovery")
    $([[ ! "$globalnet" =~ ^(y|yes)$ ]] || echo "- test globalnet") \
    "
  fi

  # TODO: Should add function to manipulate opetshift clusters yamls, to have overlapping CIDRs

  echo "# System and functional tests for Submariner:"
  if [[ "$skip_tests" =~ ^(y|yes)$ ]]; then
    echo -e "\n# Skipping tests: $skip_tests \n"
  else
    echo -e "\n
    - test_submariner_status_cluster_a
    - test_submariner_status_cluster_b
    - test_clusters_connected_by_service_ip
    - test_clusters_connected_overlapping_cidrs: $globalnet
    - test_clusters_connected_by_same_service_on_new_namespace: $service_discovery
    - verify_golang
    - test_submariner_packages
    - test_submariner_e2e_with_go
    - test_submariner_e2e_with_subctl
    "
  fi
}

# ------------------------------------------


function setup_workspace() {
  PROMPT "Creating workspace and verifying GO installation"
  # DONT trap_commands - Includes credentials, hide from output

  # Add HOME dir to PATH
  [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"
  mkdir -p $HOME/.local/bin

  # CD to main working directory
  mkdir -p ${WORKDIR}
  cd ${WORKDIR}

  # Installing if $config_golang = yes/y
  [[ ! "$config_golang" =~ ^(y|yes)$ ]] || install_local_golang "${WORKDIR}"

  # verifying GO installed, and set GOBIN to local directory in ${WORKDIR}
  export GOBIN="${WORKDIR}/GOBIN"
  mkdir -p "$GOBIN"
  verify_golang "$GOBIN"

  if [[ -e ${GOBIN} ]] ; then
    echo "# Re-exporting global variables"
    export OC="${GOBIN}/oc"
  fi

  # Installing if $config_aws_cli = yes/y
  [[ ! "$config_aws_cli" =~ ^(y|yes)$ ]] || ( configure_aws_access \
  "${AWS_PROFILE_NAME}" "${AWS_REGION}" "${AWS_KEY}" "${AWS_SECRET}" "${WORKDIR}" "${WORKDIR}/GOBIN")

  # Trim trailing and leading spaces from $SUBM_TEST_NS
  SUBM_TEST_NS="$(echo "$SUBM_TEST_NS" | xargs)"
}

# ------------------------------------------

function download_ocp_installer() {
### Download OCP installer ###
  PROMPT "Downloading OCP Installer $GET_OCP_VERSION"
  # The nightly builds available at: https://openshift-release-artifacts.svc.ci.openshift.org/
  trap_commands;

  # Optional param: $1 => $GET_OCP_VERSION (default = latest)
  ocp_major_version="$(echo "$1" | cut -s -d '.' -f 1)" # Get the major digit of OCP version
  ocp_major_version="${ocp_major_version:-4}" # if no major version was found (e.g. "latest"), the default OCP is 4
  GET_OCP_VERSION="${1:-latest}"

  cd ${WORKDIR}

  BUG "OCP 4.4.8 failure on generate asset \"Platform Permissions Check\"" \
  "Run OCP Installer 4.4.6 instead" \
  "https://bugzilla.redhat.com/show_bug.cgi?id=1850099"

  ocp_url="https://mirror.openshift.com/pub/openshift-v${ocp_major_version}/clients/ocp/${GET_OCP_VERSION}/"
  ocp_install_gz=$(curl $ocp_url | grep -Eoh "openshift-install-linux-.+\.tar\.gz" | cut -d '"' -f 1)
  oc_client_gz=$(curl $ocp_url | grep -Eoh "openshift-client-linux-.+\.tar\.gz" | cut -d '"' -f 1)

  echo "# Deleting previous OCP installers, and downloading: [$ocp_install_gz], [$oc_client_gz]."
  # find -type f -maxdepth 1 -name "openshift-*.tar.gz" -mtime +1 -exec rm -rf {} \;
  delete_old_files_or_dirs "openshift-*.tar.gz"

  download_file ${ocp_url}${ocp_install_gz}
  download_file ${ocp_url}${oc_client_gz}

  tar -xvf ${ocp_install_gz} -C ${WORKDIR}
  tar -xvf ${oc_client_gz} -C ${WORKDIR}

  echo "# Install OC - Openshift Client:"
  # sudo cp oc /usr/local/bin/
  # cp oc ~/.local/bin
  # cp oc ~/go/bin/

  mkdir -p $GOBIN
  # cp oc $GOBIN/
  /usr/bin/install ./oc $GOBIN/oc
  ${OC} -h
}

# ------------------------------------------

function build_ocpup_tool_latest() {
### Download OCPUP tool ###
  PROMPT "Downloading latest OCP-UP tool, and installing it to $GOBIN/ocpup"
  trap_commands;

  # TODO: Need to fix ocpup alias

  cd ${WORKDIR}
  # rm -rf ocpup # We should not remove directory, as it may included previous install config files
  git clone https://github.com/dimaunx/ocpup || echo "# OCPUP directory already exists"
  cd ocpup

  # To cleanup GOLANG mod files:
    # go clean -cache -modcache -i -r

  #git fetch && git reset --hard && git clean -fdx && git checkout --theirs . && git pull
  git fetch && git reset --hard && git checkout --theirs . && git pull

  echo "# Build OCPUP and install it to $GOBIN/"
  export GO111MODULE=on
  go mod vendor
  go install -mod vendor # Compile binary and moves it to $GOBIN
  # go build -mod vendor # Saves binary in current directory

  # Check OCPUP command
    # sudo ln -sf ocpup /usr/local/bin/ocpup
  which ocpup
    # ~/go/bin/ocpup

  ocpup  -h
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

function build_submariner_e2e_latest() {
### Building latest Submariner code and tests ###
  PROMPT "Building latest Submariner code, including test packages (unit-tests and E2E)"
  trap_commands;
  # Delete old Submariner directory
    # rm -rf $GOPATH/src/github.com/submariner-io/submariner

  # Download Submariner with go
    # export PATH=$PATH:$GOROOT/bin
  GO111MODULE="off" go get -v github.com/submariner-io/submariner/... || echo "# GO Get Submariner Engine finished."

  # Pull latest changes and build:
  cd $GOPATH/src/github.com/submariner-io/submariner
  ls

  #git fetch upstream && git checkout master && git pull upstream master
  # git fetch && git git pull --rebase
  git fetch && git reset --hard && git clean -fdx && git checkout --theirs . && git pull

  # make build # Will fail if Docker is not pre-installed
    # ...
    # Building submariner-engine version dev
    # ...
    # Building submariner-route-agent version dev
    # ...

  # ./scripts/build was removed in https://github.com/submariner-io/submariner/commit/0616258f163adfc368c0abfc3c405b5effb18390
    # ./scripts/build
    # ...
    # Building subctl version dev for linux/amd64
    # ...

  # Just build repo with go build
  export GO111MODULE=on
  go mod vendor
  # go install -mod vendor # Compile binary and moves it to $GOBIN
  go build -mod vendor # Saves binary in current directory

  #ls -l bin/submariner-engine
  ls -l test/e2e/
}

# ------------------------------------------

function build_operator_latest() {
### Building latest Submariner-Operator code and SubCTL tool ###
  PROMPT "Building latest Submariner-Operator code and SubCTL tool"
  trap_commands;

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
  # cp ./bin/subctl $GOBIN/
  /usr/bin/install ./bin/subctl $GOBIN/subctl

  # Create symbolic link /usr/local/bin/subctl :
  #sudo ln -sf $GOPATH/src/github.com/submariner-io/submariner-operator/bin/subctl /usr/local/bin/subctl
  #cp ./bin/subctl ~/.local/bin

}

# ------------------------------------------

function download_subctl_latest_release() {
  ### Download OCP installer ###
    PROMPT "Downloading latest release of Submariner-Operator tool - SubCtl"
    trap_commands;
    # TODO: curl -Ls  https://raw.githubusercontent.com/submariner-io/submariner-operator/master/scripts/subctl/getsubctl.sh | VERSION=rc bash

    cd ${WORKDIR}

    repo_url="https://github.com/submariner-io/submariner-operator"
    repo_tag="$(curl "$repo_url/tags/" | grep -Eoh 'tag/v[^"]+' -m 1)"
    releases_url="${repo_url}/releases"

    file_path="$(curl "${releases_url}/${repo_tag}" | grep -Eoh 'download\/.*\/subctl-.*-linux-amd64[^"]+' -m 1)"

    download_file "${releases_url}/${file_path}"

    file_name=$(basename -- "$file_path")
    tar -xvf ${file_name} --strip-components 1 --wildcards --no-anchored  "subctl*"

    # Rename last extracted file to subctl
    extracted_file="$(ls -1 -tu subctl* | head -1)"

    # BUG "${file_name} is not a TGZ archive, but a binary" \
    # "Do not extract the downloaded file [${file_name}], but rename instead to \"subctl\"" \
    # "https://github.com/submariner-io/submariner-operator/issues/257"

    [[ ! -e "$extracted_file" ]] || mv "$extracted_file" subctl
    chmod +x subctl

    echo "# Install subctl into ${GOBIN}:"
    mkdir -p $GOBIN
    # cp ./subctl $GOBIN/
    /usr/bin/install ./subctl $GOBIN/subctl

    echo "# Install subctl into user HOME bin:"
    # cp ./subctl ~/.local/bin/
    /usr/bin/install ./subctl ~/.local/bin/subctl

    echo "# Add user HOME bin to system PATH:"
    export PATH="$HOME/.local/bin:$PATH"
}

# ------------------------------------------

function download_subctl_latest_devel() {
  ### Download OCP installer ###
    PROMPT "Testing \"getsubctl.sh\" to download and install latest subctl-devel (built from Submariner-Operator \"master\" branch)"
    trap_commands;

    cd ${WORKDIR}

    BUG "getsubctl.sh fails on an unexpected argument, since the local 'install' is not the default" \
    "set 'PATH=/usr/bin:$PATH' for the execution of 'getsubctl.sh'" \
    "https://github.com/submariner-io/submariner-operator/issues/473"
    # Workaround:
    PATH="/usr/bin:$PATH" which install

    curl -Ls  https://raw.githubusercontent.com/submariner-io/submariner-operator/master/scripts/subctl/getsubctl.sh \
    | VERSION=devel PATH="/usr/bin:$PATH" bash -x || getsubctl_status=FAILED

    if [[ "$getsubctl_status" = FAILED ]] ; then
      BUG "getsubctl.sh sometimes fails on error 403 (rate limit exceeded)" \
      "Download directly with wget" \
      "https://github.com/submariner-io/submariner-operator/issues/526"
      # Workaround:

      repo_url="https://github.com/submariner-io/submariner-operator"
      repo_tag="$(curl "$repo_url/tags/" | grep -Eoh 'tag/dev[^"]+' -m 1)"
      releases_url="${repo_url}/releases"
      file_path="$(curl "${releases_url}/${repo_tag}" | grep -Eoh 'download\/.*\/subctl-.*-linux-amd64[^"]+' -m 1)"

      # BUG "getsubctl.sh pulls non-latest devel version" \
      # "Download subctl-v0.4.0-12-g0eb4ab8-linux-amd64.tar.xz" \
      # "https://github.com/submariner-io/submariner-operator/issues/520"
      # # Workround:
      # file_path="download/devel/subctl-v0.4.0-12-g0eb4ab8-linux-amd64.tar.xz"

      download_file "${releases_url}/${file_path}"

      file_name=$(basename -- "$file_path")
      tar -xvf ${file_name} --strip-components 1 --wildcards --no-anchored  "subctl*"

      # Rename last extracted file to subctl
      extracted_file="$(ls -1 -tu subctl* | head -1)"

      [[ ! -e "$extracted_file" ]] || mv "$extracted_file" subctl
      chmod +x subctl

      echo "# Install subctl into ${GOBIN}:"
      mkdir -p $GOBIN
      # cp ./subctl $GOBIN/
      /usr/bin/install ./subctl $GOBIN/subctl

      echo "# Install subctl into user HOME bin:"
      # cp ./subctl ~/.local/bin/
      /usr/bin/install ./subctl ~/.local/bin/subctl
    fi

    echo "# Copy subctl from user HOME bin into ${GOBIN}:"
    mkdir -p $GOBIN
    # cp ./subctl $GOBIN/
    /usr/bin/install "$HOME/.local/bin/subctl" $GOBIN/subctl

    echo "# Add user HOME bin to system PATH:"
    export PATH="$HOME/.local/bin:$PATH"

}

# ------------------------------------------

function test_subctl_command() {
  PROMPT "Verifying SubCTL (Submariner-Operator command line tool)"
  trap_commands;

  which subctl
  subctl version
  subctl --help

}

# ------------------------------------------

function create_aws_cluster_a() {
### Create AWS cluster A (public) with OCP installer ###
  PROMPT "Creating AWS cluster A (public) with OCP installer"
  trap_commands;
  # Using existing OCP install-config.yaml - make sure to have it in the workspace.

  BUG "OCP Install failure creating IAM Role worker-role" \
  "No workaround yet" \
  "https://bugzilla.redhat.com/show_bug.cgi?id=1846630"

  cd ${WORKDIR}

  if [[ -d "$CLUSTER_A_DIR" ]] && [[ -n `ls -A "$CLUSTER_A_DIR"` ]] ; then
    FATAL "$CLUSTER_A_DIR directory contains previous deployment configuration. It should be initially removed."
  fi

  mkdir -p "${CLUSTER_A_DIR}"
  cp "${CLUSTER_A_YAML}" "${CLUSTER_A_DIR}/install-config.yaml"

  # OR to create new OCP install-config.yaml:
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

  # Run OCP installer with the user-cluster-a.yaml:

    # This has a bug in bugzilla - using "--dir"
    # $ cd ..
    # $ ./openshift-install create install-config --dir user-cluster-a

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
### Create Openstack cluster B (private) with OCPUP tool ###
  PROMPT "Creating Openstack cluster B (private) with OCP-UP tool"
  trap_commands;

  cd "${OCPUP_DIR}"
  echo -e "# Using an existing OCPUP yaml configuration file: \n${CLUSTER_B_YAML}"
  # TODO: This YAML file should be copied from a secure path
  cp "${CLUSTER_B_YAML}" ./
  ocpup_yml=$(basename -- "$CLUSTER_B_YAML")
  ls -l "$ocpup_yml"

  # Run OCPUP to Create OpenStack cluster B (private)
  # ocpup  create clusters --debug --config "$ocpup_yml"
  ocpup  create clusters --config "$ocpup_yml" &
  pid=$!
  tail --pid=$pid -f --retry .config/cl1/.openshift_install.log &
  tail --pid=$pid -f /dev/null

  # To tail all OpenShift Installer logs (in a new session):
    # find . -name "*openshift_install.log" | xargs tail --pid=$pid -f # tail ocpup/.config/cl1/.openshift_install.log

  # Login to the new created cluster:
  # $ grep "Access the OpenShift web-console" -r . --include='*.log' -A 1
    # "Access the OpenShift web-console here: https://console-openshift-console.apps..."
    # "Login to the console with user: kubeadmin, password: ..."
}

# ------------------------------------------

function test_kubeconfig_aws_cluster_a() {
# Check that AWS cluster A (public) is up and running
  CLUSTER_A_VERSION=${CLUSTER_A_VERSION:+" (OCP Version $CLUSTER_A_VERSION)"}
  PROMPT "Testing that AWS cluster A${CLUSTER_A_VERSION} is up and running"
  trap_commands;

  kubconf_a;
  test_cluster_status
  export CLUSTER_A_VERSION=$(${OC} version | awk '/Server Version/ { print $3 }')
  # cd -
}

function kubconf_a() {
# Alias of KubeConfig for AWS cluster A (public) (AWS):
  trap_commands;
  export "KUBECONFIG=${KUBECONF_CLUSTER_A}";
}

# ------------------------------------------

function test_kubeconfig_osp_cluster_b() {
# Check that OSP cluster B (private) is up and running
  CLUSTER_B_VERSION=${CLUSTER_B_VERSION:+" (OCP Version $CLUSTER_B_VERSION)"}
  PROMPT "Testing that OSP cluster B${CLUSTER_B_VERSION} is up and running"
  trap_commands;

  kubconf_b;
  test_cluster_status
  export CLUSTER_B_VERSION=$(${OC} version | awk '/Server Version/ { print $3 }')
}

function kubconf_b() {
# Alias of KubeConfig for OSP cluster B (private) (OpenStack):
  trap_commands;
  export "KUBECONFIG=${KUBECONF_CLUSTER_B}";
}

# ------------------------------------------

function test_cluster_status() {
  # Verify that current kubeconfig cluster is up and healthy
  trap_commands;

  [[ -f ${KUBECONFIG} ]] || FATAL "Openshift deployment configuration is missing: ${KUBECONFIG}"

  # Set the default namespace to "${SUBM_TEST_NS}" (if SUBM_TEST_NS parameter was previously set)
  if [[ $SUBM_TEST_NS ]] ; then
    echo "# Backup current KUBECONFIG to: ${KUBECONFIG}.bak"
    cp "${KUBECONFIG}" "${KUBECONFIG}.bak"

    BUG "On OCP version < 4.4.6 : If running inside different cluster, OC can use wrong project name by default" \
    "Set the default namespace to \"${SUBM_TEST_NS}\"" \
    "https://bugzilla.redhat.com/show_bug.cgi?id=1826676"

    echo "# Create namespace for Submariner tests: ${SUBM_TEST_NS}"
    ${OC} create namespace "${SUBM_TEST_NS}" || : # || : to ignore none-zero exit code

    echo "# Change the default namespace in [${KUBECONFIG}] to: ${SUBM_TEST_NS}"
    cur_context="$(${OC} config current-context)"
    ${OC} config set "contexts.${cur_context}.namespace" "${SUBM_TEST_NS}"
  else
    export SUBM_TEST_NS=default
  fi

  ${OC} version
  ${OC} config view
  ${OC} status
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

  # Only if your AWS cluster still exists (less than 48 hours passed) - run destroy command:
  # TODO: should first check if it was not already purged, because it can save a lot of time.
  if [[ -d "${CLUSTER_A_DIR}" ]]; then
    echo "# Previous OCP Installation found: ${CLUSTER_A_DIR}"
    # cd "${CLUSTER_A_DIR}"
    if [[ -f "${CLUSTER_A_DIR}/metadata.json" ]] ; then
      echo "# Destroying OCP cluster ${CLUSTER_A_NAME}:"
      timeout 10m ./openshift-install destroy cluster --log-level debug --dir "${CLUSTER_A_DIR}" || \
      ( [[ $? -eq 124 ]] && \
      BUG "WARNING: OCP destroy timeout exceeded - loop state while searching for hosted zone." \
      "Force exist OCP destroy process, or use OCP version 4.5" \
      "https://bugzilla.redhat.com/show_bug.cgi?id=1817201" )
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

  # To remove YOUR DNS record sets from Route53:
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
### If Required - Destroy your previous Openstack cluster B (private) ###
  PROMPT "Destroying previous Openstack cluster B (private)"
  trap_commands;

  cd "${OCPUP_DIR}"
  if [[ -f "${CLUSTER_B_DIR}/metadata.json" ]] ; then
    echo -e "# Using an existing OCPUP yaml configuration file: \n${CLUSTER_B_YAML}"
    # TODO: This YAML file should be copied from a secure path
    cp "${CLUSTER_B_YAML}" ./
    ocpup_yml=$(basename -- "$CLUSTER_B_YAML")
    ls -l "$ocpup_yml"

    # ocpup  destroy clusters --debug --config "$ocpup_yml"
    ocpup  destroy clusters --config "$ocpup_yml" & # running on the background (with timeout)
    pid=$! # while the background process runs, tail its log
    # tail --pid=$pid -f .config/cl1/.openshift_install.log && tail -f /proc/$pid/fd/1

    # Wait until the background process finish
    #tail --pid=$pid -f --retry ${OCPUP_DIR}/.config/cl1/.openshift_install.log &
    #tail --pid=$pid -f /dev/null # wait until the background process finish

    timeout --foreground 20m tail --pid=$pid -f --retry "${OCPUP_DIR}/.config/cl1/.openshift_install.log"

    # To tail all OpenShift Installer logs (in a new session):
      # find . -name "*openshift_install.log" | xargs tail --pid=$pid -f # tail ocpup/.config/cl1/.openshift_install.log

    echo "# Backup previous OCP install-config directory of cluster ${CLUSTER_B_NAME} "
    backup_and_remove_dir ".config"
  else
    echo "# OCP cluster config (metadata.json) was not found in ${CLUSTER_B_DIR}. Skipping cluster Destroy."
  fi
}


# ------------------------------------------

function clean_aws_cluster_a() {
### Run cleanup of previous Submariner on AWS cluster A (public) ###
  PROMPT "Cleaning previous Submariner (Namespace objects, OLM, CRDs, ServiceExports) on AWS cluster A (public)"
  kubconf_a;
  delete_submariner_namespace_and_crds;

  PROMPT "Remove previous Submariner Gateway labels (if exists) on AWS cluster A (public)"

  BUG "If one of the gateway nodes does not have external ip, submariner will fail to connect later" \
  "Make sure only 1 node has a gateway label" \
  "https://github.com/submariner-io/submariner-operator/issues/253"
  remove_submariner_gateway_labels

  BUG "Submariner gateway label cannot be removed once created" \
  "No Resolution yet" \
  "https://github.com/submariner-io/submariner/issues/432"
}

# ------------------------------------------

function clean_osp_cluster_b() {
### Run cleanup of previous Submariner on OSP cluster B (private) ###
  PROMPT "Cleaning previous Submariner (Namespace objects, OLM, CRDs, ServiceExports) on OSP cluster B (private)"
  kubconf_b;
  delete_submariner_namespace_and_crds;

  PROMPT "Remove previous Submariner Gateway labels (if exists) on OSP cluster B (private)"
  remove_submariner_gateway_labels
}

# ------------------------------------------

function delete_submariner_namespace_and_crds() {
### Run cleanup of previous Submariner on current KUBECONFIG cluster ###
  trap_commands;

  BUG "Deploying broker will fail if previous submariner-operator namespaces and CRDs already exist" \
  "Run cleanup (oc delete) of any existing resource of submariner-operator" \
  "https://github.com/submariner-io/submariner-operator/issues/88"

  delete_namespace_and_crds "${SUBM_NAMESPACE}" "submariner"

  # Required if Broker cluster is not a Dataplane cluster as well:
  # delete_namespace_and_crds "submariner-k8s-broker"

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

function remove_submariner_gateway_labels() {
  trap_commands;

  # Remove previous submariner gateway labels from all node in the cluster:
  ${OC} label --all node submariner.io/gateway-

}

# ------------------------------------------

function install_netshoot_app_on_cluster_a() {
  PROMPT "Install Netshoot application on AWS cluster A (public)"
  trap_commands;

  kubconf_a;

  ${OC} delete pod ${NETSHOOT_CLUSTER_A}  --ignore-not-found ${SUBM_TEST_NS:+-n $SUBM_TEST_NS}

  if [[ -n $SUBM_TEST_NS ]] ; then
    # ${OC} delete --timeout=30s namespace "${SUBM_TEST_NS}" --ignore-not-found || : # || : to ignore none-zero exit code
    delete_namespace_and_crds "${SUBM_TEST_NS}"
    ${OC} create namespace "${SUBM_TEST_NS}" || : # || : to ignore none-zero exit code
  fi

  # NETSHOOT_CLUSTER_A=netshoot-cl-a # Already exported in global subm_variables

  # Deployment is terminated after netshoot is loaded - need to "oc run" with infinite loop
  # ${OC} delete deployment ${NETSHOOT_CLUSTER_A}  --ignore-not-found ${SUBM_TEST_NS:+-n $SUBM_TEST_NS}
  # ${OC} create deployment ${NETSHOOT_CLUSTER_A}  --image nicolaka/netshoot ${SUBM_TEST_NS:+-n $SUBM_TEST_NS}
  ${OC} run ${NETSHOOT_CLUSTER_A} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} --image nicolaka/netshoot --generator=run-pod/v1 -- sleep infinity

  echo "# Wait up to 3 minutes for Netshoot pod [${NETSHOOT_CLUSTER_A}] to be ready:"
  ${OC} wait --timeout=3m --for=condition=ready pod -l run=${NETSHOOT_CLUSTER_A} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS}
  ${OC} describe pod  ${NETSHOOT_CLUSTER_A} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS}
}

# ------------------------------------------

function install_nginx_svc_on_cluster_b() {
  PROMPT "Install Ngnix service on OSP cluster B${SUBM_TEST_NS:+ (Namespace $SUBM_TEST_NS)}"
  trap_commands;

  kubconf_b;

  install_nginx_service "${NGINX_CLUSTER_B}" "${SUBM_TEST_NS}"

}

# ------------------------------------------

function test_basic_cluster_connectivity_before_submariner() {
### Pre-test - Demonstrate that the clusters aren’t connected without Submariner ###
  PROMPT "Before Submariner is installed:
  Verifying connectivity on the same cluster, from Netshoot to Nginx service"
  trap_commands;

  # Trying to connect from cluster A to cluster B, will fails (after 5 seconds).
  # It’s also worth looking at the clusters to see that Submariner is nowhere to be seen.

  kubconf_b;
  netshoot_pod=netshoot-cl-b-new # A new Netshoot pod on cluster b
  nginx_IP_cluster_b=$(${OC} get svc -l app=${NGINX_CLUSTER_B} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} | awk 'FNR == 2 {print $3}')
    # nginx_cluster_b_ip: 100.96.43.129

  echo "# Install Netshoot on OSP cluster B, and verify connectivity to $nginx_IP_cluster_b:8080 on the SAME cluster"

  ${OC} delete pod ${netshoot_pod} --ignore-not-found ${SUBM_TEST_NS:+-n $SUBM_TEST_NS}

  ${OC} run ${netshoot_pod} --attach=true --restart=Never --pod-running-timeout=1m --request-timeout=1m --rm -i \
  ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} --image nicolaka/netshoot -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_IP_cluster_b}:8080"
}

# ------------------------------------------

function test_clusters_disconnected_before_submariner() {
### Pre-test - Demonstrate that the clusters aren’t connected without Submariner ###
  PROMPT "Before Submariner is installed:
  Verifying that Netshoot pod on AWS cluster A (public), cannot reach Nginx service on OSP cluster B (private)"
  trap_commands;

  # Trying to connect from cluster A to cluster B, will fails (after 5 seconds).
  # It’s also worth looking at the clusters to see that Submariner is nowhere to be seen.

  kubconf_b;
  # nginx_IP_cluster_b=$(${OC} get svc -l app=${NGINX_CLUSTER_B} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} | awk 'FNR == 2 {print $3}')
  ${OC} get svc -l app=${NGINX_CLUSTER_B} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} | awk 'FNR == 2 {print $3}' > "$TEMP_FILE"
  nginx_IP_cluster_b="$(< $TEMP_FILE)"
    # nginx_cluster_b_ip: 100.96.43.129

  kubconf_a;
  # netshoot_pod_cluster_a=$(${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')
  ${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} --field-selector status.phase=Running | awk 'FNR == 2 {print $1}' > "$TEMP_FILE"
  netshoot_pod_cluster_a="$(< $TEMP_FILE)"

  msg="# Negative Test - Clusters should NOT be able to connect without Submariner"

  ${OC} exec $netshoot_pod_cluster_a ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} -- \
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

  # Installing Terraform
  install_local_terraform "${WORKDIR}"

  kubconf_a;
  cd "${CLUSTER_A_DIR}"

  curl -LO https://github.com/submariner-io/submariner/raw/master/tools/openshift/ocp-ipi-aws/prep_for_subm.sh
  chmod a+x ./prep_for_subm.sh

  BUG "prep_for_subm.sh should work silently (without manual intervention to approve terraform action)" \
  "Modify prep_for_subm.sh with \"terraform apply -auto-approve" \
  "https://github.com/submariner-io/submariner/issues/241"
  sed 's/terraform apply/terraform apply -auto-approve/g' -i ./prep_for_subm.sh

  BUG "prep_for_subm.sh should accept custom ports for the gateway nodes" \
  "Modify file ec2-resources.tf, and change ports 4500 & 500 to $BROKER_NATPORT & $BROKER_IKEPORT" \
  "https://github.com/submariner-io/submariner/issues/240"
  [[ -f ./ocp-ipi-aws/ocp-ipi-aws-prep/ec2-resources.tf ]] || ./prep_for_subm.sh
  sed "s/500/$BROKER_IKEPORT/g" -i ./ocp-ipi-aws/ocp-ipi-aws-prep/ec2-resources.tf

  # Run prep_for_subm script to apply ec2-resources.tf:
  ./prep_for_subm.sh
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

function label_all_gateway_external_ip_cluster_a() {
### Label a Gateway node on AWS cluster A (public) ###
  PROMPT "Adding Gateway label to all worker nodes with an external ip on AWS cluster A (public)"
  kubconf_a;
  # TODO: Check that the Gateway label was created with "prep_for_subm.sh" on AWS cluster A (public) ?
  gateway_label_all_nodes_external_ip
}

function label_first_gateway_cluster_b() {
### Label a Gateway node on OSP cluster B (private) ###
  PROMPT "Adding Gateway label to the first worker node on OSP cluster B (private)"
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
### Adding submariner gateway label to all worker nodes with an external IP ###
  trap_commands;

  # Filter all node names that have external IP (column 7 is not none), and ignore header fields
  # Run 200 attempts, and wait for output to include regex of IPv4
  watch_and_retry "${OC} get nodes -l node-role.kubernetes.io/worker -o wide | awk '{print \$7}'" 200 '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'

  gw_nodes=$(${OC} get nodes -l node-role.kubernetes.io/worker -o wide | awk '$7!="<none>" && NR>1 {print $1}')
  # ${OC} get nodes -l node-role.kubernetes.io/worker -o wide | awk '$7!="<none>" && NR>1 {print $1}' > "$TEMP_FILE"
  # gw_nodes="$(< $TEMP_FILE)"
  echo "# Adding submariner gateway label to all worker nodes with an external IP: $gw_nodes"
    # gw_nodes: user-cl1-bbmkg-worker-8mx4k

  [[ -n "$gw_nodes" ]] || FATAL "EXTERNAL-IP was not created yet (by \"prep_for_subm.sh\" script)"

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
  cd ${WORKDIR}
  #cd $GOPATH/src/github.com/submariner-io/submariner-operator

  rm broker-info.subm.* || echo "# Previous ${BROKER_INFO} already removed"

  DEPLOY_CMD="subctl deploy-broker "

  # Deploys the CRDs, creates the SA for the broker, the role and role bindings
  kubconf_a;

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
    BUG "Running subctl with GlobalNet can fail if glabalnet_cidr address is already assigned" \
    "Define a new and unique globalnet-cidr for this cluster" \
    "https://github.com/submariner-io/submariner/issues/544"

    PROMPT "Adding GlobalNet to Submariner Deploy command"
    # DEPLOY_CMD="${DEPLOY_CMD} --globalnet --globalnet-cidr 169.254.0.0/19"
    DEPLOY_CMD="${DEPLOY_CMD} --globalnet"
  fi

  PROMPT "Deploying Submariner Broker and joining cluster A"
  echo "# Executing: ${DEPLOY_CMD}"
  $DEPLOY_CMD

  ${OC} -n ${SUBM_NAMESPACE} get pods |& (! highlight "CrashLoopBackOff") || submariner_status=DOWN

  # Now looking at cluster A shows that the Submariner broker namespace has been created:
  ${OC} get crds | grep -E 'submariner|lighthouse'
      # clusters.submariner.io                                      2019-12-03T16:45:57Z
      # endpoints.submariner.io                                     2019-12-03T16:45:57Z

  [[ "$submariner_status" != DOWN ]] || FATAL "Submariner pod has Crashed - check its logs"
}

# ------------------------------------------

function join_submariner_cluster_a() {
# Join Submariner member - AWS cluster A (public)
  PROMPT "Joining cluster A to Submariner Broker (also on cluster A), and verifying CRDs"
  kubconf_a;
  join_submariner_current_cluster "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function join_submariner_cluster_b() {
# Join Submariner member - OSP cluster B (private)
  PROMPT "Joining cluster B to Submariner Broker (on cluster A), and verifying CRDs"
  kubconf_b;
  join_submariner_current_cluster "${CLUSTER_B_NAME}"

}

# ------------------------------------------

function join_submariner_current_cluster() {
# Join Submariner member - of current cluster kubeconfig
  trap_commands;
  current_cluster_context_name="$1"

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
  # ${OC} config view --flatten > ${MERGED_KUBCONF}

  ${OC} config view

  BUG "Libreswan cable-driver cannot be used with IPSec ports 501 and 4501" \
   "Make sure subctl join used \"--cable-driver strongswan\" (it should be the default for Subctl 0.4)" \
  "https://github.com/submariner-io/submariner/issues/683"
  #Workaround:
  # Use strongswan as in u/s, instead of libreswan

  JOIN_CMD="subctl join --clusterid ${current_cluster_context_name} \
  ./${BROKER_INFO} ${subm_cable_driver} \
  --ikeport ${BROKER_IKEPORT} --nattport ${BROKER_NATPORT}"

  if [[ "$globalnet" =~ ^(y|yes)$ ]]; then
    PROMPT "Adding GlobalNet to Submariner Join command for cluster ${current_cluster_context_name}"

    BUG "Running subctl with GlobalNet can fail if glabalnet_cidr address is already assigned" \
    "Define a new and unique globalnet-cidr for each cluster, or add a wait (30 seconds)" \
    "https://github.com/submariner-io/submariner-operator/issues/299"
    # Workaround
    sleep 30s
    # JOIN_CMD="${JOIN_CMD} --globalnet-cidr 169.254.32.0/19" # or 169.254.0.0/19
  fi

  # subctl --subm-debug ${JOIN_CMD}
  BUG "--subm-debug cannot be used before join argument in subctl command" \
  "Add --subm-debug at the end only" \
  "https://github.com/submariner-io/submariner-operator/issues/340"
  # Workaround:
  JOIN_CMD="${JOIN_CMD} --subm-debug"
  echo "# Executing: ${JOIN_CMD}"
  $JOIN_CMD

  PROMPT "Testing that Submariner CRDs created on cluster ${current_cluster_context_name}"
  ${OC} get crds | grep submariners
      # ...
      # submariners.submariner.io                                   2019-11-28T14:09:56Z

  # Print details of the Operator in OSP cluster B (private), and in the Broker cluster:
  ${OC} get namespace ${SUBM_NAMESPACE} -o json

  ${OC} get Submariner -n ${SUBM_NAMESPACE} -o yaml

}


# ------------------------------------------

function test_submariner_status_cluster_a() {
# Operator pod status on AWS cluster A (public)
  PROMPT "Testing Submariner engine on AWS cluster A (public)"
  kubconf_a;
  test_submariner_engine_status "${CLUSTER_A_NAME}"
}

# ------------------------------------------

function test_submariner_status_cluster_b() {
# Operator pod status on OSP cluster B (private)
  PROMPT "Testing Submariner engine on OSP cluster B (private)"

  kubconf_b;
  test_submariner_engine_status  "${CLUSTER_B_NAME}"
}


# ------------------------------------------

function collect_submariner_info() {
  # print submariner pods descriptions and logs
  # Ref: https://github.com/submariner-io/shipyard/blob/master/scripts/shared/post_mortem.sh

  PROMPT "Collecting Submariner pods logs due to test failure" "$RED"
  df -h
  free -h
  ${OC} get all -n ${SUBM_NAMESPACE} || :
  ${OC} describe cm -n openshift-dns || :
  ${OC} get pods -n ${SUBM_NAMESPACE} --show-labels || :
  ${OC} get clusters -n ${SUBM_NAMESPACE} -o wide || :
  # TODO: Loop on each cluster: ${OC} describe cluster "${cluster_name}" -n ${SUBM_NAMESPACE} || :

  # submariner_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-engine -o jsonpath="{.items[0].metadata.name}")
  # ${OC} describe pod $submariner_pod -n ${SUBM_NAMESPACE} || :
  # ${OC} logs $submariner_pod -n ${SUBM_NAMESPACE} |& highlight "received packet" || :
  ${OC} get Submariner -o yaml -n ${SUBM_NAMESPACE} || :
  ${OC} get deployments -o yaml -n ${SUBM_NAMESPACE} || :
  # ${OC} get pods -o yaml -n ${SUBM_NAMESPACE} || :

  subctl show networks || :
  ${OC} describe Gateway -n ${SUBM_NAMESPACE} || :

  # for pod in $(${OC} get pods -A \
  # -l 'name in (submariner-operator,submariner-engine,submariner-globalnet,kube-proxy)' \
  # -o jsonpath='{.items[0].metadata.namespace} {.items[0].metadata.name}' ; do
  #     echo "######################: Logs for Pod $pod :######################"
  #     ${OC}  -n $ns describe pod $name
  #     ${OC}  -n $namespace logs $pod
  # done

  echo -e "\n#########################################################################################\n"

  local namespace="${SUBM_NAMESPACE}"
  for pod in $(${OC} get pods -l app=submariner-engine -n $namespace -o jsonpath='{.items[*].metadata.name}'); do
      echo "######################: Logs Submariner Engine pod $pod in namespace $namespace :######################"
      ${OC} -n $namespace describe pod $pod || :
      ${OC} -n $namespace logs $pod || :
  done

  for pod in $(${OC} get pods -l app=submariner-globalnet -n $namespace -o jsonpath='{.items[*].metadata.name}'); do
      echo "######################: Logs for Submariner Globalnet pod $pod in namespace $namespace :######################"
      ${OC} -n $namespace describe pod $pod || :
      ${OC} -n $namespace logs $pod || :
  done

  echo -e "\n#########################################################################################\n"

  namespace="kube-system"
  for pod in $(${OC} get pods -l k8s-app=kube-proxy -n $namespace -o jsonpath='{.items[*].metadata.name}'); do
      echo "######################: Logs for Kube Proxy pod $pod in namespace $namespace :######################"
      ${OC} -n $namespace describe pod $pod || :
      ${OC} -n $namespace logs $pod || :
  done

  echo -e "\n#########################################################################################\n"
}

# ------------------------------------------

function test_submariner_engine_status() {
# Check submariner-engine on the Operator pod
  trap_commands;
  cluster_name="$1"
  # ns_name="submariner-operator"

  PROMPT "Testing Submariner Operator resources on ${cluster_name}"

  ${OC} get all -n ${SUBM_NAMESPACE} |& (! highlight "No resources found") \
  || FATAL "Error: Submariner is not installed on $cluster_name"

  # submariner_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-engine -o jsonpath="{.items[0].metadata.name}")
  ${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-engine -o jsonpath="{.items[0].metadata.name}" > "$TEMP_FILE"
  submariner_pod="$(< $TEMP_FILE)"

  if [[ -z "${subm_cable_driver}" || "${subm_cable_driver}" =~ strongswan ]] ; then
    PROMPT "Testing Submariner StrongSwan (cable driver) on ${cluster_name}"
    BUG "strongswan status exit code 3, even when \"security associations\" is up" \
    "Ignore non-zero exit code, by redirecting stderr" \
    "https://github.com/submariner-io/submariner/issues/360"

    cmd="${OC} exec $submariner_pod -n ${SUBM_NAMESPACE} strongswan stroke statusall"
    regex='Security Associations \(1 up'
    # Run up to 30 retries (+ 10 seconds interval between retries), and watch for output to include regex
    watch_and_retry "$cmd" 30 "$regex" || submariner_status=DOWN
      # Security Associations (1 up, 0 connecting):
      # submariner-cable-subm-cluster-a-10-0-89-164[1]: ESTABLISHED 11 minutes ago, 10.166.0.13[66.187.233.202]...35.171.45.208[35.171.45.208]
      # submariner-child-submariner-cable-subm-cluster-a-10-0-89-164{1}:  INSTALLED, TUNNEL, reqid 1, ESP in UDP SPIs: c9cfd847_i cddea21b_o
      # submariner-child-submariner-cable-subm-cluster-a-10-0-89-164{1}:   10.166.0.13/32 10.252.0.0/14 100.96.0.0/16 === 10.0.89.164/32 10.128.0.0/14 172.30.0.0/16

    BUG "StrongSwan connecting to 'default' URI fails" \
    "Verify StrongSwan with different URI path and ignore failure" \
    "https://github.com/submariner-io/submariner/issues/426"
    # ${OC} exec $submariner_pod -n ${SUBM_NAMESPACE} -- bash -c "swanctl --list-sas"
    # workaround:
    ${OC} exec $submariner_pod -n ${SUBM_NAMESPACE} -- bash -c "swanctl --list-sas --uri unix:///var/run/charon.vici" |& (! highlight "CONNECTING, IKEv2" ) || submariner_status=UP

  elif [[ "${subm_cable_driver}" =~ libreswan ]] ; then
    PROMPT "Testing Submariner LibreSwan (cable driver) on ${cluster_name}"
    # TODO: Check LibreSwan pod status with watch_and_retry
    sleep 2m
  fi

  PROMPT "Check HA status and IPSEC tunnel of Submariner Gateways on ${cluster_name}"
  # ${OC} describe Gateway -n ${SUBM_NAMESPACE} |& highlight "Ha Status:\s*active" || submariner_status=DOWN

  ${OC} describe Gateway -n ${SUBM_NAMESPACE} > "$TEMP_FILE"

  if highlight "Ha Status:\s*passive|Status Failure\s*\w+" "$TEMP_FILE" ; then
     submariner_status=DOWN
  else
    submariner_status=UP
  fi

  # Get some info on installed CRDs
  # subctl info # Removed since https://github.com/submariner-io/submariner-operator/issues/467
  subctl show networks || :
  ${OC} describe cm -n openshift-dns
  ${OC} get pods -n ${SUBM_NAMESPACE} --show-labels
  ${OC} get clusters -n ${SUBM_NAMESPACE} -o wide
  ${OC} describe cluster "${cluster_name}" -n ${SUBM_NAMESPACE} || submariner_status=DOWN

  if [[ "$globalnet" =~ ^(y|yes)$ ]]; then
    PROMPT "Testing GlobalNet controller status on ${cluster_name}"
    test_globalnet_status || submariner_status=DOWN
  fi

  if [[ "$service_discovery" =~ ^(y|yes)$ ]] ; then
    PROMPT "Testing Lighthouse agent status on ${cluster_name}"
    test_lighthouse_status || submariner_status=DOWN
  fi

  if [[ "$submariner_status" = DOWN ]]; then
  # if receiving: "Security Associations (0 up, 0 connecting)", we need to check Operator pod logs:
  # || : to ignore none-zero exit code
    ${OC} logs $submariner_pod -n ${SUBM_NAMESPACE} |& highlight "received packet" || :
    ${OC} describe pod $submariner_pod -n ${SUBM_NAMESPACE} || :
    ${OC} get Submariner -o yaml || :
    ${OC} get deployments -o yaml -n ${SUBM_NAMESPACE} || :
    ${OC} get pods -o yaml -n ${SUBM_NAMESPACE} || :
    FATAL "Error: Submariner clusters are not connected."
  fi
}

# ------------------------------------------

function test_lighthouse_status() {
  # Check Lighthouse (the pod for service-discovery) status
  trap_commands;

  ${OC} describe multiclusterservices --all-namespaces

  lighthouse_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-lighthouse-agent -o jsonpath="{.items[0].metadata.name}")

  echo "# Tailing logs in Lighthouse pod [$lighthouse_pod] to verify Service-Discovery sync with Broker"
  # ${OC} logs $lighthouse_pod -n ${SUBM_NAMESPACE} |& highlight "Lighthouse agent syncer started"

  cmd="${OC} logs --tail 100 $lighthouse_pod -n ${SUBM_NAMESPACE}"
  regex="Lighthouse agent syncer started"
  # Run up to 3 minutes (+ 10 seconds interval between retries), and watch for output to include regex
  watch_and_retry "$cmd" 5m "$regex"

  # TODO: Can also test app=submariner-lighthouse-coredns  for the lighthouse DNS status
}

# ------------------------------------------

function test_globalnet_status() {
  # Check Globalnet controller pod status
  trap_commands;

  globalnet_pod=$(${OC} get pod -n ${SUBM_NAMESPACE} -l app=submariner-globalnet -o jsonpath="{.items[0].metadata.name}")

  echo "# Tailing logs in GlobalNet pod [$globalnet_pod] to verify it allocates Global IPs to cluster services"

  cmd="${OC} logs --tail 100 $globalnet_pod -n ${SUBM_NAMESPACE}"
  regex="Allocating globalIp"
  # Run up to 3 minutes (+ 10 seconds interval between retries), and watch for output to include regex
  watch_and_retry "$cmd" 3m "$regex"

  PROMPT "Testing Gateway health (no restarts) on ${cluster_name}" # TODO: Should be tested on a seperate function, not related to Globalnet
  echo "# Tailing logs in GlobalNet pod [$globalnet_pod], to see if Endpoints were removed (due to Submariner Gateway restarts)"
  ${OC} logs $globalnet_pod -n ${SUBM_NAMESPACE} |& (! highlight "remove endpoint")

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
  GLOBAL_IP=$($cmd | grep "$globalnet_tag" | grep -Eoh "$ipv4_regex")
}

# ------------------------------------------

function test_clusters_connected_by_service_ip() {
  PROMPT "After Submariner is installed:
  Identify Netshoot pod on cluster A, and Nginx service on cluster B"
  trap_commands;

  kubconf_a;
  # netshoot_pod_cluster_a=$(${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')
  ${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} --field-selector status.phase=Running | awk 'FNR == 2 {print $1}' > "$TEMP_FILE"
  netshoot_pod_cluster_a="$(< $TEMP_FILE)"
  echo "# NETSHOOT_CLUSTER_A: $NETSHOOT_CLUSTER_A"
    # netshoot-785ffd8c8-zv7td

  kubconf_b;
  echo "${OC} get svc -l app=${NGINX_CLUSTER_B} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} | awk 'FNR == 2 {print $3}')"
  # nginx_IP_cluster_b=$(${OC} get svc -l app=${NGINX_CLUSTER_B} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} | awk 'FNR == 2 {print $3}')
  ${OC} get svc -l app=${NGINX_CLUSTER_B} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} | awk 'FNR == 2 {print $3}' > "$TEMP_FILE"
  nginx_IP_cluster_b="$(< $TEMP_FILE)"
  echo "# Nginx service on cluster B, will be identified by its IP (without --service-discovery): $nginx_IP_cluster_b:8080"
    # nginx_IP_cluster_b: 100.96.43.129

  kubconf_a;
  CURL_CMD="${SUBM_TEST_NS:+-n $SUBM_TEST_NS} ${netshoot_pod_cluster_a} -- curl --output /dev/null --max-time 30 --verbose ${nginx_IP_cluster_b}:8080"

  if [[ ! "$globalnet" =~ ^(y|yes)$ ]] ; then
    PROMPT "Testing connection without GlobalNet: From Netshoot on AWS cluster A (public), to Nginx service IP on OSP cluster B (private)"
    ${OC} exec ${CURL_CMD} || \
    BUG "TODO: This will if fail the clusters have Overlapping CIDRs, while Submariner was not deployed with --globalnet"
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

    ${OC} exec ${CURL_CMD} |& (! highlight "Connection timed out" && FATAL "$msg") || echo -e "$msg"
  fi
}

# ------------------------------------------

function test_clusters_connected_overlapping_cidrs() {
### Run Connectivity tests between the Private and Public clusters ###
# To validate that now Submariner made the connection possible!
  PROMPT "Testing GlobalNet annotation - Nginx service on OSP cluster B (private) should get a GlobalNet IP"
  trap_commands;

  kubconf_b;

  BUG "When you create a pod/service, GN Controller gets notified about the Pod/Service notification
   and then it annotates and programs - this could add delay to the GlobalNet use-cases." \
   "Wait up to 3 minutes before checking connectivity with GlobalNet on overlapping clusters CIDRs" \
  "https://github.com/submariner-io/submariner/issues/588"
  # Workaround:

  # Should fail if NGINX_CLUSTER_B was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_svc_pod_global_ip_created svc "$NGINX_CLUSTER_B" $SUBM_TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on Ngnix service (${NGINX_CLUSTER_B}${SUBM_TEST_NS:+.$SUBM_TEST_NS})"
  nginx_global_ip="$GLOBAL_IP"

  PROMPT "Testing GlobalNet annotation - Netshoot pod on AWS cluster A (public) should get a GlobalNet IP"
  kubconf_a;
  netshoot_pod_cluster_a=$(${OC} get pods -l run=${NETSHOOT_CLUSTER_A} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} \
  --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')

  # Should fail if netshoot_pod_cluster_a was not annotated with GlobalNet IP
  GLOBAL_IP=""
  test_svc_pod_global_ip_created pod "$netshoot_pod_cluster_a" $SUBM_TEST_NS
  [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on Netshoot Pod (${netshoot_pod_cluster_a}${SUBM_TEST_NS:+ in $SUBM_TEST_NS})"

  # TODO: Ping to the netshoot_global_ip
  # netshoot_global_ip="$GLOBAL_IP"

  PROMPT "Testing GlobalNet connectivity - From Netshoot pod ${netshoot_pod_cluster_a} (IP ${netshoot_global_ip}) on cluster A
  To Nginx service on cluster B, by its Global IP: $nginx_global_ip:8080"

  kubconf_a;
  ${OC} exec ${netshoot_pod_cluster_a} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} \
  -- curl --output /dev/null --max-time 30 --verbose ${nginx_global_ip}:8080

  #TODO: validate annotation of globalIp in the node
}

# ------------------------------------------

function test_clusters_connected_by_same_service_on_new_namespace() {
### Nginx service on cluster B, will be identified by its Domain Name, with --service-discovery ###
  trap_commands;

  new_netshoot_cluster_a=netshoot-cl-a-new # A NEW Netshoot pod on cluster A
  new_subm_test_ns=${SUBM_TEST_NS:+${SUBM_TEST_NS}-new} # A NEW Namespace on cluster B
  new_nginx_cluster_b=${NGINX_CLUSTER_B} # NEW Ngnix service BUT with the SAME name as $NGINX_CLUSTER_B

  PROMPT "Install NEW Ngnix service on OSP cluster B${new_subm_test_ns:+ (Namespace $new_subm_test_ns)}"

  kubconf_b;

  install_nginx_service "${new_nginx_cluster_b}" "${new_subm_test_ns}"

  PROMPT "Install NEW Netshoot pod on AWS cluster A${SUBM_TEST_NS:+ (Namespace $SUBM_TEST_NS)},
  and verify connectivity to the NEW Ngnix service on OSP cluster B${new_subm_test_ns:+ (Namespace $new_subm_test_ns)}"
  kubconf_a; # Can also use --context ${CLUSTER_A_NAME} on all further oc commands

  ${OC} delete pod ${new_netshoot_cluster_a} --ignore-not-found ${SUBM_TEST_NS:+-n $SUBM_TEST_NS}

  ${OC} run ${new_netshoot_cluster_a} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} --image nicolaka/netshoot \
  --pod-running-timeout=5m --restart=Never -- sleep 5m

  echo "# Wait up to 3 minutes for NEW Netshoot pod [${new_netshoot_cluster_a}] to be ready:"
  ${OC} wait --timeout=3m --for=condition=ready pod -l run=${new_netshoot_cluster_a} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS}
  ${OC} describe pod ${new_netshoot_cluster_a} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS}

  if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then
    PROMPT "Testing GlobalNet annotation - NEW Nginx service on OSP cluster B should get a GlobalNet IP"
    kubconf_b

    BUG "When you create a pod/service, GN Controller gets notified about the Pod/Service notification
     and then it annotates and programs - this could add delay to the GlobalNet use-cases." \
     "Wait up to 3 minutes before checking connectivity with GlobalNet on overlapping clusters CIDRs" \
    "https://github.com/submariner-io/submariner/issues/588"
    # Workaround:

    # Should fail if new_nginx_cluster_b was not annotated with GlobalNet IP
    GLOBAL_IP=""
    test_svc_pod_global_ip_created svc "$new_nginx_cluster_b" $new_subm_test_ns
    [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on NEW Ngnix service (${new_nginx_cluster_b}${new_subm_test_ns:+.$new_subm_test_ns})"

    # TODO: Ping to the new_nginx_global_ip
    # new_nginx_global_ip="$GLOBAL_IP"

    PROMPT "Testing GlobalNet annotation - NEW Netshoot pod on AWS cluster A (public) should get a GlobalNet IP"

    kubconf_a;

    netshoot_pod=$(${OC} get pods -l run=${new_netshoot_cluster_a} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} \
    --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')

    # Should fail if new_netshoot_cluster_a was not annotated with GlobalNet IP
    GLOBAL_IP=""
    test_svc_pod_global_ip_created pod "$new_netshoot_cluster_a" $SUBM_TEST_NS
    [[ -n "$GLOBAL_IP" ]] || FATAL "GlobalNet error on NEW Netshoot Pod (${new_netshoot_cluster_a}${SUBM_TEST_NS:+ in $SUBM_TEST_NS})"
  fi

  PROMPT "Create ServiceExport on OSP cluster B${new_subm_test_ns:+ (Namespace $new_subm_test_ns)}, for Nginx on SuperCluster domain"

  kubconf_b;

  BUG "Service domain (FQDN) on supercluster will not be resolved, if GlobalNet annotation was not set yet" \
  "Verify Nginx GlobalIP Annotation, prior to creating ServiceExport" \
  "https://github.com/submariner-io/submariner/issues/627"
  # Workaround:
  # Temporarily export ServiceExport after watch_and_retry for globalip annotation, but not before

  ${OC} ${new_subm_test_ns:+-n $new_subm_test_ns} apply -f - <<EOF
    apiVersion: lighthouse.submariner.io/v2alpha1
    kind: ServiceExport
    metadata:
      name: ${new_nginx_cluster_b}
EOF

  echo "# Wait for the ServiceExport CR to be ready:"

  BUG "Rollout status failed: ServiceExport is not a registered version" \
  "Skip checking for ServiceExport creation status" \
  "https://github.com/submariner-io/submariner/issues/640"
  # Workaround: Do not run this -
    # ${OC} rollout status "serviceexport.lighthouse.submariner.io/${new_nginx_cluster_b}" ${new_subm_test_ns:+-n $new_subm_test_ns}

  BUG "Missing documentation about svc.supercluster.local" \
  "Doc Needed: Ping/Curl svc.supercluster.local" \
  "https://github.com/submariner-io/submariner-website/issues/167"

  # Get FQDN on Supercluster when using Service-Discovery (lighthouse)
  nginx_cl_b_dns="${new_nginx_cluster_b}${new_subm_test_ns:+.$new_subm_test_ns}.svc.supercluster.local"


  PROMPT "Testing Service-Discovery: From NEW Netshoot pod on cluster A${SUBM_TEST_NS:+ (Namespace $SUBM_TEST_NS)}
  To NEW Nginx service on cluster B${new_subm_test_ns:+ (Namespace $new_subm_test_ns)}, by DNS hostname: $nginx_cl_b_dns"
  kubconf_a

  BUG "curl to Ngnix with Global-IP on supercluster, sometimes fails" \
  "Randomly fails, not always" \
  "https://github.com/submariner-io/submariner/issues/644"
  # No workaround

  echo "# Try to ping ${new_nginx_cluster_b} until getting expected FQDN: $nginx_cl_b_dns (and IP)"
  #TODO: Validate both GlobalIP and svc.supercluster.local with   ${OC} get all
      # NAME                 TYPE           CLUSTER-IP   EXTERNAL-IP                            PORT(S)   AGE
      # service/kubernetes   clusterIP      172.30.0.1   <none>                                 443/TCP   39m
      # service/openshift    ExternalName   <none>       kubernetes.default.svc.supercluster.local   <none>    32m

  cmd="${OC} exec ${new_netshoot_cluster_a} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} -- ping -c 1 $nginx_cl_b_dns"
  regex="PING ${nginx_cl_b_dns}"
  watch_and_retry "$cmd" 3m "$regex"
    # PING netshoot-cl-a-new.test-submariner-new.svc.supercluster.local (169.254.59.89)

  echo "# Try to CURL from ${new_netshoot_cluster_a} to ${nginx_cl_b_dns}:8080 :"
  ${OC} exec ${new_netshoot_cluster_a} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_cl_b_dns}:8080"

  # TODO: Test connectivity with https://github.com/tsliwowicz/go-wrk

  # Negative test for nginx_cl_b_short_dns FQDN
  nginx_cl_b_short_dns="${new_nginx_cluster_b}${new_subm_test_ns:+.$new_subm_test_ns}"

  PROMPT "Testing Service-Discovery:
  There should be NO DNS resolution from cluster A to the local Nginx address on cluster B: $nginx_cl_b_short_dns (FQDN without \"supercluster\")"

  kubconf_a

  msg="# Negative Test - ${nginx_cl_b_short_dns}:8080 should not be reachable (FQDN without \"supercluster\")"

  ${OC} exec ${new_netshoot_cluster_a} ${SUBM_TEST_NS:+-n $SUBM_TEST_NS} \
  -- /bin/bash -c "curl --max-time 30 --verbose ${nginx_cl_b_short_dns}:8080" \
  |& (! highlight "command terminated with exit code" && FATAL "$msg") || echo -e "$msg"
    # command terminated with exit code 28

}

# ------------------------------------------

function test_submariner_packages() {
### Run Submariner Unit tests (mock) ###
  PROMPT "Testing Submariner Packages (Unit-Tests) with GO"
  trap_commands;
  cd $GOPATH/src/github.com/submariner-io/submariner
  export GO111MODULE="on"
  go env
  go test -v ./pkg/... -ginkgo.v -ginkgo.reportFile "$SCRIPT_DIR/subm_pkg_junit_result.xml"

    # OR with local go modules:
      # GO111MODULE="on" go test -v ./pkg/... -ginkgo.v -ginkgo.reportFile junit_result.xml

        # JUnit report was created: ~/go/src/github.com/submariner-io/submariner-operator/pkg/discovery/network/junit_result.xml
        # Ran 32 of 32 Specs in 0.012 seconds
        # SUCCESS! -- 32 Passed | 0 Failed | 0 Pending | 0 Skipped
        # ...
        # JUnit report was created: ~/go/src/github.com/submariner-io/submariner-operator/pkg/subctl/datafile/junit_result.xml
        # Ran 5 of 5 Specs in 0.001 seconds
        # SUCCESS! -- 5 Passed | 0 Failed | 0 Pending | 0 Skipped
        # ...
        # JUnit report was created: ~/go/src/github.com/submariner-io/submariner-operator/pkg/subctl/operator/install/crds/junit_result.xml
        # Ran 3 of 3 Specs in 0.002 seconds
        # SUCCESS! -- 3 Passed | 0 Failed | 0 Pending | 0 Skipped
}

# ------------------------------------------

function test_submariner_e2e_with_go() {
# Run E2E Tests of Submariner:
  PROMPT "Testing Submariner End-to-End tests with GO"
  trap_commands;
  cd $GOPATH/src/github.com/submariner-io/submariner

  BUG "Should be able to use default KUBECONFIGs of OCP installers, with identical context (\"admin\")" \
  "Modify KUBECONFIG context name on cluster A and B, to be unique (to prevent E2E failure)" \
  "https://github.com/submariner-io/submariner/issues/245"
  sed -z "s#name: [a-zA-Z0-9-]*\ncurrent-context: [a-zA-Z0-9-]*#name: ${CLUSTER_A_NAME}\ncurrent-context: ${CLUSTER_A_NAME}#" -i.bak ${KUBECONF_CLUSTER_A}
  sed -z "s#name: [a-zA-Z0-9-]*\ncurrent-context: [a-zA-Z0-9-]*#name: ${CLUSTER_B_NAME}\ncurrent-context: ${CLUSTER_B_NAME}#" -i.bak ${KUBECONF_CLUSTER_B}

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
  -ginkgo.reportFile "$SCRIPT_DIR/subm_e2e_junit_result.xml" \
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

  which subctl
  subctl version

  BUG "Cannot use Merged KUBECONFIG for subctl info command: ${KUBECONFIG}" \
  "Call Kubeconfig of a single Cluster" \
  "https://github.com/submariner-io/submariner-operator/issues/384"
  # workaround:
  kubconf_a;

  # subctl info # Removed since https://github.com/submariner-io/submariner-operator/issues/467
  subctl show networks || :

  BUG "No Subctl option to set -ginkgo.reportFile" \
  "No workaround yet..." \
  "https://github.com/submariner-io/submariner-operator/issues/509"

  # subctl verify --enable-disruptive --verbose ${KUBECONF_CLUSTER_A} ${KUBECONF_CLUSTER_B}
  subctl verify --only service-discovery,connectivity --verbose ${KUBECONF_CLUSTER_A} ${KUBECONF_CLUSTER_B}

}

# ------------------------------------------


####################################################################################

### MAIN ###

# Logging main output (enclosed with parenthesis) with tee

LOG_FILE="${REPORT_NAME// /_}" # replace all spaces with _
LOG_FILE="${LOG_FILE}_${DATE_TIME}.log" # can also consider adding timestemps with: ts '%H:%M:%.S' -s

(
  # Trap test exit failure, to print more info before exiting main flow
  #trap_on_exit_error collect_submariner_info
  trap 'trap_on_exit_error "$?" "$LINENO" "${junit_run} collect_submariner_info"' EXIT

  # Print planned steps according to CLI/User inputs
  ${junit_run} print_test_plan

  # Setup and verify environment
  setup_workspace

  ### Running Submariner Deploy ###
  if [[ ! "$skip_deploy" =~ ^(y|yes)$ ]]; then

    # Running download_ocp_installer if requested
    [[ ! "$get_ocp_installer" =~ ^(y|yes)$ ]] || ${junit_run} download_ocp_installer ${GET_OCP_VERSION}

    # Running destroy_aws_cluster_a if requested
    [[ ! "$destroy_cluster_a" =~ ^(y|yes)$ ]] || ${junit_run} destroy_aws_cluster_a

    # Running create_aws_cluster_a if requested
    [[ ! "$create_cluster_a" =~ ^(y|yes)$ ]] || ${junit_run} create_aws_cluster_a

    ${junit_run} test_kubeconfig_aws_cluster_a

    # Running build_ocpup_tool_latest if requested
    [[ ! "$get_ocpup_tool" =~ ^(y|yes)$ ]] || ${junit_run} build_ocpup_tool_latest

    # Running destroy_osp_cluster_b if requested
    [[ ! "$destroy_cluster_b" =~ ^(y|yes)$ ]] || ${junit_run} destroy_osp_cluster_b

    # Running create_osp_cluster_b if requested
    [[ ! "$create_cluster_b" =~ ^(y|yes)$ ]] || ${junit_run} create_osp_cluster_b

    ${junit_run} test_kubeconfig_osp_cluster_b

    ### Cleanup Submariner from all clusters ###

    # Running clean_aws_cluster_a if requested
    [[ ! "$clean_cluster_a" =~ ^(y|yes)$ ]] || [[ "$destroy_cluster_a" =~ ^(y|yes)$ ]] \
    || ${junit_run} clean_aws_cluster_a

    # Running clean_osp_cluster_b if requested
    [[ ! "$clean_cluster_b" =~ ^(y|yes)$ ]] || [[ "$destroy_cluster_b" =~ ^(y|yes)$ ]] \
    || ${junit_run} clean_osp_cluster_b

    ${junit_run} install_netshoot_app_on_cluster_a

    ${junit_run} install_nginx_svc_on_cluster_b

    ${junit_run} test_basic_cluster_connectivity_before_submariner

    ${junit_run} test_clusters_disconnected_before_submariner

    # Running build_operator_latest if requested
    [[ ! "$build_operator" =~ ^(y|yes)$ ]] || ${junit_run} build_operator_latest

    # Running build_submariner_e2e_latest if requested
    [[ ! "$build_submariner_e2e" =~ ^(y|yes)$ ]] || ${junit_run} build_submariner_e2e_latest

    # Running download_subctl_latest_release if requested
    [[ ! "$get_subctl" =~ ^(y|yes)$ ]] || ${junit_run} download_subctl_latest_release

    # Running download_subctl_latest_release if requested
    [[ ! "$get_subctl_devel" =~ ^(y|yes)$ ]] || ${junit_run} download_subctl_latest_devel

    ${junit_run} test_subctl_command

    ${junit_run} open_firewall_ports_on_the_broker_node

    ${junit_run} label_all_gateway_external_ip_cluster_a

    ${junit_run} label_first_gateway_cluster_b

    ${junit_run} install_broker_aws_cluster_a

    ${junit_run} join_submariner_cluster_a

    ${junit_run} join_submariner_cluster_b

  fi

  ### Running Submariner Tests ###

  if [[ ! "$skip_tests" =~ ^(y|yes)$ ]]; then

    ${junit_run} test_kubeconfig_aws_cluster_a

    ${junit_run} test_kubeconfig_osp_cluster_b

    echo "# From this point, if script fails - \$TEST_STATUS_RC is considered UNSTABLE
    \n# ($TEST_STATUS_RC with exit code 2)"

    echo 2 > $TEST_STATUS_RC

    ${junit_run} test_submariner_status_cluster_a

    ${junit_run} test_submariner_status_cluster_b

    # Run Connectivity tests between the Private and Public clusters,
    # To validate that now Submariner made the connection possible.

    ${junit_run} test_clusters_connected_by_service_ip

    [[ ! "$globalnet" =~ ^(y|yes)$ ]] || ${junit_run} test_clusters_connected_overlapping_cidrs

    [[ ! "$service_discovery" =~ ^(y|yes)$ ]] || ${junit_run} test_clusters_connected_by_same_service_on_new_namespace

    ${junit_run} verify_golang

    ${junit_run} test_submariner_packages || BUG "Submariner Unit-Tests FAILED."

    ${junit_run} test_submariner_e2e_with_go || BUG "Submariner E2E Tests FAILED."

    ${junit_run} test_submariner_e2e_with_subctl
  fi

  # If got to here - all tests of Submariner has passed ;-)
  echo 0 > $TEST_STATUS_RC

) |& tee $LOG_FILE # can also consider adding timestemps with: ts '%H:%M:%.S' -s


####################################################################################

### END of Submariner Tests (Creating HTML report from console output) ###

# Get test exit status (from file $TEST_STATUS_RC)
test_status="$([[ ! -f "$TEST_STATUS_RC" ]] || cat $TEST_STATUS_RC)"

# Create HTML Report from log file (with title extracted from log file name)
message="Creating HTML Report"
if [[ -z "$test_status" || "$test_status" -ne 0 ]] ; then
  message="$message - Test exit status: $test_status"
  # color="$RED"
fi
PROMPT "$message" # "$color"

#REPORT_NAME=$(basename $LOG_FILE .log)
#REPORT_NAME=( ${REPORT_NAME//_/ } ) # without quotes
#REPORT_NAME="${REPORT_NAME[*]^}"
echo "# REPORT_NAME = $REPORT_NAME" # May have been set externally
echo "# REPORT_FILE = $REPORT_FILE" # May have been set externally

log_to_html "$LOG_FILE" "$REPORT_NAME" "$REPORT_FILE"

# If REPORT_FILE was not passed externally, set it as the latest html file that was created
REPORT_FILE="${REPORT_FILE:-$(ls -1 -tu *.html | head -1)}"

# Compressing report to tar.gz
report_archive="${REPORT_FILE%.*}_${DATE_TIME}.tar.gz"

echo -e "# Compressing Report, Log, Kubeconfigs and $BROKER_INFO into: ${report_archive}"
[[ ! -f "$KUBECONF_CLUSTER_A" ]] || cp "$KUBECONF_CLUSTER_A" "kubconf_${CLUSTER_A_NAME}"
[[ ! -f "$KUBECONF_CLUSTER_B" ]] || cp "$KUBECONF_CLUSTER_B" "kubconf_${CLUSTER_B_NAME}"
tar -cvzf $report_archive $(ls \
 "$REPORT_FILE" \
 "$LOG_FILE" \
 kubconf_* \
 *junit*.xml \
 "$WORKDIR/$BROKER_INFO" \
 2>/dev/null)

echo -e "# Archive \"$report_archive\" now contains:"
tar tvf $report_archive

echo -e "# To view in your Browser, run:\n tar -xvf ${report_archive}; firefox ${REPORT_FILE}"

exit $test_status

# You can find latest script here:
# https://github.com/manosnoam/ocp-multi-cluster-tester
#
# To create a local script file:
#        > setup_subm.sh; chmod +x setup_subm.sh; vi setup_subm.sh
#
# Execution example:
# Re-creating a new AWS cluster:
# ./setup_subm.sh --build-e2e --destroy-cluster-a --create-cluster-a --clean-cluster-b --service-discovery --globalnet
#
# Using Submariner upstream release (master), and installing on existing AWS cluster:
# ./setup_subm.sh --get-subctl-devel --clean-cluster-a --clean-cluster-b --service-discovery --globalnet
#
# Using the latest formal release of Submariner, and Re-creating a new AWS cluster:
# ./setup_subm.sh --build-e2e --get-subctl --destroy-cluster-a --create-cluster-a --clean-cluster-b --service-discovery --globalnet
#
