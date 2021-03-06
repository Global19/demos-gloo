#!/usr/bin/env bash

# Based on GlooE WAF example
# https://gloo.solo.io/gloo_routing/gateway_configuration/waf/

# brew install kubernetes-cli solo-io/tap/glooctl

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Cleanup previous example runs
kubectl --namespace="${GLOO_NAMESPACE}" delete \
  --ignore-not-found='true' \
  virtualservice/default

# Install example application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

# glooctl create virtualservice \
#   --name='default' \
#   --namespace="${GLOO_NAMESPACE}"

# glooctl add route \
#   --name default \
#   --path-prefix='/' \
#   --dest-name='default-petstore-8080' \
#   --dest-namespace="${GLOO_NAMESPACE}"

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: "${GLOO_NAMESPACE}"
spec:
  displayName: default
  virtualHost:
    domains:
    - '*'
    routes:
    - matchers:
      - prefix: /
      routeAction:
        single:
          upstream:
            name: default-petstore-8080
            namespace: "${GLOO_NAMESPACE}"
    options:
      waf:
        ruleSets:
        - ruleStr: |
            # Turn rule engine on
            SecRuleEngine On
            SecRule REQUEST_HEADERS:User-Agent "nikto" "id:107,phase:1,log,deny,t:lowercase,status:403,msg:'well-known port scanning tool'"
EOF

sleep 10

# kubectl --namespace="${GLOO_NAMESPACE}" get virtualservice/default --output yaml

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petstore --watch='true'

# Wait for Gloo proxy to be fully running
kubectl --namespace="${GLOO_NAMESPACE}" rollout status deployment/gateway-proxy \
  --watch='true'

# Turn on Gloo proxy debug logging
set_gloo_proxy_log_level debug

# Create a background proxy log scrapper
LOGGER_PID_FILE="${SCRIPT_DIR}/logger.pid"
if [[ -f "${LOGGER_PID_FILE}" ]]; then
  xargs kill <"${LOGGER_PID_FILE}" && true # ignore errors
  rm "${LOGGER_PID_FILE}" "${SCRIPT_DIR}/proxy.log"
fi
kubectl --namespace="${GLOO_NAMESPACE}" logs --follow='true' deployment/gateway-proxy >"${SCRIPT_DIR}/proxy.log" &
echo $! >"${LOGGER_PID_FILE}"

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment "${GLOO_NAMESPACE}" 'gateway-proxy' '8080'

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

sleep 10

printf "\nShould return 200 OK\n"
curl --silent --write-out "\n%{http_code}\n" "${PROXY_URL}/api/pets/1"

# Rule 107
printf "\nShould return 403 Forbidden\n"
curl --silent --write-out "\n%{http_code}\n" --header "User-Agent: Nikto" "${PROXY_URL}/api/pets/1"

printf "\nShould return 200 OK\n"
curl --silent --write-out "\n%{http_code}\n" --header "User-Agent: Scott" "${PROXY_URL}/api/pets/1"
