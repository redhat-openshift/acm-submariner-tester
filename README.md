# acm-submariner-tester
A framework for testing [Submariner](https://submariner.io) with [Red Hat Advanced Cluster Management for Kubernetes](https://www.redhat.com/en/technologies/management/advanced-cluster-management) (RHACM).

It installs OpenShift clusters on private (on-premise) and public clouds, adds RHACM with Submariner, and tests inter-connectivity between the clusters.

Running with pre-defined parameters (optional):

- Openshift setup and environment options:

  * Reset (destroy & create) OCP cluster A:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--reset-cluster-a [latest / x.y / x.y.z / nightly]
  * Reset (destroy & create) OSP cluster B:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--reset-cluster-b [latest / x.y / x.y.z / nightly]
  * Reset (destroy & create) OCP cluster C:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--reset-cluster-c [latest / x.y / x.y.z / nightly]
  * Destroy existing OCP cluster A:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--destroy-cluster-a
  * Destroy existing OSP cluster B:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--destroy-cluster-b
  * Destroy existing OCP cluster C:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--destroy-cluster-c
  * Re-create OCP cluster A (existing install): &ensp;&ensp;&ensp;&ensp;&ensp;--create-cluster-a
  * Re-create OCP cluster B (existing install): &ensp;&ensp;&ensp;&ensp;&ensp;--create-cluster-b
  * Re-create OCP cluster C (existing install): &ensp;&ensp;&ensp;&ensp;&ensp;--create-cluster-c
  * Delete ACM & Submariner in OCP cluster A: &ensp;&ensp;&ensp;--clean-cluster-a
  * Delete ACM & Submariner in OCP cluster B: &ensp;&ensp;&ensp;--clean-cluster-b
  * Delete ACM & Submariner in OCP cluster C: &ensp;&ensp;&ensp;--clean-cluster-c
  * Install & configure Golang (and other libs): &ensp;&ensp;&ensp;&ensp;--config-golang
  * Set Clouds access (AWS/OSP/GCP/AZURE):&ensp;&ensp;&ensp;&ensp;--config-clouds
  * Skip OCP clusters setup (registry, users, etc.):&ensp;&ensp; --skip-ocp-setup

- Submariner installation options:

  * Install ACM version:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; --acm-version [x.y / x.y.z]
  * Specify ACM images date (default to latest): &ensp;&ensp;&ensp;--acm-date [YYYY-MM-DD]
  * Specify MCE version (default to latest): &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--mce-version [x.y / x.y.z]
  * Specify Submariner version: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; &ensp;--subctl-version [latest / x.y / x.y.z / {tag}]
  * Install Submariner with CLI (default to API): &ensp;&ensp;&ensp;&ensp;--subctl-install
  * Override images from downstream registry:&ensp;&ensp;&ensp;&ensp;--registry-images
  * Set (and test) Submariner with GlobalNet:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--globalnet
  * Set Submariner Network Cable Driver: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--cable-driver [libreswan / vxlan]
  * Join managed cluster A:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--join-cluster-a
  * Join managed cluster B:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--join-cluster-b
  * Join managed cluster C:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--join-cluster-c

- Submariner test options:

  * Skip tests execution (by type): &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--skip-tests [sys / e2e / pkg / all]
  * Update Git and test with GO (instead of subctl): &ensp;--build-tests
  * Create Junit test results (xml): &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--junit
  * Upload Junit results to Polarion: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;--polarion

- General script options:

  * Import additional variables from file:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; --import-vars  [variables file path]
  * Print Submariner pods logs on failure: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp; --print-logs
  * Show debug info (verbose) for commands:&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;-d / --debug
  * Show this help menu: &ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;-h / --help


### Command examples:

To run interactively (enter options manually):

`./setup_subm.sh`


Examples with pre-defined options:

`./setup_subm.sh --clean-cluster-a --clean-cluster-b --acm-version 2.7 --subctl-version 0.14 --registry-images`

  * Reuse (clean) existing clusters
  * Install ACM 2.7.z release (latest Z release)
  * Install Submariner 0.14.z release (latest Z release)
  * Override Submariner images from a custom downstream repository (defined in $REGISTRY variables)
  * Run Submariner E2E tests (with subctl)


`./setup_subm.sh --reset-cluster-c nightly --clean-cluster-a --subctl-version devel --build-tests --junit`

  * Install OCP nightly (RC version) on cluster C, as defined in $CLUSTER_C_YAML variable
  * Clean existing cluster A (which is also the ACM Hub cluster)
  * Install Submariner version "devel" (upstream development branch)
  * Build and run Submariner E2E and unit-tests with GO
  * Create Junit tests result (xml files)
