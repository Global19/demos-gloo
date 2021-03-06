#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

K8S_SECRET_NAME='my-oauth-secret'
POLICY_K8S_CONFIGMAP='allow-jwt'

cleanup_port_forward_deployment 'gateway-proxy'
cleanup_port_forward_deployment 'api-server'

kubectl --namespace="${GLOO_NAMESPACE}" delete \
  --ignore-not-found='true' \
  virtualservice/default \
  "secret/${K8S_SECRET_NAME}"

kubectl --namespace='default' delete \
  --ignore-not-found='true' \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic-db.yaml" \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic.yaml"

cleanup_port_forward_deployment 'dex'

kubectl --namespace="${GLOO_NAMESPACE}" delete \
  --ignore-not-found='true' \
  configmap/"${POLICY_K8S_CONFIGMAP}"

helm delete --purge dex
