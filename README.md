# ocp-multi-cluster-tester
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

- Submariner installation and test options:

  * Install latest release of Submariner:              --install-subctl
  * Install development release of Submariner:         --install-subctl-devel
  * Skip Submariner installation:                      --skip-install
  * Configure and test Service Discovery:              --service-discovery
  * Configure and test GlobalNet:                      --globalnet
  * Use specific IPSec (cable driver):                 --cable-driver [libreswan / strongswan]
  * Build E2E tests of all Submariner repositories:    --build-e2e
  * Skip tests execution (by type):                    --skip-tests [sys / e2e / pkg / all]
  * Print all pods logs on failure:                    --print-logs

- General script options:

* Import additional variables from file:             --import-vars  [variables file path]
* Record Junit Tests result (xml):                   --junit
* Upload Junit results to polarion:                  --polarion
* Show debug info (verbose) for commands:            -d / --debug
* Show this help menu:                               -h / --help


### Command examples:

- To run interactively (user enter options):

  `./setup_subm.sh`


- Example with pre-defined parameters:

  * Download OCP installer version 4.5.1
  * Recreate new cluster on AWS (cluster A)
  * Clean existing cluster on OSP (cluster B)
  * Install latest Submariner release
  * Configure Service-Discovery and GlobalNet
  * Build and run latest E2E tests
  * Create Junit tests result (xml file)

  `./setup_subm.sh --get-ocp-installer 4.5.1 --build-e2e --install-subctl --reset-cluster-a --clean-cluster-b --service-discovery --globalnet --junit`


- Installing latest Submariner (master development), and using existing AWS cluster:

  `./setup_subm.sh --install-subctl-devel --clean-cluster-a --clean-cluster-b --service-discovery --globalnet`


- Installing last Submariner release, and re-creating a new AWS cluster:

  `./setup_subm.sh --build-e2e --install-subctl --reset-cluster-a --clean-cluster-b --service-discovery --globalnet`
