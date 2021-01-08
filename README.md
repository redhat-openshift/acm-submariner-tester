# ocp-multi-cluster-tester
Interactive script to create Openshift multi-clusters on private and public clouds, and test inter-connectivity with Submariner.

Running with pre-defined parameters (optional):

- Openshift setup and environment options:

  * Create AWS cluster A:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--create-cluster-a
  * Create OSP cluster B:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; --create-cluster-b
  * Destroy existing AWS cluster A: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--destroy-cluster-a
  * Destroy existing OSP cluster B:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--destroy-cluster-b
  * Reset (create & destroy) AWS cluster A:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--reset-cluster-a
  * Reset (create & destroy) OSP cluster B: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--reset-cluster-b
  * Clean existing AWS cluster A: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--clean-cluster-a
  * Clean existing OSP cluster B:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--clean-cluster-b
  * Download OCP Installer version:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--get-ocp-installer [latest / x.y.z]
  * Download latest OCPUP Tool:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--get-ocpup-tool
  * Skip OCP clusters setup (destroy/create/clean):&ensp;&ensp;--skip-ocp-setup
  * Install Golang if missing: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; --config-golang
  * Install AWS-CLI and configure access: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--config-aws-cli


- Submariner installation options:

  * Install latest release of Submariner: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--install-subctl
  * Install development release of Submariner: &ensp;&ensp;&ensp;&ensp;&ensp; --install-subctl-devel
  * Override images from a custom registry:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--registry-images
  * Skip Submariner installation: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--skip-install
  * Configure and test Service Discovery: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--service-discovery
  * Configure and test GlobalNet:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--globalnet
  * Use specific IPSec (cable driver):&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; --cable-driver [libreswan / strongswan]


- Submariner test options:

  * Skip tests execution (by type):&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--skip-tests [sys / e2e / pkg / all]
  * Update Git and test with GO (instead of subctl):&ensp; --build-tests
  * Create Junit test results (xml): &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; --junit
  * Upload Junit results to Polarion: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--polarion

- General script options:

  * Import additional variables from file: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; --import-vars&ensp;[variables file path]
  * Print Submariner pods logs on failure:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; --print-logs
  * Show debug info (verbose) for commands:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;-d / --debug
  * Show this help menu:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; -h / --help


### Command examples:

To run interactively (enter options manually):

`./setup_subm.sh`


Examples with pre-defined options:

`./setup_subm.sh --clean-cluster-a --clean-cluster-b --install-subctl-devel --registry-images --globalnet`

  * Reuse (clean) existing clusters
  * Install latest Submariner devel (master development)
  * Override Submariner images from a custom repository (configured in REGISTRY variables)
  * Configure GlobalNet (for overlapping clusters CIDRs)
  * Run Submariner E2E tests (with subctl)


`./setup_subm.sh --get-ocp-installer 4.5.1 --reset-cluster-a --clean-cluster-b --install-subctl --service-discovery --build-tests --junit`

  * Download OCP installer version 4.5.1
  * Recreate new cluster on AWS (cluster A)
  * Clean existing cluster on OSP (cluster B)
  * Install latest Submariner release
  * Configure Service-Discovery
  * Build and run Submariner E2E and unit-tests with GO
  * Create Junit tests result (xml files)
