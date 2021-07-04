# ocp-multi-cluster-tester
Interactive script to create Openshift multi-clusters on private and public clouds, and test inter-connectivity with Submariner.

Running with pre-defined parameters (optional):

- Openshift setup and environment options:

  * Create AWS cluster A: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--create-cluster-a
  * Create OSP cluster B:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--create-cluster-b
  * Create AWS cluster C: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--create-cluster-c
  * Destroy existing AWS cluster A:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--destroy-cluster-a
  * Destroy existing OSP cluster B: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--destroy-cluster-b
  * Destroy existing AWS cluster C:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--destroy-cluster-c
  * Reset (create & destroy) AWS cluster A: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--reset-cluster-a
  * Reset (create & destroy) OSP cluster B:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--reset-cluster-b
  * Reset (create & destroy) AWS cluster C: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--reset-cluster-c
  * Clean existing AWS cluster A:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--clean-cluster-a
  * Clean existing OSP cluster B: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--clean-cluster-b
  * Clean existing AWS cluster C:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--clean-cluster-c
  * Download OCP Installer version: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--get-ocp-installer [latest / x.y.z / nightly]
  * Download latest OCPUP Tool: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--get-ocpup-tool
  * Install Golang if missing:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; --config-golang
  * Install AWS-CLI and configure access:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--config-aws-cli
  * Skip OCP clusters setup (destroy/create/clean): &ensp;--skip-ocp-setup


- Submariner installation options:

  * Download SubCtl version:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--subctl-version [latest / x.y.z / {tag}]
  * Override images from a custom registry: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--registry-images
  * Configure and test GlobalNet: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--globalnet
  * Skip Submariner installation on all clusters: &ensp;&ensp;&ensp;&ensp;&ensp;--skip-install


- Submariner test options:

  * Skip tests execution (by type):&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--skip-tests [sys / e2e / pkg / all]
  * Update Git and test with GO (instead of subctl): &ensp;--build-tests
  * Create Junit test results (xml):&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--junit
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

`./setup_subm.sh --clean-cluster-a --clean-cluster-b --install-version 0.8.1 --registry-images --globalnet`

  * Reuse (clean) existing clusters
  * Install Submariner 0.8.1 release
  * Override Submariner images from a custom repository (configured in REGISTRY variables)
  * Configure GlobalNet (for overlapping clusters CIDRs)
  * Run Submariner E2E tests (with subctl)


`./setup_subm.sh --get-ocp-installer 4.5.1 --reset-cluster-a --clean-cluster-b --install-version subctl-devel --build-tests --junit`

  * Download OCP installer version 4.5.1
  * Recreate new cluster on AWS (cluster A)
  * Clean existing cluster on OSP (cluster B)
  * Install "subctl-devel" (subctl development branch)
  * Build and run Submariner E2E and unit-tests with GO
  * Create Junit tests result (xml files)
