#!/usr/bin/env bash

LATEST="latest"
FABRIC8_VERSION=${1:-${FABRIC8_VERSION-$LATEST}}

if [ "$FABRIC8_VERSION" == "$LATEST" ] || [ "$FABRIC8_VERSION" == "" ] ; then
  FABRIC8_VERSION=$(curl -sL http://central.maven.org/maven2/io/fabric8/platform/packages/fabric8-full/maven-metadata.xml | grep '<latest' | cut -f2 -d">"|cut -f1 -d"<")
fi

TEMPLATE="packages/fabric8-full/target/classes/META-INF/fabric8/openshift.yml"

if [ "$FABRIC8_VERSION" == "local" ] ; then
  echo "Installing using a local build"
else
  echo "Installing fabric8 version: ${FABRIC8_VERSION}"
  TEMPLATE="http://central.maven.org/maven2/io/fabric8/platform/packages/fabric8-full/${FABRIC8_VERSION}/fabric8-full-${FABRIC8_VERSION}-openshift.yml"
fi
echo "Using the fabric8 template: ${TEMPLATE}"

APISERVER=$(oc version | grep Server | sed -e 's/.*http:\/\///g' -e 's/.*https:\/\///g')
NODE_IP=$(echo "${APISERVER}" | sed -e 's/:.*//g')
EXPOSER="Route"

echo "Connecting to the API Server at: https://${APISERVER}"
echo "Using Node IP ${NODE_IP} and Exposer strategy: ${EXPOSER}"
echo "Using github client ID: ${GITHUB_OAUTH_CLIENT_ID} and secret: ${GITHUB_OAUTH_CLIENT_SECRET}"

GITHUB_ID="${GITHUB_OAUTH_CLIENT_ID}"
GITHUB_SECRET="${GITHUB_OAUTH_CLIENT_SECRET}"

oc new-project fabric8-system

echo "Applying the fabric8 template ${TEMPLATE}"
oc process -f ${TEMPLATE} -p APISERVER_HOSTPORT=${APISERVER} -p NODE_IP=${NODE_IP} -p EXPOSER=${EXPOSER} -p GITHUB_OAUTH_CLIENT_SECRET=${GITHUB_SECRET} -p GITHUB_OAUTH_CLIENT_ID=${GITHUB_ID} | oc apply -f -

echo "Now adding the OAuthClient and cluster-admin role to the init-tenant service account"
cat <<EOF | oc create -f -
kind: OAuthClient
apiVersion: v1
metadata:
  name: fabric8-online-platform
secret: fabric8
redirectURIs:
- "http://$(oc get route keycloak -o jsonpath="{.spec.host}")/auth/realms/fabric8/broker/openshift-v3/endpoint"
grantMethod: prompt
EOF
oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:$(oc project -q):init-tenant

echo "Deploying fabric8-metrics"
METRICS="packages/metrics/target/classes/META-INF/fabric8/openshift.yml"

if [ "$FABRIC8_VERSION" == "local" ] ; then
  echo "Installing using a local build"
else
  echo "Installing fabric8 version: ${FABRIC8_VERSION}"
  METRICS="http://central.maven.org/maven2/io/fabric8/platform/packages/metrics/${FABRIC8_VERSION}/metrics-${FABRIC8_VERSION}-openshift.yml"
fi

oc apply -f ${METRICS}

FABRIC8_DEVOPS_VERSION=$(curl -sL http://central.maven.org/maven2/io/fabric8/devops/apps/prometheus-blackbox-exporter/maven-metadata.xml | grep '<latest' | cut -f2 -d">"|cut -f1 -d"<")
oc apply -n fabric8-metrics -f http://central.maven.org/maven2/io/fabric8/devops/apps/prometheus-blackbox-exporter/${FABRIC8_DEVOPS_VERSION}/prometheus-blackbox-exporter-${FABRIC8_DEVOPS_VERSION}-openshift.yml 

echo "Please wait while the pods all startup!"
echo
echo "To watch this happening you can type:"
echo "  oc get pod -l provider=fabric8 -w"
echo
echo "Or you can watch in the OpenShift console"
echo
echo "Then you should be able the open the fabric8 console here:"
echo "  http://`oc get route fabric8 --template={{.spec.host}}`/"
