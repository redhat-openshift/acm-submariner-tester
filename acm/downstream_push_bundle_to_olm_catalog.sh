#!/bin/bash

# source debug.sh
#
# source /usr/local/etc/brew-auth.config

# Expected Env vars examples:
#
# export VERSION="${SUBMARINER_VERSION}"
# export OPERATOR_NAME="submariner"
# export BUNDLE_NAME="submariner-operator-bundle"
# export NAMESPACE="${SUBMARINER_NAMESPACE}"
# export CHANNEL="${SUBMARINER_CHANNEL}"
# export OPERATOR_BUNDLE_SNAPSHOT_IMAGES="${REGISTRY_MIRROR}/rh-osbs/rhacm2-tech-preview-${BUNDLE_NAME}:${VERSION}"
# export OPERATOR_RELATED_IMAGE="submariner-rhel8-operator"
# export SUBSCRIBE=false

wd="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

declare -a installModes=('AllNamespaces' 'SingleNamespace')

USER=''
PASSWORD=''
# OPERATORS_NAMESPACE="openshift-operators"
# MARKETPLACE_NAMESPACE=${NAMESPACE:-openshift-marketplace}
DOCKER_AUTH_FILE="/tmp/docker.config.json"
INSTALL_MODE=${installModes[1]}
BREW_SECRET_NAME='brew-registry'

#CATALOG_SOURCE="quay.io/operatorhubio/catalog:latest"
#CATALOG_SOURCE="registry.redhat.io/openshift4/ose-operator-registry"
#CATALOG_SOURCE="registry.redhat.io/openshift4/ose-service-catalog"
#CATALOG_SOURCE="registry.redhat.io/redhat/redhat-operator-index:${OCP_VER}"
#CATALOG_BINARY="registry-proxy.engineering.redhat.com/rh-osbs/openshift-ose-operator-registry:${OCP_VER}"

#SRC_IMAGE_INDEX="https://brew.registry.redhat.io/rh-osbs/iib:5801"

if [[ -z "${VERSION}" ]] ||
   [[ -z "${OPERATOR_NAME}" ]] ||
   [[ -z "${BUNDLE_NAME}" ]] ||
   [[ -z "${NAMESPACE}" ]] ||
   [[ -z "${CHANNEL}" ]]; then
    error "Required environment variables not loaded"
    error "    VERSION"
    error "    OPERATOR_NAME"
    error "    BUNDLE_NAME"
    error "    NAMESPACE"
    error "    CHANNEL"
    exit 3
fi

BUILD_IIB=${BUILD_IIB:-false}
SUBSCRIBE=${SUBSCRIBE:-true}
OPERATOR_BUNDLE_SNAPSHOT_IMAGES=${OPERATOR_BUNDLE_SNAPSHOT_IMAGES:-''}
OPERATOR_RELATED_IMAGE=${OPERATOR_RELATED_IMAGE:-''}

# login
#docker login registry.redhat.io
#podman login -u $(oc whoami | tr -d ':') -p $(oc whoami -t) --tls-verify=false "${EXTERNAL_OCP_REGISTRY}"
podman login -u ${REGISTRY_USR} -p ${REGISTRY_PWD} --tls-verify=false ${REGISTRY_MIRROR}
oc login -u "${USER}" -p "${PASSWORD}"
OCP_REGISTRY_URL=$(oc registry info --internal)
OCP_IMAGE_INDEX="${OCP_REGISTRY_URL}/${MARKETPLACE_NAMESPACE}/${BUNDLE_NAME}-index:${VERSION}"
OCP_VERSION=$(oc version | grep "Server Version: " | tr -s ' ' | cut -d ' ' -f3 | cut -d '.' -f1,2)
#CATALOG_SOURCE=registry.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION}
CATALOG_SOURCE=${REGISTRY_MIRROR}/rh-osbs/iib-pub:v${OCP_VERSION}
CATALOG_BINARY=${REGISTRY_MIRROR}/rh-osbs/openshift-ose-operator-registry:v${OCP_VERSION}

# Create/switch project
oc new-project ${NAMESPACE} 2>/dev/null || oc project ${NAMESPACE} -q

### Access to private repository
if oc get secret ${BREW_SECRET_NAME} -n ${NAMESPACE} > /dev/null 2>&1; then
  oc delete secret ${BREW_SECRET_NAME} -n ${NAMESPACE} --wait
fi
oc create secret -n ${NAMESPACE} docker-registry ${BREW_SECRET_NAME} --docker-server=${REGISTRY_MIRROR} --docker-username="${REGISTRY_USR}" --docker-password="${REGISTRY_PWD}" --docker-email=${BREW_REGISTRY_EMAIL}

# Set the subscription namespace
subscriptionNamespace=$([ "${INSTALL_MODE}" == "${installModes[0]}" ] && echo "${OPERATORS_NAMESPACE}" || echo "${NAMESPACE}")

# Disable the default remote OperatorHub sources for OLM
oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'

# Delete previous catalogSource and Subscription
oc delete sub/my-subscription -n "${subscriptionNamespace}" --wait > /dev/null 2>&1 || :
oc delete catalogsource/my-catalog-source -n "${MARKETPLACE_NAMESPACE}" --wait > /dev/null 2>&1 || :

if [ "${BUILD_IIB}" = true ]; then

  if [[ -z "${OPERATOR_BUNDLE_SNAPSHOT_IMAGES}" ]]; then
      error "Required environment variables not loaded"
      error "    OPERATOR_BUNDLE_SNAPSHOT_IMAGES"
      exit 3
  fi

  ### Create the docker auth file
  #oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode | jq > ${DOCKER_AUTH_FILE}

  ### pull the image
  #podman login -u ${REGISTRY_USR} -p ${REGISTRY_PWD} --tls-verify=false ${REGISTRY_MIRROR}
  #podman login --authfile ${DOCKER_AUTH_FILE} --tls-verify=false registry.redhat.io
  #podman image pull --creds ${REGISTRY_USR}:${REGISTRY_PWD} --tls-verify=false ${OPERATOR_BUNDLE_SNAPSHOT_IMAGE}

  ### tag the bundle
  # docker tag  ${SRC_IMAGE_INDEX} ${EXTERNAL_OCP_IMAGE_INDEX}
  #podman tag  ${OPERATOR_BUNDLE_SNAPSHOT_IMAGE} ${OPERATOR_BUNDLE_IMAGE}

  ### expose the internal registry
  oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
  #EXTERNAL_OCP_REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')

  ### wait
  if ! (timeout 5m bash -c "until oc registry info --public > /dev/null 2>&1; do sleep 10; done"); then
    error "registry does not have public hostname" && exit 2
  fi
  # todo: wait for the external ocp registry
  info "wait for the external ocp registry url..."
  sleep 1m

  EXTERNAL_OCP_REGISTRY=$(oc registry info --public)
  EXTERNAL_OCP_IMAGE_INDEX="${EXTERNAL_OCP_REGISTRY}/${MARKETPLACE_NAMESPACE}/${BUNDLE_NAME}-index:${VERSION}"

  ### create an index image - start a new index
  # opm index add \
  # --bundles ${OPERATOR_BUNDLE_SNAPSHOT_IMAGES} \
  # --tag "${EXTERNAL_OCP_IMAGE_INDEX}" \
  # --container-tool podman \
  # --permissive \
  # --skip-tls

  ### create an index image - append to an existing index
  # The --binary-image parameter to the opm command is is only required pre-GA.
  opm index add \
  --enable-alpha \
  --bundles ${OPERATOR_BUNDLE_SNAPSHOT_IMAGES} \
  --from-index="${CATALOG_SOURCE}" \
  --binary-image="${CATALOG_BINARY}" \
  --tag "${EXTERNAL_OCP_IMAGE_INDEX}" \
  --container-tool podman \
  --skip-tls \
  --overwrite-latest
  #--permissive # Allow load errors (do not use)

  ### tag the image index
  # docker tag  ${SRC_IMAGE_INDEX} ${EXTERNAL_OCP_IMAGE_INDEX}
  # podman tag  ${SRC_IMAGE_INDEX} ${EXTERNAL_OCP_IMAGE_INDEX}

  ### push the image index
  # docker push ${OCP_IMAGE_INDEX}
  #podman login -u "$(oc whoami | tr -d ':')" -p "$(oc whoami -t)" --tls-verify=false "${EXTERNAL_OCP_REGISTRY}"
  podman image push --creds "$(oc whoami | tr -d ':')":"$(oc whoami -t)" --tls-verify=false "${EXTERNAL_OCP_IMAGE_INDEX}"
  #podman logout ${REGISTRY_MIRROR}
  # oc image mirror "${SRC_IMAGE_INDEX}" "${EXTERNAL_OCP_IMAGE_INDEX}" \
  # -n "${MARKETPLACE_NAMESPACE}" \
  # --keep-manifest-list \
  # --filter-by-os=.* \
  # -a docker.config.json \
  # --insecure

  [ -f ${DOCKER_AUTH_FILE} ] && rm -f ${DOCKER_AUTH_FILE}
else
  SRC_IMAGE_INDEX=$(${wd:?}/downstream_get_latest_iib.sh "${VERSION}" "${BUNDLE_NAME}" | jq -r '.index_image."v'${OCP_VERSION}'"')
  if [ -z "${SRC_IMAGE_INDEX}" ]; then
    if [ -z "${1}" ]; then
      error "SRC_IMAGE_INDEX was not provided" && exit 4
    fi
    SRC_IMAGE_INDEX=${1}
  else
    SRC_IMAGE_INDEX="${REGISTRY_MIRROR}/$(echo ${SRC_IMAGE_INDEX} | cut -d'/' -f2-)"
  fi
  if oc get is "${BUNDLE_NAME}-index" -n ${MARKETPLACE_NAMESPACE} > /dev/null 2>&1; then
    oc delete is "${BUNDLE_NAME}-index" -n ${MARKETPLACE_NAMESPACE} --wait
  fi
  oc import-image "${OCP_IMAGE_INDEX}" --from="${SRC_IMAGE_INDEX}" -n ${MARKETPLACE_NAMESPACE} --confirm | grep -E 'com.redhat.component|version|release|com.github.url|com.github.commit|vcs-ref'
fi

# create the CatalogSource
cat <<EOF | oc apply -n ${MARKETPLACE_NAMESPACE} -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: my-catalog-source
  namespace: ${MARKETPLACE_NAMESPACE}
spec:
  sourceType: grpc
  image: ${OCP_IMAGE_INDEX}
  displayName: Testing Catalog Source
  publisher: Red Hat Partner (Test)
  updateStrategy:
    registryPoll:
      interval: 5m
EOF

# wait
if ! (timeout 5m bash -c "until [[ $(oc get catalogsource -n ${MARKETPLACE_NAMESPACE} my-catalog-source -o jsonpath='{.status.connectionState.lastObservedState}') -eq 'READY' ]]; do sleep 10; done"); then
    error "CatalogSource is not ready"
    exit 1
fi

# test
info "$(oc -n ${MARKETPLACE_NAMESPACE} get catalogsource --ignore-not-found)"
info "$(oc -n ${MARKETPLACE_NAMESPACE} get pods --ignore-not-found)"
info "$( (oc -n ${MARKETPLACE_NAMESPACE} get packagemanifests --ignore-not-found | grep 'Testing Catalog Source') || true)"

if [ "${SUBSCRIBE}" = true ]; then
  if [ "${INSTALL_MODE}" == "${installModes[1]}" ]; then
    # create the OperatorGroup
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: my-group
  namespace: ${NAMESPACE}
spec:
  targetNamespaces:
    - ${NAMESPACE}
EOF

    # test
    info "$(oc get og -n ${NAMESPACE} --ignore-not-found)"
  fi

  # create the Subscription (Approval should be Manual not Automatic in order to pin the bundle version)
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: my-subscription
  namespace: ${subscriptionNamespace}
spec:
  channel: ${CHANNEL}
  installPlanApproval: Manual
  name: ${OPERATOR_NAME}
  source: my-catalog-source
  sourceNamespace: ${MARKETPLACE_NAMESPACE}
  startingCSV: ${OPERATOR_NAME}.${VERSION}
EOF

  # Manual Approve
  oc wait --for condition=InstallPlanPending --timeout=5m -n ${subscriptionNamespace} subs/my-subscription || (error "InstallPlan not found."; podman logout ${REGISTRY_MIRROR}; exit 1)
  installPlan=$(oc get subscriptions.operators.coreos.com my-subscription -n "${subscriptionNamespace}" -o jsonpath='{.status.installPlanRef.name}')
  if [ -n "${installPlan}" ]; then
    oc patch installplan -n "${subscriptionNamespace}" "${installPlan}" -p '{"spec":{"approved":true}}' --type merge
  fi

  # test
  info "$(oc get sub -n "${subscriptionNamespace}" --ignore-not-found)"
  info "$(oc get installplan -n "${subscriptionNamespace}" --ignore-not-found)"
  info "$(oc get csv -n "${subscriptionNamespace}" --ignore-not-found)"
  info "$(oc get pods -n "${subscriptionNamespace}" --ignore-not-found)"
  info "$(oc get pods -n openshift-operator-lifecycle-manager --ignore-not-found)"
  debug "$(oc logs -n openshift-operator-lifecycle-manager deploy/catalog-operator | grep '^E0')"
  debug "$(oc logs -n openshift-operator-lifecycle-manager deploy/olm-operator | grep '^E0')"
fi

if [[ "${BUILD_IIB}" = false ]] && [[ -n "${OPERATOR_RELATED_IMAGE}" ]]; then
  ### Wait for condition
  #oc wait --for condition=pending --timeout=3m -n "${subscriptionNamespace}" csv/${OPERATOR_NAME}.${VERSION} || (podman logout ${REGISTRY_MIRROR}; exit 1)
  #oc wait --for condition=pending --timeout=3m -n "${MARKETPLACE_NAMESPACE}" packagemanifests/${OPERATOR_NAME} || (podman logout ${REGISTRY_MIRROR}; exit 1)
  if ! (timeout 5m bash -c "until oc get packagemanifests/${OPERATOR_NAME} -n ${MARKETPLACE_NAMESPACE} > /dev/null 2>&1; do sleep 10; done"); then
    error "packagemanifests/${OPERATOR_NAME} not found."
    podman logout ${REGISTRY_MIRROR}
    exit 1
  fi
  #OPERATOR_IMAGE_DIGEST="$(oc get csv ${OPERATOR_NAME}.${VERSION} -n "${subscriptionNamespace}" -o json | jq -r '.spec.install.spec.deployments[] | select(.name=="submariner-operator") | .spec.template.spec.containers[] | select(.name=="submariner-operator") | .image' | cut -d '@' -f2)"
  #OPERATOR_IMAGE_DIGEST="$(oc get packagemanifest ${OPERATOR_NAME} -n "${MARKETPLACE_NAMESPACE}" -o json | jq -r '.status.channels[] | select(.currentCSV=="'${OPERATOR_NAME}'.'${VERSION}'") | .currentCSVDesc.relatedImages[]' | grep "${OPERATOR_RELATED_IMAGE}" | cut -d '@' -f2)"
  #OPERATOR_IMAGE_NAME="$(oc get packagemanifest ${OPERATOR_NAME} -n "${MARKETPLACE_NAMESPACE}" -o json | jq -r '.status.channels[] | select(.currentCSV=="'${OPERATOR_NAME}'.'${VERSION}'") | .currentCSVDesc.relatedImages[]' | grep "${OPERATOR_RELATED_IMAGE}" | awk -F/ '{print $NF}' | cut -d '@' -f1)"
  #OPERATOR_IMAGE_URL="${REGISTRY_MIRROR}/$(oc get packagemanifest ${OPERATOR_NAME} -n "${MARKETPLACE_NAMESPACE}" -o json | jq -r '.status.channels[] | select(.currentCSV=="'${OPERATOR_NAME}'.'${VERSION}'") | .currentCSVDesc.relatedImages[]' | grep "${OPERATOR_RELATED_IMAGE}" | cut -d'/' -f2-)"
  #oc import-image "${subscriptionNamespace}/${OPERATOR_IMAGE_NAME}@${OPERATOR_IMAGE_DIGEST}" --from="${OPERATOR_IMAGE_URL}" -n "${subscriptionNamespace}" --confirm | grep -E 'com.redhat.component|version|release|com.github.url|com.github.commit|vcs-ref'
  #  (oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode | jq > /tmp/docker.config.json) && \
  #  sed -i "s/$(oc registry info --internal)/$(oc registry info --public)/g" /tmp/docker.config.json && \
  #  oc image mirror "${OPERATOR_IMAGE_URL}" $(oc registry info --public)/"${subscriptionNamespace}/${OPERATOR_IMAGE_NAME}@${OPERATOR_IMAGE_DIGEST}" \
  #    -n "${subscriptionNamespace}" \
  #    --keep-manifest-list \
  #    --filter-by-os=.* \
  #    -a /tmp/docker.config.json \
  #    --insecure && \
  #  rm /tmp/docker.config.json
fi

podman logout ${REGISTRY_MIRROR}
