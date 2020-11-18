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

- Submariner installation options:

  * Install latest release of Submariner:              --install-subctl
  * Install development release of Submariner:         --install-subctl-devel
  * Skip Submariner installation:                      --skip-install
  * Configure and test Service Discovery:              --service-discovery
  * Configure and test GlobalNet:                      --globalnet
  * Use specific IPSec (cable driver):                 --cable-driver [libreswan / strongswan]

- Submariner test options:

  * Run tests with GO (instead of subctl):             --go-tests
  * Skip tests execution (by type):                    --skip-tests [sys / e2e / pkg / all]
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


  `./setup_subm.sh --get-ocp-installer 4.5.1 --reset-cluster-a --clean-cluster-b --install-subctl --service-discovery --go-tests --junit`

  * Download OCP installer version 4.5.1
  * Recreate new cluster on AWS (cluster A)
  * Clean existing cluster on OSP (cluster B)
  * Install latest Submariner (master development)
  * Configure Service-Discovery
  * Build and run Submariner E2E and unit-tests with GO
  * Create Junit tests result (xml files)
