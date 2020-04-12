#!/bin/bash
#######################################################################################################
#                                                                                                     #
# Setup Submariner on AWS and OSP (Upshift)                                                           #
# By Noam Manos, nmanos@redhat.com                                                                    #
# The script is based on the Submariner MVP Doc:                                                      #
# https://docs.google.com/document/d/1HCbyuNX8AELNyB6TE4H05Kj3gujwS4-Im3-BG796zIw                     #
#                                                                                                     #
# It is assumed that you have existing OCP "install-config.yaml" for both Cluster A (OSP) and B (OSP),#
# in the current directory. For Cluster B, use the existing config of OCPUP multi-cluster-networking. #                                                                         #
#                                                                                                     #
# For Cluster A, you can create config with AWS pull secret and SSH public key. To do so:             #
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

This is an interactive script to create Openshift Clusters on OSP and AWS,
and test multi-cluster network connectivity with Submariner:

* ...
* ...
* ...

Running with pre-defined parameters (optional):

* Show this help menu:                               -h / --help
* Show debug info (verbose) for commands:            -d / --debug
* Build latest Submariner-Operator (SubCtl):         --build-operator
* Build latest Submariner E2E (test packages):       --build-e2e
* Download latest OCP Installer:                     --get-ocp-installer
* Download latest OCPUP Tool:                        --get-ocpup-tool
* Download latest KUBEFED Tool:                      --get-kubefed-tool
* Download latest release of SubCtl:                 --get-subctl
* Create AWS Cluster A:                              --create-cluster-a
* Create OSP Cluster B:                              --create-cluster-b
* Destroy existing AWS Cluster A:                    --destroy-cluster-a
* Destroy existing OSP Cluster B:                    --destroy-cluster-b
* Clean existing AWS Cluster A:                      --clean-cluster-a
* Clean existing OSP Cluster B:                      --clean-cluster-b
* Install Service Discovery (lighthouse):            --service-discovery
* Install Global Net:                                --globalnet
* Skip Submariner deployment:                        --skip-deploy
* Skip all tests execution:                          --skip-tests
* Install Golang if missing:                         --config-golang
* Install AWS-CLI and configure access:              --config-aws-cli
* Import additional variables from file:             --import-vars  [Variable file path]


Command examples:

$ ./setup_subm.sh

  Will run interactively (enter choices during execution).

$ ./setup_subm.sh --get-ocp-installer --build-e2e --get-subctl --destroy-cluster-a --create-cluster-a --clean-cluster-b --service-discovery --globalnet

  Will create new AWS Cluster (A), Clean existing OSP Cluster (B), build, install and test latest Submariner, with service discovery.


----------------------------------------------------------------------'

# To trap inside functions
# set -T # might have issues with kubectl/oc commands

# To exit on error
set -e

# To expend aliases
shopt -s expand_aliases

####################################################################################

### General CONSTANTS ###
export RED='\x1b[0;31m'
export GREEN='\x1b[38;5;22m'
export CYAN='\x1b[36m'
export YELLOW='\x1b[33m' #'\x1b[32m'
export NO_COLOR='\x1b[0m'
export HAT="${RED}🎩︎${NO_COLOR}"

export TEMP_FILE=`mktemp`
export DATE_TIME="$(date +%d%m%Y_%H%M)"
export PATH=$HOME/.local/bin:$PATH

### Import Submariner setup variables ###
source "$(dirname $0)/subm_variables"

### Import General Helpers Function ###
source "$(dirname $0)/helper_functions"

####################################################################################

### CLI Script inputs ###

check_cli_args() {
  [[ -n "$1" ]] || ( echo "# Missing arguments. Please see Help with: -h" && exit 1 )
}

shopt -s nocasematch # Case-insensitive match for string evaluations
POSITIONAL=()
while [ $# -gt 0 ]; do
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
  --get-ocpup-tool)
    get_ocpup_tool=YES
    shift ;;
  --get-kubefed-tool)
    get_kubefed_tool=YES
    shift ;;
  --get-subctl)
    get_subctl=YES
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
  # -o|--optional-key-value)
  --import-vars)
    check_cli_args $2
    variables_file="$2"
    echo "# Importing additional variables from file: $variables_file"
    source "$variables_file"
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

  # User input: $get_ocpup_tool - to build_ocpup_tool_latest
  while [[ ! "$get_ocpup_tool" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to download OCPUP tool ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    get_ocpup_tool=${input:-no}
  done

  # User input: $create_cluster_a - to create_aws_cluster_a
  while [[ ! "$create_cluster_a" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to create AWS Cluster A ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    create_cluster_a=${input:-no}
  done

  # User input: $destroy_cluster_a - to destroy_aws_cluster_a
  while [[ ! "$destroy_cluster_a" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to DESTROY AWS Cluster A ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    destroy_cluster_a=${input:-no}
  done

  # User input: $clean_cluster_a - to clean_aws_cluster_a
  if [[ "$destroy_cluster_a" =~ ^(no|n)$ ]]; then
    while [[ ! "$clean_cluster_a" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to clean AWS Cluster A ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      clean_cluster_a=${input:-no}
    done
  fi

  # User input: $destroy_cluster_b - to destroy_osp_cluster_b
  while [[ ! "$destroy_cluster_b" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to DESTROY OSP Cluster B ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    destroy_cluster_b=${input:-no}
  done

  # User input: $create_cluster_b - to create_osp_cluster_b
  while [[ ! "$create_cluster_a" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to create OSP Cluster B ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    create_cluster_b=${input:-no}
  done

  # User input: $clean_cluster_b - to clean_osp_cluster_b
  if [[ "$destroy_cluster_b" =~ ^(no|n)$ ]]; then
    while [[ ! "$clean_cluster_b" =~ ^(yes|no)$ ]]; do
      echo -e "\n${YELLOW}Do you want to clean OSP Cluster B ? ${NO_COLOR}
      Enter \"yes\", or nothing to skip: "
      read -r input
      clean_cluster_b=${input:-no}
    done
  fi

  # User input: $service_discovery - to deploy with --service-discovery
  while [[ ! "$service_discovery" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to install Service Discovery (lighthouse) ? ${NO_COLOR}
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
    echo -e "\n${YELLOW}Do you want to pull and build latest Submariner-Operator repository (SubCtl) ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    build_operator=${input:-no}
  done

  # User input: $get_subctl - to download_subctl_latest_release
  while [[ ! "$get_subctl" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to use the latest release of SubCtl (instead of Submariner-Operator \"mater\" branch) ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    get_subctl=${input:-no}
  done

  # User input: $build_submariner_e2e - to build_submariner_e2e_latest
  while [[ ! "$build_submariner_e2e" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to pull and build latest Submariner repository (E2E tests) ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    build_submariner_e2e=${input:-YES}
  done

  # User input: $get_kubefed_tool - to download_kubefedctl_latest
  while [[ ! "$get_kubefed_tool" =~ ^(yes|no)$ ]]; do
    echo -e "\n${YELLOW}Do you want to download KUBEFED tool ? ${NO_COLOR}
    Enter \"yes\", or nothing to skip: "
    read -r input
    get_kubefed_tool=${input:-no}
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
get_kubefed_tool=${get_kubefed_tool:-NO}
get_subctl=${get_subctl:-NO}
destroy_cluster_a=${destroy_cluster_a:-NO}
create_cluster_a=${create_cluster_a:-NO}
clean_cluster_a=${clean_cluster_a:-NO}
destroy_cluster_b=${destroy_cluster_b:-NO}
create_cluster_b=${create_cluster_b:-NO}
clean_cluster_b=${clean_cluster_b:-NO}
service_discovery=${service_discovery:-NO}
globalnet=${globalnet:-NO}


####################################################################################


### Main CI Function ###

function setup_workspace() {
  prompt "Creating workspace and verifing GO installation"
  # DONT trap_commands - Includes credentials, hide from output

  # CD to main working directory
  mkdir -p ${WORKDIR}
  cd ${WORKDIR}

  # Installing if $config_golang = yes/y
  [[ ! "$config_golang" =~ ^(y|yes)$ ]] || install_local_golang

  # Installing if $config_aws_cli = yes/y
  [[ ! "$config_aws_cli" =~ ^(y|yes)$ ]] || ( configure_aws_access \
  "${AWS_PROFILE_NAME}" "${AWS_REGION}" "${AWS_KEY}" "${AWS_SECRET}" "${WORKDIR}" )

  # verifying GO installed
  verify_golang

}

# ------------------------------------------

function download_ocp_installer() {
### Download OCP installer ###
  prompt "Downloading latest OCP Installer"
  # The nightly builds available at: https://openshift-release-artifacts.svc.ci.openshift.org/
  trap_commands;
  cd ${WORKDIR}

  # ocp_install_gz=$(curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/ \
  # | grep -Eoh '"openshift-install-linux-.+\.tar\.gz"' | tr -d '"')
  curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/ \
  | grep -Eoh '"openshift-install-linux-.+\.tar\.gz"' | tr -d '"' > $TEMP_FILE

  ocp_install_gz="$(< $TEMP_FILE)"

  #oc_client_gz=$(curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/ \
  # | grep -Eoh '"openshift-client-linux-.+\.tar\.gz"' | tr -d '"')

  curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/ \
  | grep -Eoh '"openshift-client-linux-.+\.tar\.gz"' | tr -d '"' > $TEMP_FILE

  oc_client_gz="$(< $TEMP_FILE)"

  #wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/${ocp_install_gz}
  #wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/${oc_client_gz}

  download_file https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/${ocp_install_gz}
  download_file https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/${oc_client_gz}

  tar -xvf ${ocp_install_gz} -C ${WORKDIR}
  tar -xvf ${oc_client_gz} -C ${WORKDIR}

  ${OC} -h

  # Create oc (openshift client) link
    # sudo cp oc /usr/local/bin/
    # cp oc ~/.local/bin
    cp oc ~/go/bin/
}

# ------------------------------------------

function build_ocpup_tool_latest() {
### Download OCPUP tool ###
  prompt "Downloading latest OCP-UP tool, and installing it to ~/go/bin/ocpup"
  trap_commands;

  # TODO: Need to fix ocpup alias

  cd ${WORKDIR}

  git clone https://github.com/dimaunx/ocpup || echo "# OCPUP directory exists"

  cd ocpup

  # To cleanup GOLANG mod files:
    # go clean -cache -modcache -i -r

  git fetch && git reset --hard && git clean -df && git checkout --theirs . && git pull

  # Build OCPUP and install it locally to ~/go/bin/
  export GO111MODULE=on
  go mod vendor
  go install -mod vendor

  # Check OCPUP command
    # sudo ln -sf ocpup /usr/local/bin/ocpup
  which ocpup
    # ~/go/bin/ocpup

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

function build_submariner_e2e_latest() {
### Building latest Submariner code and tests ###
  prompt "Building latest Submariner code, including test packages (unit-tests and E2E)"
  trap_commands;
  # Delete old Submariner directory
    # rm -rf $GOPATH/src/github.com/submariner-io/submariner

  # Download Submariner with go
    # export PATH=$PATH:$GOROOT/bin
  go get -v github.com/submariner-io/submariner/... || echo "# GO get Submariner Engine finished."

  # Pull latest changes and build:
  cd $GOPATH/src/github.com/submariner-io/submariner
  ls

  #git fetch upstream && git checkout master && git pull upstream master
  # git fetch && git git pull --rebase
  git fetch && git reset --hard && git clean -df && git checkout --theirs . && git pull

  make build # || echo "# Build Submariner Engine finished"
    # ...
    # Building submariner-engine version dev
    # ...
    # Building submariner-route-agent version dev
    # ...
  ls -l bin/submariner-engine
}

# ------------------------------------------

function build_operator_latest() {
### Building latest Submariner-Operator code and SubCTL tool ###
  prompt "Building latest Submariner-Operator code and SubCTL tool"
  trap_commands;
  # Delete old Submariner directory
  #rm -rf $GOPATH/src/github.com/submariner-io/submariner-operator

  # Download Submariner Operator with go
  # export PATH=$PATH:$GOROOT/bin
  go get -v github.com/submariner-io/submariner-operator/... || echo "# GO get Submariner Operator finished"

  # Pull latest changes and build:
  cd $GOPATH/src/github.com/submariner-io/submariner-operator
  ls

  # go get -v -u -t ./...
  git fetch && git reset --hard && git clean -df && git checkout --theirs . && git pull
  # git log --pretty=fuller

  # Build SubCtl tool
  #make build # || echo "# Build Submariner Operator finished"
  BUG "make build" "make bin/subctl" "https://github.com/submariner-io/submariner-operator/issues/126"
  GO111MODULE="on" go mod vendor
  make bin/subctl

    # ...
    # Building subctl version dev for linux/amd64
    # ...

  ls -l ./bin/subctl

  # Create symbolic link /usr/local/bin/subctl :
  # sudo ln -sf $GOPATH/src/github.com/submariner-io/submariner-operator/bin/subctl /usr/local/bin/subctl
  # cp ./bin/subctl ~/.local/bin
  cp ./bin/subctl ~/go/bin/

}

# ------------------------------------------

function download_subctl_latest_release() {
  ### Download OCP installer ###
    prompt "Downloading latest release of Submariner-Operator tool - SubCtl"
    trap_commands;
    cd ${WORKDIR}

    release_url="https://github.com/submariner-io/submariner-operator/releases/"
    file_path="$(curl $release_url | grep -Eoh 'download\/v.*\/subctl-.*-linux-amd64' -m 1)"
    file_name=$(basename -- "$file_path")

    download_file ${release_url}${file_path}

    # tar -xvf ${file_name} -C ${WORKDIR}

    BUG "${file_name} is not a TGZ archive, but a binary" \
    "Do not extract the downloaded file [${file_name}], but rename instead to \"subctl\"" \
    "https://github.com/submariner-io/submariner-operator/issues/257"
    mv ${file_name} subctl
    chmod +x subctl

    echo "# Copy subctl to system path:"
    cp subctl ~/go/bin/
    #go get -v github.com/kubernetes-sigs/kubefed/... || echo "# Installed kubefed"
    #cd $GOPATH/src/github.com/kubernetes-sigs/kubefed
    #go get -v -u -t ./...

}

# ------------------------------------------

function test_subctl_command() {
  prompt "Verifying SubCTL (Submariner-Operator command line tool)"
  trap_commands;
  #cd $GOPATH/src/github.com/submariner-io/submariner-operator

  which subctl
  subctl version

  # Create subctl alias:
  # unalias subctl
  # alias subctl="${PWD}/bin/subctl"

  subctl deploy-broker --help
    # set the broker up
    #
    # Usage:
    #   subctl deploy-broker [flags]
    #
    # Flags:
    #       --clustercidr string      cluster CIDR
    #       --clusterid string        cluster ID used to identify the tunnels
    #       --colorcodes string       color codes (default "blue")
    #       --disable-nat             Disable NAT for IPSEC
    #   -h, --help                    help for deploy-broker
    #       --ikeport int             IPsec IKE port (default 500)
    #       --nattport int            IPsec NATT port (default 4500)
    #   -n, --no-dataplane            Don't install the submariner dataplane on the broker
    #   -o, --operator-image string   the operator image you wish to use (default "quay.io/submariner/submariner-operator:0.0.1")
    #       --repository string       image repository
    #       --servicecidr string      service CIDR
    #       --version string          image version
    #
    # Global Flags:
    #       --kubeconfig string   absolute path(s) to the kubeconfig file(s) (default "~/.kube/config")

  subctl join --help
    # connect a cluster to an existing broker
    #
    # Usage:
    #   subctl join [flags]
    #
    # Flags:
    #       --clustercidr string      cluster CIDR
    #       --clusterid string        cluster ID used to identify the tunnels
    #       --colorcodes string       color codes (default "blue")
    #       --disable-nat             Disable NAT for IPSEC
    #   -h, --help                    help for join
    #       --ikeport int             IPsec IKE port (default 500)
    #       --nattport int            IPsec NATT port (default 4500)
    #   -o, --operator-image string   the operator image you wish to use (default "quay.io/submariner/submariner-operator:0.0.1")
    #       --repository string       image repository
    #       --servicecidr string      service CIDR
    #       --version string          image version
    #
    # Global Flags:
    #       --kubeconfig string   absolute path(s) to the kubeconfig file(s) (default "~/.kube/config")
    #
}

# ------------------------------------------

function download_kubefedctl_latest() {
### Download OCP installer ###
  prompt "Downloading latest KubFed Controller"
  trap_commands;
  cd ${WORKDIR}

  curl https://github.com/kubernetes-sigs/kubefed/releases/ \
  | grep -Eoh 'download\/v.*\/kubefedctl-.*-linux-amd64\.tgz' -m 1 > $TEMP_FILE

  kubefedctl_url="$(< $TEMP_FILE)"
  kubefedctl_gz=$(basename -- "$kubefedctl_url")

  # download_file https://github.com/kubernetes-sigs/kubefed/releases/${kubefedctl_url}

  BUG "Downloading latest kubefedctl will later break Subctl command" \
  "Download older kubefedctl version v0.1.0-rc3" \
  "https://github.com/submariner-io/submariner-operator/issues/192"
  kubefedctl_gz="kubefedctl-0.1.0-rc3-linux-amd64.tgz"
  download_file "https://github.com/kubernetes-sigs/kubefed/releases/download/v0.1.0-rc3/kubefedctl-0.1.0-rc3-linux-amd64.tgz"

  tar -xvf ${kubefedctl_gz} -C ${WORKDIR}

  ${KUBFED} -h

  # Create kubefedctl link
    # sudo cp kubefedctl /usr/local/bin/
    # cp kubefedctl ~/.local/bin

  BUG "Install kubefedctl in current dir" \
  "Install kubefedctl into ~/go/bin/" \
  "https://github.com/submariner-io/submariner-operator/issues/166"
  cp kubefedctl ~/go/bin/
  #go get -v github.com/kubernetes-sigs/kubefed/... || echo "# Installed kubefed"
  #cd $GOPATH/src/github.com/kubernetes-sigs/kubefed
  #go get -v -u -t ./...
}

# ------------------------------------------

function create_aws_cluster_a() {
### Create AWS Cluster A (Public) with OCP installer ###
  prompt "Creating AWS Cluster A (Public) with OCP installer"
  trap_commands;
  # Using existing OCP install-config.yaml - make sure to have it in the workspace.

  cd ${WORKDIR}

  mkdir ${CLUSTER_A_NAME} || FATAL "Previous Cluster ${CLUSTER_A_NAME} deployment should be removed."
  cp ${OCP_CLUSTER_A_SETUP} ${CLUSTER_A_DIR}/install-config.yaml

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
        # ? Cluster Name user-cluster-a
        # ? Pull Secret

  # Run OCP installer with the user-cluster-a.yaml:

    # This has a bug in bugzilla - using "--dir"
    # $ cd ..
    # $ ./openshift-install create install-config --dir user-cluster-a

  cd ${CLUSTER_A_NAME}
  ../openshift-install create cluster --log-level debug

  # To tail all OpenShift Installer logs (in a new session):
    # find . -name "*.log" | xargs tail -f

  # Login to the new created Cluster:
    # $ grep "Access the OpenShift web-console" -r . --include='*.log' -A 1
      # "Access the OpenShift web-console here: https://console-openshift-console.apps..."
      # "Login to the console with user: kubeadmin, password: ..."
}

# ------------------------------------------

function create_osp_cluster_b() {
### Create Openstack Cluster B (Private) with OCPUP tool ###
  prompt "Creating Openstack Cluster B (Private) with OCP-UP tool"
  trap_commands;

  cd ${OCPUP_DIR}
  echo -e "# Using an existing OCPUP yaml configuration file: \n${OCPUP_CLUSTER_B_SETUP}"
  # TODO: This YAML file should be copied from a secure path
  cp ${OCPUP_CLUSTER_B_SETUP} ./
  ocpup_yml=$(basename -- "$OCPUP_CLUSTER_B_SETUP")
  ls -l $ocpup_yml

  # vi $ocpup_yml

    # openshift:
    #   version: 4.2.0
    # clusters:
    # - clusterName: cl1
    #   clusterType: private
    #   vpcCidr: 10.166.0.0/16
    #   podCidr: 10.252.0.0/14
    #   svcCidr: 100.96.0.0/16
    #   numMasters: 3
    #   numWorkers: 2
    #   numGateways: 1
    #   dnsDomain: devcluster.openshift.com
    #   platform:
    #     name: openstack
    #     region: regionOne
    #     externalNetwork: provider_net_cci_6
    #     computeFlavor: ci.m1.xlarge
    # authentication:
    #   pullSecret: [ YOUR AWS PULL SECRET inside '' ]
    #   sshKey: [ YOUR ~/.ssh/id_rsa.pub ]
    #   openstack:
    #       authUrl: https://rhos-d.infra.prod.upshift.rdu2.redhat.com:13000/v3
    #       userName: [ YOUR Red Hat Username ]
    #       password: [ YOUR Red Hat Password inside "" ]
    #       projectId: 8ce209f63ab24601b57bf3cfd5b7cc25
    #       projectName: multi-cluster-networking
    #       userDomainName: redhat.com


  # Run OCPUP to Create OpenStack Cluster B (Private)
  # ocpup create clusters --debug --config $ocpup_yml
  ocpup create clusters --config $ocpup_yml &
  pid=$!
  tail --pid=$pid -f --retry .config/cl1/.openshift_install.log &
  tail --pid=$pid -f /dev/null

  # To tail all OpenShift Installer logs (in a new session):
    # find . -name "*openshift_install.log" | xargs tail --pid=$pid -f # tail ocpup/.config/cl1/.openshift_install.log

  # Login to the new created Cluster:
  # $ grep "Access the OpenShift web-console" -r . --include='*.log' -A 1
    # "Access the OpenShift web-console here: https://console-openshift-console.apps..."
    # "Login to the console with user: kubeadmin, password: ..."
}

# ------------------------------------------

function test_kubeconfig_aws_cluster_a() {
# Check that AWS Cluster A (Public) is up and running
  prompt "Checking that AWS Cluster A (Public) is up and running"
  trap_commands;

  #cd ${WORKDIR}/${CLUSTER_A_NAME}
  # cd ${CLUSTER_A_DIR}

  # export CLUSTER_A=~/automation/ocp-install/user-cluster-a/auth/kubeconfig
  #export CLUSTER_A=${PWD}/auth/kubeconfig
  # export KUBECONF_CLUSTER_A=${PWD}/auth/kubeconfig
  #alias kubconf_a="KUBECONFIG=${KUBECONF_CLUSTER_A}"

  kubconf_a;
  test_cluster_status || FATAL "Openshift deployment cannot be reached with KUBECONFIG=${KUBECONF_CLUSTER_A}"
  # cd -
}

function kubconf_a() {
# Alias of KubeConfig for AWS Cluster A (Public) (AWS):
  trap_commands;
  export "KUBECONFIG=${KUBECONF_CLUSTER_A}";
}

# ------------------------------------------

function test_kubeconfig_osp_cluster_b() {
# Check that OSP Cluster B (Private) is up and running
  prompt "Checking that OSP Cluster B (Private) is up and running"
  trap_commands;

  # cd ${WORKDIR}/${OCPUP_DIR}

  # TODO: Need to replace "cl1" with a dynamic value according to OCPUP yaml config
  # export CLUSTER_B="~/automation/ocp-install/ocpup/.config/cl1/auth/kubeconfig"
  # export CLUSTER_B=${PWD}/.config/cl1/auth/kubeconfig
  #alias kubconf_b="KUBECONFIG=${KUBECONF_CLUSTER_B}"

  kubconf_b;
  test_cluster_status || FATAL "Openshift deployment cannot be reached with KUBECONFIG=${KUBECONF_CLUSTER_B}"
  # cd -
}

function kubconf_b() {
# Alias of KubeConfig for OSP Cluster B (Private) (OpenStack):
  trap_commands;
  export "KUBECONFIG=${KUBECONF_CLUSTER_B}";
}

# ------------------------------------------

function test_cluster_status() {
  # Verify that current kubeconfig Cluster is up and healthy
  trap_commands;

  ${OC} version
  ${OC} config view
  ${OC} status
  ${OC} get all
    # NAME                 TYPE           CLUSTER-IP   EXTERNAL-IP                            PORT(S)   AGE
    # service/kubernetes   ClusterIP      172.30.0.1   <none>                                 443/TCP   39m
    # service/openshift    ExternalName   <none>       kubernetes.default.svc.cluster.local   <none>    32m
}

# ------------------------------------------

function destroy_aws_cluster_a() {
### Destroy your previous AWS Cluster A (Public) ###
  prompt "Destroying previous AWS Cluster A (Public)"
  trap_commands;
  # Temp - CD to main working directory
  cd ${WORKDIR}

  # Only if your AWS cluster still exists (less than 48 hours passed) - run destroy command:
  # TODO: should first check if it was not already purged, because it can save a lot of time.
  if [[ -d ${CLUSTER_A_NAME} ]]; then
    echo "# Previous Openshift config dir exists - removing it"
    # cd ${CLUSTER_A_NAME}
    if [[ -f ${CLUSTER_A_DIR}/metadata.json ]] ; then
      timeout 20m ./openshift-install destroy cluster --log-level debug --dir ${CLUSTER_A_NAME} || \
      ( [[ $? -eq 124 ]] && \
      BUG "WARNING: OCP Destroy did not complete, but timeout exceeded." \
      "Skipping Destroy proccess" \
      "https://bugzilla.redhat.com/show_bug.cgi?id=1817201" )
    fi
    # cd ..

    # Remove existing OCP install-config directory:
    #rm -r _${CLUSTER_A_DIR}/ || echo "# Old config dir removed."
    mv ${CLUSTER_A_NAME} _${CLUSTER_A_NAME}_${DATE_TIME}
  else
    echo "# Cluster config (metadata.json) was not found in ${CLUSTER_A_DIR}. Skipping Cluster Destroy."
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
### If Required - Destroy your previous Openstack Cluster B (Private) ###
  prompt "Destroying previous Openstack Cluster B (Private)"
  trap_commands;

  cd ${OCPUP_DIR}
  if [[ -f ${CLUSTER_B_DIR}/metadata.json ]] ; then
    echo -e "# Using an existing OCPUP yaml configuration file: \n${OCPUP_CLUSTER_B_SETUP}"
    # TODO: This YAML file should be copied from a secure path
    cp ${OCPUP_CLUSTER_B_SETUP} ./
    ocpup_yml=$(basename -- "$OCPUP_CLUSTER_B_SETUP")
    ls -l $ocpup_yml

    # ocpup destroy clusters --debug --config $ocpup_yml
    ocpup destroy clusters --config $ocpup_yml & # running on the background (with timeout)
    pid=$! # while the background process runs, tail its log
    # tail --pid=$pid -f .config/cl1/.openshift_install.log && tail -f /proc/$pid/fd/1

    # Wait until the background process finish
    #tail --pid=$pid -f --retry ${OCPUP_DIR}/.config/cl1/.openshift_install.log &
    #tail --pid=$pid -f /dev/null # wait until the background process finish

    timeout --foreground 20m tail --pid=$pid -f --retry ${OCPUP_DIR}/.config/cl1/.openshift_install.log

    # To tail all OpenShift Installer logs (in a new session):
      # find . -name "*openshift_install.log" | xargs tail --pid=$pid -f # tail ocpup/.config/cl1/.openshift_install.log

    # Remove config directory
    mv .config _config
  else
    echo "# Cluster config (metadata.json) was not found in ${CLUSTER_B_DIR}. Skipping Cluster Destroy."
  fi
}


# ------------------------------------------

function clean_aws_cluster_a() {
### Run cleanup of previous Submariner on AWS Cluster A (Public) ###
  prompt "Cleaning previous Submariner (Namespace objects, OLM and CRDs) on AWS Cluster A (Public)"
  kubconf_a;
  delete_submariner_namespace_and_crds;

  prompt "Remove previous Submariner Gateway labels (if exists) on AWS Cluster A (Public)"

  BUG "If one of the gateway nodes does not have external ip, submariner will fail to connect later" \
  "Make sure only 1 node has a gateway label" \
  "https://github.com/submariner-io/submariner-operator/issues/253"
  remove_submariner_gateway_labels

  BUG "Submariner gateway label cannot be removed once created" \
  "No Resolution yet" \
  "https://github.com/submariner-io/submariner/issues/432"

  #TODO: Call kubeconfig of broker cluster
  prompt "Cleaning previous Kubefed (Namespace objects, OLM and CRDs) from the Broker on AWS Cluster A (Public)"
  delete_kubefed_namespace_and_crds
}

# ------------------------------------------

function clean_osp_cluster_b() {
### Run cleanup of previous Submariner on OSP Cluster B (Private) ###
  prompt "Cleaning previous Submariner (Namespace objects, OLM and CRDs) on OSP Cluster B (Private)"
  kubconf_b;
  delete_submariner_namespace_and_crds;

  prompt "Remove previous Submariner Gateway labels (if exists) on OSP Cluster B (Private)"
  remove_submariner_gateway_labels
}

# ------------------------------------------

function delete_kubefed_namespace_and_crds() {
### Run cleanup of previous Kubefed on current KUBECONFIG cluster ###
  # trap_commands;

  BUG "Deploying broker with service-discovery failed since Kubefed ns and crds already exist" \
  "Run cleanup (oc delete) of any existing resource of Kubefed-operator" \
  "https://github.com/submariner-io/submariner-operator/issues/206"

  delete_namespace_and_crds "kubefed-operator" "kubefed"

  BUG "Kubfed cleanup hangs while deleting CRD federatedmulticlusterservices" \
  "Add timeout to the delete command, and ignore exit code" \
  "https://github.com/submariner-io/submariner-operator/issues/251"

}

# ------------------------------------------

function delete_submariner_namespace_and_crds() {
### Run cleanup of previous Submariner on current KUBECONFIG cluster ###
  # trap_commands;

  BUG "Deploying broker will fail if previous submariner-operator namespaces and CRDs already exist" \
  "Run cleanup (oc delete) of any existing resource of submariner-operator" \
  "https://github.com/submariner-io/submariner/issues/88"

  delete_namespace_and_crds "submariner-operator" "submariner"

}

# ------------------------------------------

function remove_submariner_gateway_labels() {
  trap_commands;

  # Remove previous submariner gateway labels from all node in the Cluster:
  ${OC} label --all node submariner.io/gateway-

}

# ------------------------------------------

function install_netshoot_app_on_cluster_a() {
  prompt "Install Netshoot application on AWS Cluster A (Public)"
  trap_commands;

  # Create netshoot app on AWS Cluster A (Public):
  cd $GOPATH/src/github.com/submariner-io/submariner-operator

  #KUBECONFIG=$CLUSTER_A  ${OC} apply -f ./scripts/kind-e2e/netshoot.yaml
  kubconf_a;
  ${OC} delete -f ./scripts/kind-e2e/netshoot.yaml --ignore-not-found # || echo "# OK: Netshoot app does not exist on Cluster A. Installing it..."
  ${OC} apply -f ./scripts/kind-e2e/netshoot.yaml
    # deployment.apps/netshoot created

  # netshoot_app_cluster_a=$(${OC} get pods -l app=netshoot --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')
  ${OC} get pods -l app=netshoot --field-selector status.phase=Running | awk 'FNR == 2 {print $1}' > $TEMP_FILE
  netshoot_app_cluster_a="$(< $TEMP_FILE)"
  echo "# netshoot_app_cluster_a: $netshoot_app_cluster_a"
    # netshoot-785ffd8c8-zv7td

  ${OC} rollout status deployment netshoot
  ${OC} describe pod netshoot
}

# ------------------------------------------

function install_nginx_svc_on_cluster_b() {
  prompt "Install Nginx service on OSP Cluster B (Private)"
  trap_commands;

  # Create nginx service on OSP Cluster B (Private):
  kubconf_b;
  ${OC} delete -f ./scripts/kind-e2e/nginx-demo.yaml --ignore-not-found # || echo "# OK: Nginx service does not exist on Cluster B. Installing it..."
  ${OC} apply -f ./scripts/kind-e2e/nginx-demo.yaml
    # deployment.apps/nginx-demo created
    # service/nginx-demo created

  #${OC} get svc -l app=nginx-demo
  ${OC} rollout status deployment nginx-demo
  ${OC} describe service nginx-demo
}

# ------------------------------------------

function test_clusters_disconnected_before_submariner() {
### Pre-test - Demonstrate that the clusters aren’t connected without Submariner ###
  prompt "Before Submariner is installed: \n"\
  "Verifying that Netshoot app on AWS Cluster A (Public), cannot reach Nginx service on OSP Cluster B (Private)"
  trap_commands;

  # Trying to connect from cluster A to cluster B, will fails (after 5 seconds).
  # It’s also worth looking at the clusters to see that Submariner is nowhere to be seen.

  kubconf_b;
  #${OC} get svc -l app=nginx-demo | awk 'FNR == 2 {print $3}' > $TEMP_FILE
  #nginx_http_cluster_b="$(< $TEMP_FILE)"
  nginx_http_cluster_b=$(${OC} get svc -l app=nginx-demo | awk 'FNR == 2 {print $3}')
    # nginx_http_cluster_b: 100.96.43.129

  kubconf_a;
  netshoot_app_cluster_a=$(${OC} get pods -l app=netshoot --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')
  ${OC} exec $netshoot_app_cluster_a -- curl --output /dev/null --max-time 20 --verbose $nginx_http_cluster_b \
  |& highlight "command terminated with exit code" && echo "# Negative Test OK - Clusters should not be connected without Submariner"
    # command terminated with exit code 28
}

# ------------------------------------------

function open_firewall_ports_on_the_gateway_node() {
### Open AWS Firewall ports on the gateway node with terraform (prep_for_subm.sh) ###
  # Readme: https://github.com/submariner-io/submariner/tree/master/tools/openshift/ocp-ipi-aws
  prompt "Running \"prep_for_subm.sh\" - to open Firewall ports on the Gateway node in AWS Cluster A (Public)"
  trap_commands;

  kubconf_a;
  cd ${CLUSTER_A_DIR}

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
### Label a Gateway node on AWS Cluster A (Public) ###
  prompt "Adding Gateway label to all worker nodes with an external ip on AWS Cluster A (Public)"
  kubconf_a;
  # TODO: Check that the Gateway label was created with "prep_for_subm.sh" on AWS Cluster A (Public) ?
  gateway_label_all_nodes_external_ip
}

function label_first_gateway_cluster_b() {
### Label a Gateway node on OSP Cluster B (Private) ###
  prompt "Adding Gateway label to the first worker node on OSP Cluster B (Private)"
  kubconf_b;
  gateway_label_first_worker_node
}

function gateway_label_first_worker_node() {
### Adding submariner gateway label to the first worker node ###
  trap_commands;

  gw_node1=$(${OC} get nodes -l node-role.kubernetes.io/worker | awk 'FNR == 2 {print $1}')
  echo "# Adding submariner gateway labels to first worker node: $gw_node1"
    # gw_node1: user-cl1-bbmkg-worker-8mx4k

  # TODO: Run only If there's no Gateway label already:
  ${OC} label node $gw_node1 "submariner.io/gateway=true" --overwrite
    # node/user-cl1-bbmkg-worker-8mx4k labeled

  ${OC} get nodes -l "submariner.io/gateway=true" |& highlight "Ready"
      # NAME                          STATUS   ROLES    AGE     VERSION
      # ip-10-0-89-164.ec2.internal   Ready    worker   5h14m   v1.14.6+c07e432da
}

function gateway_label_all_nodes_external_ip() {
### Adding submariner gateway label to all worker nodes with an external IP ###
  trap_commands;

  # Filter all node names that have external IP (column 7 is not none), and ignore header fields:
  watch_for "\${OC} get nodes -l node-role.kubernetes.io/worker -o wide | awk '{print \$7}'" "[0-9]" 200

  gw_nodes=$(${OC} get nodes -l node-role.kubernetes.io/worker -o wide | awk '$7!="<none>" && NR>1 {print $1}')
  echo "# Adding submariner gateway label to all worker nodes with an external IP: $gw_nodes"
    # gw_nodes: user-cl1-bbmkg-worker-8mx4k

  for node in $gw_nodes; do
    # TODO: Run only If there's no Gateway label already:
    ${OC} label node $node "submariner.io/gateway=true" --overwrite
      # node/user-cl1-bbmkg-worker-8mx4k labeled
  done

  ${OC} get nodes -l "submariner.io/gateway=true" |& highlight "Ready"
      # NAME                          STATUS   ROLES    AGE     VERSION
      # ip-10-0-89-164.ec2.internal   Ready    worker   5h14m   v1.14.6+c07e432da
}

# ------------------------------------------

function install_broker_and_member_aws_cluster_a() {
### Installing Submariner Broker on AWS Cluster A (Public) ###
  # TODO - Should test broker deployment also on different Public Cluster (C), rather than on Public Cluster A.
  # TODO: Call kubeconfig of broker cluster

  trap_commands;
  cd ${WORKDIR}
  #cd $GOPATH/src/github.com/submariner-io/submariner-operator

  rm broker-info.subm || echo "# Old broker-info.subm removed."
  DEPLOY_CMD="deploy-broker --dataplane --clusterid ${CLUSTER_A_NAME}-tunnel --ikeport $BROKER_IKEPORT --nattport $BROKER_NATPORT --subm-debug"

  # Deploys the CRDs, creates the SA for the broker, the role and role bindings
  kubconf_a;

  if [[ "$service_discovery" =~ ^(y|yes)$ ]]; then
    prompt "Adding Service-Discovery to Submariner Deploy command"

    BUG "Deploying --service-discovery does not see kubefedctl in current dir" \
    "Install kubefedctl on system PATH as sudo" \
    "https://github.com/submariner-io/submariner-operator/issues/166"

    BUG "kubecontext must be identical to broker-cluster-context, otherwise kubefedctl will fail" \
    "Modify KUBECONFIG context name on the public cluster for the broker, and use the same name for kubecontext and broker-cluster-context" \
    "https://github.com/submariner-io/submariner-operator/issues/193"
    sed -z "s#name: [a-zA-Z0-9-]*\ncurrent-context: [a-zA-Z0-9-]*#name: ${CLUSTER_A_NAME}\ncurrent-context: ${CLUSTER_A_NAME}#" -i.bak ${KUBECONF_CLUSTER_A}

    DEPLOY_CMD="${DEPLOY_CMD} --service-discovery --disable-cvo --kubecontext ${CLUSTER_A_NAME} --broker-cluster-context ${BROKER_CLUSTER_NAME}"
    # subctl deploy-broker --kubecontext <BROKER-CONTEXT-NAME>  --kubeconfig <MERGED-KUBECONFIG> \
    # --dataplane --service-discovery --broker-cluster-context <BROKER-CONTEXT-NAME> --clusterid  <CLUSTER-ID-FOR-TUNNELS>
  fi

  if [[ "$globalnet" =~ ^(y|yes)$ ]]; then
    prompt "Adding globalnet to Submariner Deploy command"
    DEPLOY_CMD="${DEPLOY_CMD} --globalnet"
  fi

  prompt "Deploying Submariner Broker and joining Cluster A"
  subctl ${DEPLOY_CMD}

  ${OC} -n submariner-operator get pods |& highlight "CrashLoopBackOff" && submariner_status=DOWN

  ${OC} -n kubefed-operator get pods |& highlight "CrashLoopBackOff" && submariner_status=DOWN

  # Now looking at cluster A shows that the Submariner broker namespace has been created:
  ${OC} get crds | grep -E 'submariner|kubefed|lighthouse'
      # clusters.submariner.io                                      2019-12-03T16:45:57Z
      # endpoints.submariner.io                                     2019-12-03T16:45:57Z

  [[ "$submariner_status" != DOWN ]] || FATAL "Submariner pod has Crashed - check its logs"
}

# ------------------------------------------

function join_submariner_cluster_b() {
# Install Submariner on OSP Cluster B (Private)
  cd ${WORKDIR}
  prompt "Joining Cluster B to Submariner Broker (on Cluster A), and verifying CRDs"

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

  trap_commands;
  #cd $GOPATH/src/github.com/submariner-io/submariner-operator

  BUG "After deploying broker with Service discovery, Subctl join can fail on \"context does not exist\"" \
  "Subctl join must be specified with broker-cluster-context" \
  "https://github.com/submariner-io/submariner-operator/issues/194"

  BUG "ClusterID must be identical to KUBECONFIG context name, otherwise kubefedctl will fail" \
  "Modify KUBECONFIG context name on the public cluster for the broker, and use the same name for kubecontext and clusterid" \
  "https://github.com/submariner-io/submariner-operator/issues/193"
  sed -z "s#name: [a-zA-Z0-9-]*\ncurrent-context: [a-zA-Z0-9-]*#name: ${CLUSTER_B_NAME}\ncurrent-context: ${CLUSTER_B_NAME}#" -i.bak ${KUBECONF_CLUSTER_B}

  export KUBECONFIG="${KUBECONF_CLUSTER_B}:${KUBECONF_BROKER}"
  ${OC} config view --flatten > ${KUBFED_CONFIG}

  BUG "Multiple Kubconfig cannot have same users (e.g. \"admin\"), otherwise join will fail to get kubefed clientset (Unauthorized)" \
  "Rename username in KUBECONFIG, before joining a new cluster" \
  "https://github.com/submariner-io/submariner-operator/issues/225"

  kubconf_b;
  ${OC} config view --flatten > ${KUBFED_CONFIG}_b
  sed -i 's/admin/kubefed_b/' ${KUBFED_CONFIG}_b
  export KUBECONFIG="${KUBECONF_BROKER}:${KUBFED_CONFIG}_b"
  ${OC} config view --flatten > ${KUBFED_CONFIG}
  # sed -i.bak 's/admin/east/' ${KUBECONF_CLUSTER_A}
  # sed -i.bak 's/admin/west/' ${KUBECONF_CLUSTER_B}
  # sed -i.bak 's/admin/kubefed/' ${KUBFED_CONFIG}

  #export KUBECONFIG="${KUBFED_CONFIG}"
  ${OC} config view

  subctl join --kubecontext ${CLUSTER_B_NAME} --kubeconfig ${KUBFED_CONFIG} \
  --broker-cluster-context ${BROKER_CLUSTER_NAME} --clusterid ${CLUSTER_B_NAME}-tunnel \
  ./broker-info.subm --ikeport $BROKER_IKEPORT --nattport $BROKER_NATPORT --subm-debug

  # subctl join --kubecontext <DATA-CLUSTER-CONTEXT-NAME> --kubeconfig <MERGED-KUBECONFIG> broker-info.subm  \
  # --broker-cluster-context <BROKER-CONTEXT-NAME> --clusterid  <CLUSTER-ID-FOR-TUNNELS>

  BUG "Lighthouse-controller is not reachable between private and public clusters" \
  "Service Discovery fix for Private Clusters" \
  "https://github.com/submariner-io/lighthouse/issues/74"
  export k8sip=$(${OC} --context=${CLUSTER_B_NAME} get svc kubernetes | awk 'FNR == 2 {print $3}')
  ${OC} -n kubefed-operator --context=${BROKER_CLUSTER_NAME} patch kubefedclusters ${CLUSTER_B_NAME}-tunnel \
  --type='json' -p='[{"op": "replace", "path": "/spec/apiEndpoint", "value":"https://'"$k8sip"':443"}]'

  # Check that Submariners CRD has been created on OSP Cluster B (Private):
  ${OC} get crds | grep submariners
      # ...
      # submariners.submariner.io                                   2019-11-28T14:09:56Z

  # Print details of the Operator in OSP Cluster B (Private), and in the Broker Cluster:
  ${OC} get namespace submariner-operator -o json

  ${OC} get Submariner -n submariner-operator -o yaml

  ${OC} get kubefedclusters -n kubefed-operator --context=${BROKER_CLUSTER_NAME}

}

# ------------------------------------------

function test_submariner_engine_status() {
# Check submariner-engine (strongswan status) on Operator pod
  trap_commands;

  # Get some info on installed CRDs
  subctl info
  ${OC} describe cm -n openshift-dns
  ${OC} get pods -n submariner-operator

  # submariner_pod=$(${OC} get pod -n submariner-operator -l app=submariner-engine -o jsonpath="{.items[0].metadata.name}")
  ${OC} get pod -n submariner-operator -l app=submariner-engine -o jsonpath="{.items[0].metadata.name}" > $TEMP_FILE
  submariner_pod="$(< $TEMP_FILE)"

  BUG "strongswan status exit code 3, even when \"security associations\" is up" \
  "Ignore non-zero exit code, by redirecting stderr" \
  "https://github.com/submariner-io/submariner/issues/360"
  ${OC} exec $submariner_pod -n submariner-operator strongswan stroke statusall \
  |& highlight "Security Associations (1 up" || strongswan_status=DOWN
    # Security Associations (1 up, 0 connecting):
    # submariner-cable-subm-cluster-a-10-0-89-164[1]: ESTABLISHED 11 minutes ago, 10.166.0.13[66.187.233.202]...35.171.45.208[35.171.45.208]
    # submariner-child-submariner-cable-subm-cluster-a-10-0-89-164{1}:  INSTALLED, TUNNEL, reqid 1, ESP in UDP SPIs: c9cfd847_i cddea21b_o
    # submariner-child-submariner-cable-subm-cluster-a-10-0-89-164{1}:   10.166.0.13/32 10.252.0.0/14 100.96.0.0/16 === 10.0.89.164/32 10.128.0.0/14 172.30.0.0/16

  BUG "StrongSwan connecting to 'default' URI fails" \
  "Verify StrongSwan with different URI path" \
  "https://github.com/submariner-io/submariner/issues/426"
  ${OC} exec $submariner_pod -n submariner-operator -- bash -c "swanctl --list-sas --uri unix:///var/run/charon.vici" || strongswan_status=DOWN

  if [[ "$strongswan_status" = DOWN ]]; then
  # if receiving: "Security Associations (0 up, 0 connecting)", we need to check Operator pod logs:
  # || : to ignore none-zero exit code
    ${OC} logs $submariner_pod -n submariner-operator |& highlight "received packet" || :
    ${OC} describe pod $submariner_pod -n submariner-operator || :
    ${OC} get Submariner -o yaml || :
    ${OC} get deployments -o yaml -n submariner-operator || :
    ${OC} get pods -o yaml -n submariner-operator || :
    FATAL "Error: Submariner Clusters are not connected."
  fi
}

function test_lighthouse_controller_status() {
  # Check Lighthouse controller status
  prompt "Checking Lighthouse controller status on AWS Cluster A (Public)"
  ${OC} describe multiclusterservices --all-namespaces
  lighthouse_pod=$(${OC} get pod -n kubefed-operator -l app=lighthouse-controller -o jsonpath="{.items[0].metadata.name}")
  ${OC} logs -f $lighthouse_pod -n kubefed-operator --limit-bytes=100000 \
  |& highlight "cluster is not reachable" && lighthouse_status=DOWN || :
  [[ "$lighthouse_status" != DOWN ]] || FATAL "Error: Service-Discovery is not reachable"
  echo "TEST RETURN CODE = $?"
}

# ------------------------------------------

function test_submariner_status_cluster_a() {
# Operator pod status on AWS Cluster A (Public)
  prompt "Checking Submariner engine (strongswan) on AWS Cluster A (Public)"
  kubconf_a;
  test_submariner_engine_status

  # TODO: Should run with broker kubeconfig KUBECONF_BROKER
  [[ ! "$service_discovery" =~ ^(y|yes)$ ]] || test_lighthouse_controller_status
}

# ------------------------------------------

function test_submariner_status_cluster_b() {
# Operator pod status on OSP Cluster B (Private)
  prompt "Checking Submariner engine (strongswan) on OSP Cluster B (Private)"
  kubconf_b;
  test_submariner_engine_status
}

# ------------------------------------------

function test_clusters_connected_by_service_ip() {
### Run Connectivity tests between the Private and Public Clusters ###
# To validate that now Submariner made the connection possible!
  prompt "Testing connectivity with Submariner, between: \n"\
  "Netshoot app on AWS Cluster A (Public) <--> Nginx service on OSP Cluster B (Private)"
  trap_commands;

  kubconf_a;
  # netshoot_app_cluster_a=$(${OC} get pods -l app=netshoot --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')
  ${OC} get pods -l app=netshoot --field-selector status.phase=Running | awk 'FNR == 2 {print $1}' > $TEMP_FILE
  netshoot_app_cluster_a="$(< $TEMP_FILE)"
  echo "# netshoot_app_cluster_a: $netshoot_app_cluster_a"
    # netshoot-785ffd8c8-zv7td

  kubconf_b;
  nginx_http_cluster_b=$(${OC} get svc -l app=nginx-demo | awk 'FNR == 2 {print $3}')
  echo "# Nginx service on Cluster B, will be identified by its IP (without --service-discovery): $nginx_http_cluster_b"
    # nginx_http_cluster_b: 100.96.43.129

  kubconf_a;
  CURL_CMD="${netshoot_app_cluster_a} -- curl --output /dev/null --max-time 30 --verbose ${nginx_http_cluster_b}"

  if [[ "$globalnet" =~ ^(y|yes)$ ]] ; then
    prompt "Testing NO-connectivity if Clusters A and B have Overlapping CIDRs"
    ${OC} exec ${CURL_CMD} |& highlight "port 80: Host is unreachable" \
    && echo -e "# Negative Test OK - Clusters has Overlapping CIDRs. \n" \
    "Nginx Service IP (${nginx_http_cluster_b}) on Cluster B, is not reachable externally."
  else
    ${OC} exec ${CURL_CMD} || \
    BUG "TODO: This will fail User created Clusters with Overlapping CIDRs, while Submariner was not deployed with --globalnet"
      # *   Trying 100.96.72.226:80...
      # * TCP_NODELAY set
      # * Connected to 100.96.72.226 (100.96.72.226) port 80 (#0)
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
  fi

  # if [[ "$service_discovery" =~ ^(y|yes)$ ]]; then
  #   # nginx_http_cluster_b=nginx-demo # this dns name is taken from scripts/kind-e2e/nginx-demo.yaml
  #   netshoot_app_cluster_a=netshoot-cl-a
  #   nginx_http_cluster_b=nginx-cl-b
  #
  #   prompt "Testing Service-Discovery: Nginx service on Cluster B, will be identified by Domain name: $nginx_http_cluster_b"
  #   # echo "# Nginx service on Cluster B, will be identified by its Domain Name (with --service-discovery): $nginx_http_cluster_b"
  #   # ${OC} exec ${netshoot_app_cluster_a} -- curl --output /dev/null --max-time 30 --verbose ${nginx_http_cluster_b}
  #
  #   # Install Ngnix service on OSP Cluster B
  #   kubconf_b; # Can also use --context ${CLUSTER_B_NAME} on all further oc commands
  #   ${OC} delete deployment ${nginx_http_cluster_b} --ignore-not-found
  #   ${OC} create deployment ${nginx_http_cluster_b} --image=nginx
  #
  #   # Expose Ngnix service on port 80
  #   ${OC} delete service ${nginx_http_cluster_b} --ignore-not-found
  #   ${OC} expose deployment ${nginx_http_cluster_b} --port=80 --name=${nginx_http_cluster_b}
  #
  #   # Install Netshoot app on AWS Cluster A, and verify connectivity to Ngnix service on OSP Cluster B
  #   kubconf_a; # Can also use --context ${CLUSTER_A_NAME} on all further oc commands
  #   #${OC} run ${netshoot_app_cluster_a} --generator=run-pod/v1 --image nicolaka/netshoot -- sleep infinity
  #   #${OC} exec ${netshoot_app_cluster_a} -- curl --output /dev/null --max-time 30 --verbose ${nginx_http_cluster_b}
  #
  #   ${OC} run --attach=true --restart=Never --timeout=30s --rm -i --tty --generator=run-pod/v1 \
  #   ${netshoot_app_cluster_a} --image nicolaka/netshoot -- curl --max-time 20 --verbose ${nginx_http_cluster_b}
  #   #${OC} --context ${CLUSTER_A_NAME} run --generator=run-pod/v1 netshoot-app --image nicolaka/netshoot -- \
  #   #bash -c "/bin/bash curl --max-time 30 --verbose ${nginx_http_cluster_b}"
  # fi

}

# ------------------------------------------

function test_clusters_connected_by_service_name() {
### Nginx service on Cluster B, will be identified by its Domain Name, with --service-discovery ###
  trap_commands;

  netshoot_app_cluster_a=netshoot-cl-a
  nginx_http_cluster_b=nginx-cl-b

  prompt "Testing Service-Discovery: Nginx service will be identified by Domain name: $nginx_http_cluster_b"
  # ${OC} exec ${netshoot_app_cluster_a} -- curl --output /dev/null --max-time 30 --verbose ${nginx_http_cluster_b}

  echo "# Install Ngnix service on OSP Cluster B:"
  kubconf_b; # Can also use --context ${CLUSTER_B_NAME} on all further oc commands
  ${OC} delete deployment ${nginx_http_cluster_b} --ignore-not-found
  ${OC} create deployment ${nginx_http_cluster_b} --image=nginx

  echo "# Expose Ngnix service on port 80:"
  ${OC} delete service ${nginx_http_cluster_b} --ignore-not-found
  ${OC} expose deployment ${nginx_http_cluster_b} --port=80 --name=${nginx_http_cluster_b}

  echo "# Wait for Ngnix service to be ready:"
  ${OC} rollout status deployment ${nginx_http_cluster_b}

  # Install Netshoot app on AWS Cluster A, and verify connectivity to Ngnix service on OSP Cluster B
  kubconf_a; # Can also use --context ${CLUSTER_A_NAME} on all further oc commands
  #${OC} run ${netshoot_app_cluster_a} --generator=run-pod/v1 --image nicolaka/netshoot -- sleep infinity
  #${OC} exec ${netshoot_app_cluster_a} -- curl --output /dev/null --max-time 30 --verbose ${nginx_http_cluster_b}

  ${OC} run --attach=true --restart=Never --timeout=30s --rm -i --tty --generator=run-pod/v1 \
  ${netshoot_app_cluster_a} --image nicolaka/netshoot -- curl --max-time 20 --verbose ${nginx_http_cluster_b}

  # TODO: Test connectivity with https://github.com/tsliwowicz/go-wrk
}

# ------------------------------------------

function test_clusters_connected_overlapping_cidrs() {
### Run Connectivity tests between the Private and Public Clusters ###
# To validate that now Submariner made the connection possible!
  prompt "Testing GlobalNet: Nginx service will be identified its Global IP"
  trap_commands;

  kubconf_b;
  #kubconf_b;
  #nginx_http_cluster_b=$(${OC} get svc -l app=nginx-demo | awk 'FNR == 2 {print $3}')
  global_ip=$(${OC} get svc nginx-demo -o jsonpath='{.metadata.annotations.submariner\.io/globalIp}')

  kubconf_a;
  netshoot_app_cluster_a=$(${OC} get pods -l app=netshoot --field-selector status.phase=Running | awk 'FNR == 2 {print $1}')

  echo -e "# Connecting from Netshoot pod [${netshoot_app_cluster_a}] on Cluster A\n" \
  "# To Nginx service on Cluster B, by its Global IP: $global_ip"

  ${OC} exec ${netshoot_app_cluster_a} -- curl --output /dev/null --max-time 30 --verbose ${global_ip}

}

# ------------------------------------------

function run_submariner_unit_tests() {
### Run Submariner Unit tests (mock) ###
  prompt "Running Submariner Unit-Tests"
  trap_commands;
  cd $GOPATH/src/github.com/submariner-io/submariner
  GO111MODULE="on" go test -v ./pkg/... -ginkgo.v -ginkgo.reportFile junit_result.xml \
  || echo "# Warning: Test execution failure occurred"

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

function run_submariner_e2e_tests() {
# Run E2E Tests of Submariner:
  prompt "Running Submariner E2E (End-to-End tests)"
  trap_commands;
  cd $GOPATH/src/github.com/submariner-io/submariner

  BUG "Should be able to use default KUBECONFIGs of OCP installers, with identical context (\"admin\")" \
  "Modify KUBECONFIG context name on Cluster A and B, to be unique (to prevent E2E failure)" \
  "https://github.com/submariner-io/submariner/issues/245"
  sed -z "s#name: [a-zA-Z0-9-]*\ncurrent-context: [a-zA-Z0-9-]*#name: ${CLUSTER_A_NAME}\ncurrent-context: ${CLUSTER_A_NAME}#" -i.bak ${KUBECONF_CLUSTER_A}
  sed -z "s#name: [a-zA-Z0-9-]*\ncurrent-context: [a-zA-Z0-9-]*#name: ${CLUSTER_B_NAME}\ncurrent-context: ${CLUSTER_B_NAME}#" -i.bak ${KUBECONF_CLUSTER_B}

  export KUBECONFIG="${KUBECONF_CLUSTER_A}:${KUBECONF_CLUSTER_B}"

  ${OC} config get-contexts

    # CURRENT   NAME              CLUSTER            AUTHINFO   NAMESPACE
    # *         admin             user-cluster-a   admin
    #           admin_cluster_b   user-cl1         admin

  GO111MODULE="on" go test -v ./test/e2e -args -dp-context ${CLUSTER_A_NAME} -dp-context ${CLUSTER_B_NAME} \
  -connection-timeout 30 -connection-attempts 3 \
  -ginkgo.v -ginkgo.randomizeAllSpecs \
  -ginkgo.reportPassed -ginkgo.reportFile ${WORKDIR}/e2e_junit_result.xml \
  || echo "# Warning: Test execution failure occurred"
}

function upload_test_results_polarion() {
  # Polarion Jump - update test results
    prompt "Polarion Jump - update test results"

  # git clone ssh://user@code.engineering.redhat.com/jump
  # cd jump
  # virtualenv venv
  # source venv/bin/activate
  # python -V
  # ./prepare_pylarion.sh
  # pip install colorlog
  #
  # To upload to this test:
  # https://polarion.engineering.redhat.com/polarion/#/project/RHELOpenStackPlatform/testrun?id=20190815-0853
  #
  # python jump.py --testrun-id="20190815-0853" --xml-file="junit__01.xml" --update_testcases=True --debug=True # --jenkins_build_url=\$BUILD_URL
  #
  # python jump.py --testrun-id="20181118-1147" --xml-file="junit__01.xml" --debug=True # --jenkins_build_url=\$BUILD_URL
  #
  # ./rhos-qe-jenkins/jobs/defaults/include/jump.groovy.inc
}

####################################################################################

### MAIN ###

# Logging main output (enclosed with parenthesis) with tee

LOG_FILE=( ${REPORT_NAME// /_} ) # replace all spaces with _
LOG_FILE=${LOG_FILE}_${DATE_TIME}.log # can also consider adding timestemps with: ts '%H:%M:%.S' -s

(

  # Print planned steps according to CLI/User inputs
  prompt "Input parameters and Test Plan steps"

  echo "# Openshift Clusters creation/cleanup before Submariner deployment:

  AWS Cluster A (Public):
  - destroy_aws_cluster_a: $destroy_cluster_a
  - create_aws_cluster_a: $create_cluster_a
  - clean_aws_cluster_a: $clean_cluster_a

  OSP Cluster B (Private):
  - destroy_osp_cluster_b: $destroy_cluster_b
  - create_osp_cluster_b: $create_cluster_b
  - clean_osp_cluster_b: $clean_cluster_b

  OCP and Submariner setup and test tools:
  - config_golang: $config_golang
  - config_aws_cli: $config_aws_cli
  - download_ocp_installer: $get_ocp_installer
  - build_ocpup_tool_latest: $get_ocpup_tool
  - build_operator_latest: $build_operator
  - build_submariner_e2e_latest: $build_submariner_e2e
  - download_subctl_latest_release: $get_subctl
  - download_kubefedctl_latest: $get_kubefed_tool
  "

  echo "# Submariner deployment and environment setup for the tests:"
  if [[ "$skip_deploy" =~ ^(y|yes)$ ]]; then
    echo -e "\n# Skipping deployment and preparations: $skip_deploy \n"
  else
    echo -e "\n
    - test_kubeconfig_aws_cluster_a
    - test_kubeconfig_osp_cluster_b
    - install_netshoot_app_on_cluster_a
    - install_nginx_svc_on_cluster_b
    - test_clusters_disconnected_before_submariner
    - configure_aws_ports_for_submariner_broker ((\"prep_for_subm.sh\")
    - label_all_gateway_external_ip_cluster_a
    - label_first_gateway_cluster_b
    - test_subctl_command
    - install_broker_and_member_aws_cluster_a
    - join_submariner_cluster_b
    "
    [[ ! "$service_discovery" =~ ^(y|yes)$ ]] || echo "- add service discovery"
    [[ ! "$globalnet" =~ ^(y|yes)$ ]] || echo "- add globalnet"
    # TODO: Should add function to manipulate opetshift clusters yamls, to have overlapping CIDRs
  fi

  echo "# System and functional tests for Submariner:"
  if [[ "$skip_tests" =~ ^(y|yes)$ ]]; then
    echo -e "\n# Skipping tests: $skip_tests \n"
  else
    echo -e "\n
    - (sleep 10m after deployment)
    - test_submariner_status_cluster_a
    - test_submariner_status_cluster_b
    - test_clusters_connected_by_service_ip
    - test_clusters_connected_overlapping_cidrs: $globalnet
    - test_clusters_connected_by_service_name: $service_discovery
    - test_run_submariner_unit_tests
    - test_run_submariner_e2e_tests
    "
  fi

  # Setup and verify environment
  setup_workspace

  # Running download_ocp_installer if requested
  [[ ! "$get_ocp_installer" =~ ^(y|yes)$ ]] || download_ocp_installer

  # Running destroy_aws_cluster_a if requested
  [[ ! "$destroy_cluster_a" =~ ^(y|yes)$ ]] || destroy_aws_cluster_a

  # Running create_aws_cluster_a if requested
  [[ ! "$create_cluster_a" =~ ^(y|yes)$ ]] || create_aws_cluster_a

  [[ "$skip_deploy" =~ ^(y|yes)$ ]] || test_kubeconfig_aws_cluster_a

  # Running build_ocpup_tool_latest if requested
  [[ ! "$get_ocpup_tool" =~ ^(y|yes)$ ]] || build_ocpup_tool_latest

  # Running destroy_osp_cluster_b if requested
  [[ ! "$destroy_cluster_b" =~ ^(y|yes)$ ]] || destroy_osp_cluster_b

  # Running create_osp_cluster_b if requested
  [[ ! "$create_cluster_b" =~ ^(y|yes)$ ]] || create_osp_cluster_b

  [[ "$skip_deploy" =~ ^(y|yes)$ ]] || test_kubeconfig_osp_cluster_b

  ### Cleanup Submariner from all Clusters ###

  # Running clean_aws_cluster_a if requested
  [[ ! "$clean_cluster_a" =~ ^(y|yes)$ ]] || [[ "$destroy_cluster_a" =~ ^(y|yes)$ ]] \
  || clean_aws_cluster_a

  # Running clean_osp_cluster_b if requested
  [[ ! "$clean_cluster_b" =~ ^(y|yes)$ ]] || [[ "$destroy_cluster_b" =~ ^(y|yes)$ ]] \
  || clean_osp_cluster_b

  # Running build_operator_latest if requested
  [[ ! "$build_operator" =~ ^(y|yes)$ ]] || build_operator_latest

  # Running download_subctl_latest_release if requested
  [[ ! "$get_subctl" =~ ^(y|yes)$ ]] || download_subctl_latest_release

  # Running build_submariner_e2e_latest if requested
  [[ ! "$build_submariner_e2e" =~ ^(y|yes)$ ]] || build_submariner_e2e_latest

  # Running download_kubefedctl_latest if requested
  [[ ! "$get_kubefed_tool" =~ ^(y|yes)$ ]] || download_kubefedctl_latest

  ### Running Submariner Deploy ###
  if [[ ! "$skip_deploy" =~ ^(y|yes)$ ]]; then

    install_netshoot_app_on_cluster_a

    install_nginx_svc_on_cluster_b

    test_clusters_disconnected_before_submariner

    open_firewall_ports_on_the_gateway_node

    label_all_gateway_external_ip_cluster_a

    label_first_gateway_cluster_b

    test_subctl_command

    install_broker_and_member_aws_cluster_a

    # join_submariner_cluster_a

    join_submariner_cluster_b

  fi

  ### Running Submariner Tests ###

  # After Submariner deployment - Wait 10 minutes for the Operator pods status to be up
  [[ "$skip_deploy" =~ ^(y|yes)$ ]] || sleep 10m

  if [[ ! "$skip_tests" =~ ^(y|yes)$ ]]; then

    test_kubeconfig_aws_cluster_a

    test_kubeconfig_osp_cluster_b

    test_submariner_status_cluster_a

    test_submariner_status_cluster_b

    test_clusters_connected_by_service_ip

    [[ ! "$globalnet" =~ ^(y|yes)$ ]] || test_clusters_connected_overlapping_cidrs

    [[ ! "$service_discovery" =~ ^(y|yes)$ ]] || test_clusters_connected_by_service_name

    run_submariner_unit_tests

    run_submariner_e2e_tests
  fi

) |& tee $LOG_FILE # can also consider adding timestemps with: ts '%H:%M:%.S' -s

# Create HTML Report from log file (with title extracted from log file name)
#report_name=$(basename $LOG_FILE .log)
#report_name=( ${report_name//_/ } ) # without quotes
#report_name="${report_name[*]^}"
log_to_html $LOG_FILE "$REPORT_NAME"

# Compressing report to tar.gz
report_file=$(ls -1 -t *.html | head -1)
report_archive="${report_file%.*}_${DATE_TIME}.tar.gz"
tar -cvzf "$report_archive" "$report_file"
echo -e "Report file compressed into ${report_archive}. To view in Firefox, run:\n" \
"tar -xvf ${report_archive}; firefox ${report_file}"


# You can find latest script here:
# https://code.engineering.redhat.com/gerrit/gitweb?p=...git;a=blob;f=setup_subm.sh
#
# To create a local script file:
#        > setup_subm.sh; chmod +x setup_subm.sh; vi setup_subm.sh
#
# Execution example:
# Re-creating a new AWS Cluster:
# ./setup_subm.sh --build-e2e --build-operator --destroy-cluster-a --create-cluster-a --clean-cluster-b --service-discovery --globalnet
#
# Using Submariner upstream release (master), and installing on existing AWS Cluster:
# ./setup_subm.sh --build-operator --clean-cluster-a --clean-cluster-b --service-discovery --globalnet
#
# Using the latest formal release of Submariner, and Re-creating a new AWS Cluster:
# ./setup_subm.sh --build-e2e --get-subctl --destroy-cluster-a --create-cluster-a --clean-cluster-b --service-discovery --globalnet
#
