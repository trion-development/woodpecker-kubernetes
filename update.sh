#!/bin/bash

set -e

if [ -z ${PLUGIN_NAMESPACE} ]; then
  PLUGIN_NAMESPACE="default"
  echo "WARNING: NAMESPACE not defined or empty - using default"
fi

if [ -z ${PLUGIN_KUBERNETES_USER} ]; then
  PLUGIN_KUBERNETES_USER="default"
  echo "WARNING: KUBERNETES_USER not defined or empty - using default"
fi

if [ -z ${PLUGIN_WAIT_TIMEOUT} ]; then
  PLUGIN_WAIT_TIMEOUT=30s
fi

if [ -z ${PLUGIN_DEPLOYMENT} ]; then
  if [ -z ${PLUGIN_STATEFULSET} ]; then
    echo "ERROR: DEPLOYMENT or STATEFULSET variable not defined or empty"
    exit 1
  fi
fi

if [ -z ${PLUGIN_CONTAINER} ]; then
  echo "ERROR: CONTAINER variable not defined or empty"
  exit 1
fi

if [ -z ${PLUGIN_REPO} ]; then
  echo "ERROR: REPO variable not defined or empty"
  exit 1
fi

if [ -z ${PLUGIN_TAG} ]; then
  echo "ERROR: TAG variable not defined or empty"
  exit 1
fi

if [ ! -z ${PLUGIN_KUBERNETES_TOKEN} ]; then
  KUBERNETES_TOKEN=$PLUGIN_KUBERNETES_TOKEN
else
  echo "ERROR: KUBERNETES_TOKEN variable not defined or empty"
  exit 1
fi

if [ ! -z ${PLUGIN_KUBERNETES_SERVER} ]; then
  KUBERNETES_SERVER=$PLUGIN_KUBERNETES_SERVER
else
  echo "WARNING: KUBERNETES_SERVER not defined or empty - using default conf from kubectl"
fi

if [ ! -z ${PLUGIN_KUBERNETES_CERT} ]; then
  KUBERNETES_CERT=${PLUGIN_KUBERNETES_CERT}
fi

kubectl config set-credentials default --token=${KUBERNETES_TOKEN}
if [ ! -z ${KUBERNETES_CERT} ]; then
  echo ${KUBERNETES_CERT} | base64 -d > ca.crt
  kubectl config set-cluster default --server=${KUBERNETES_SERVER} --certificate-authority=ca.crt
else
  echo "WARNING: Using insecure connection to cluster, please define CERT"
  kubectl config set-cluster default --server=${KUBERNETES_SERVER} --insecure-skip-tls-verify=true
fi

kubectl config set-context default --cluster=default --user=${PLUGIN_KUBERNETES_USER}
kubectl config use-context default
kubectl version --short

echo "INFO: Starting Kubernetes resources update"

if [ ! -z ${PLUGIN_USE_STATEFULSET} ]; then
  echo "INFO: Statefulset mode enabled"
  IFS=',' read -r -a STATEFULSETS <<< "${PLUGIN_STATEFULSET}"
  IFS=',' read -r -a CONTAINERS <<< "${PLUGIN_CONTAINER}"
  for DEPLOY in ${STATEFULSETS[@]}; do
    echo "INFO: Updating $DEPLOY on $KUBERNETES_SERVER"
    for CONTAINER in ${CONTAINERS[@]}; do
      echo "INFO: Updating $CONTAINER"
      kubectl -n ${PLUGIN_NAMESPACE} set image statefulset/${DEPLOY} \
        ${CONTAINER}=${PLUGIN_REPO}:${PLUGIN_TAG}
    done
    if [[ ! -z ${PLUGIN_FORCE} ]]; then
      echo "INFO: Forcing redeployment"
      kubectl -n ${PLUGIN_NAMESPACE} rollout restart statefulset/${DEPLOY}
    fi
  done
else
  echo "INFO: Deployment mode enabled"
  IFS=',' read -r -a DEPLOYMENTS <<< "${PLUGIN_DEPLOYMENT}"
  IFS=',' read -r -a CONTAINERS <<< "${PLUGIN_CONTAINER}"
  for DEPLOY in ${DEPLOYMENTS[@]}; do
    echo "INFO: Updating $DEPLOY on $KUBERNETES_SERVER"
    for CONTAINER in ${CONTAINERS[@]}; do
      echo "INFO: Updating $CONTAINER"
      kubectl -n ${PLUGIN_NAMESPACE} set image deployment/${DEPLOY} \
        ${CONTAINER}=${PLUGIN_REPO}:${PLUGIN_TAG}
    done
    if [[ ! -z ${PLUGIN_FORCE} ]]; then
      echo "INFO: Forcing redeployment"
      kubectl -n ${PLUGIN_NAMESPACE} rollout restart deployment/${DEPLOY}
    fi
  done
fi

if [ ! -z ${PLUGIN_WAIT} ]; then
  echo "INFO: Waiting for changes to be performed"
  if [ ! -z ${PLUGIN_USE_STATEFULSET} ]; then
    IFS=',' read -r -a STATEFULSETS <<< "${PLUGIN_STATEFULSET}"
    IFS=',' read -r -a CONTAINERS <<< "${PLUGIN_CONTAINER}"
    for DEPLOY in ${STATEFULSETS[@]}; do
      echo "INFO: Waiting for $DEPLOY"
      kubectl -n ${PLUGIN_NAMESPACE} rollout status \
        --timeout=${PLUGIN_WAIT_TIMEOUT} statefulset/${DEPLOY}
    done
  else
    IFS=',' read -r -a DEPLOYMENTS <<< "${PLUGIN_DEPLOYMENT}"
    IFS=',' read -r -a CONTAINERS <<< "${PLUGIN_CONTAINER}"
    for DEPLOY in ${DEPLOYMENTS[@]}; do
      echo "INFO: Waiting for $DEPLOY"
      kubectl -n ${PLUGIN_NAMESPACE} rollout status \
        --timeout=${PLUGIN_WAIT_TIMEOUT} deployment/${DEPLOY}
    done
  fi
fi

echo "INFO: Kubernetes resources update done"
