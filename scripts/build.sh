#!/bin/bash

# Copyright 2016 Google Inc. All rights reserved.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

usage() {
  echo "Usage: ${0} -d <docker_namespace> [-t <docker_tag>] [-p <gcp_test_project>]"
  exit 1
}

# Parse arguments to this script
while [[ $# -gt 1 ]]; do
  key="$1"
  case $key in
    -d|--docker-namespace)
    DOCKER_NAMESPACE="$2"
    shift
    ;;
    -t|--tag)
    TAG="$2"
    shift # past argument
    ;;
    -p|--project)
    GCP_TEST_PROJECT="$2"
    shift # past argument
    ;;
    *)
    # unknown option
    usage
    ;;
  esac
  shift
done

dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
projectRoot=${dir}/..
buildConfigDir=${projectRoot}/build/config

RUNTIME_NAME="jetty"
TAG_PREFIX="9.4"
GCP_ZONE="us-east1-b"

sed "s/\[INSERT_GCP_ZONE\]/$GCP_ZONE/g" build/Dockerfile.mvn-gcloud.template > build/Dockerfile.mvn-gcloud

if [ -z "${DOCKER_NAMESPACE}" ]; then
  usage
fi

BUILD_TIMESTAMP="$(date -u +%Y-%m-%d_%H_%M)"
if [ -z "${TAG}" ]; then
  export TAG="${TAG_PREFIX}-${BUILD_TIMESTAMP}"
fi

if [ -z "${GCP_TEST_PROJECT}" ]; then
  GCP_TEST_PROJECT="$(gcloud config list --format='value(core.project)')"
fi

IMAGE="${DOCKER_NAMESPACE}/${RUNTIME_NAME}:${TAG}"
echo "IMAGE: $IMAGE"

STAGING_IMAGE="gcr.io/${GCP_TEST_PROJECT}/${RUNTIME_NAME}_staging:${TAG}"
AE_SERVICE_BASE="$(echo $BUILD_TIMESTAMP | sed 's/_//g')"
TEST_AE_SERVICE_1="${AE_SERVICE_BASE}-v1"
TEST_AE_SERVICE_2="${AE_SERVICE_BASE}-v2"
GKE_TEST_APPLICATION="jetty-integration-test-app-$(date -u +%Y-%m-%d-%H-%M)"
CLUSTER_NAME="jetty-runtime-integration-cluster"

set +e
set -x
gcloud container builds submit \
  --config=${buildConfigDir}/build.yaml \
  --substitutions=\
"_IMAGE=$IMAGE,"\
"_DOCKER_TAG=$TAG,"\
"_STAGING_IMAGE=$STAGING_IMAGE,"\
"_TEST_AE_SERVICE_1=$TEST_AE_SERVICE_1,"\
"_TEST_AE_SERVICE_2=$TEST_AE_SERVICE_2,"\
"_GCP_TEST_PROJECT=$GCP_TEST_PROJECT,"\
"_GCP_ZONE=$GCP_ZONE,"\
"_GKE_TEST_APPLICATION=$GKE_TEST_APPLICATION,"\
"_CLUSTER_NAME=$CLUSTER_NAME,"\
  --timeout=45m \
  ${projectRoot}

testResult=$?

# once build has completed, kick off async cleanup build
gcloud container builds submit \
  --config=${buildConfigDir}/cleanup.yaml \
  --substitutions=\
"_GCP_TEST_PROJECT=$GCP_TEST_PROJECT,"\
"_GCP_ZONE=$GCP_ZONE,"\
"_TEST_AE_SERVICE_1=$TEST_AE_SERVICE_1,"\
"_TEST_AE_SERVICE_2=$TEST_AE_SERVICE_2,"\
"_CLUSTER_NAME=$CLUSTER_NAME,"\
  --async \
  --no-source

exit $testResult
