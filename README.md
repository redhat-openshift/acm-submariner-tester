# ocp-multi-cluster-tester
Interactive script to create Openshift multi-clusters on private and public clouds, and test inter-connectivity with Submariner.

Running with pre-defined parameters (optional):
```
* Show this help menu:                               -h / --help
* Show debug info (verbose) for commands:            -d / --debug
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
* Reset (create & destroy) AWS cluster A:            --reset-cluster-a
* Reset (create & destroy) OSP cluster B:            --reset-cluster-b
* Clean existing AWS cluster A:                      --clean-cluster-a
* Clean existing OSP cluster B:                      --clean-cluster-b
* Install Service-Discovery (lighthouse):            --service-discovery
* Install Global Net:                                --globalnet
* Use specific IPSec (cable driver):                 --cable-driver [libreswan / strongswan]
* Skip Submariner deployment:                        --skip-deploy
* Skip all tests execution:                          --skip-tests [sys / e2e / pkg / all]
* Print all pods logs on failure:                    --print-logs
* Install Golang if missing:                         --config-golang
* Install AWS-CLI and configure access:              --config-aws-cli
* Import additional variables from file:             --import-vars  [Variable file path]
* Record Junit Tests result (xml):                   --junit
* Upload Junit results to polarion:                  --polarion
```

Command examples:

`$ ./setup_subm.sh`

  Will run interactively (user enter choices).

`$ ./setup_subm.sh --get-ocp-installer --ocp-version 4.4.6 --build-e2e --get-subctl --reset-cluster-a --clean-cluster-b --service-discovery --globalnet --junit`

  Will run:
  - Recreate new cluster on AWS (cluster A), with OCP 4.4.6
  - Clean existing cluster on OSP (cluster B)
  - Install latest Submariner release
  - Configure Service-Discovery and GlobalNet
  - Build and run latest E2E tests
  - Create Junit tests result (xml file)
