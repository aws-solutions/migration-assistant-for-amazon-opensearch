#!/bin/bash
# This script runs all tests for the root CDK project,

[ "$DEBUG" == 'true' ] && set -x
set -e

ECR_ACCOUNT="740797759474.dkr.ecr.us-west-2.amazonaws.com"
ECR_REPO_URL="$ECR_ACCOUNT/opensearch-migrations/base-images"

# Check load-images-to-ecr.sh for loading needed images into ECR
pull_from_ecr() {
  local docker_image_tag=$1
  local ecr_image_tag=$2

  echo "Checking for local Docker image: $docker_image_tag"

  # Check if the image exists locally
  if docker image inspect $docker_image_tag >/dev/null 2>&1; then
    echo "Docker image already exists locally."
  else
    echo "Attempting to pull Docker image from ECR: $docker_image_tag"

    docker pull "$ECR_REPO_URL:$ecr_image_tag"
    docker tag "$ECR_REPO_URL:$ecr_image_tag" "$docker_image_tag"
  fi
}

pull_docker_image() {
  local image_name=$1

  echo "Checking for Docker image: $image_name"

  # Check if the image exists locally
  if docker image inspect $image_name >/dev/null 2>&1; then
    echo "Docker image already exists locally."
  else
    echo "Attempting to pull Docker image: $image_name"

    # Try to pull the Docker image
    if docker pull $image_name; then
      echo "Docker image pulled successfully."
    else
      echo "Failed to pull Docker image. Aborting unit tests."
      exit 1
    fi
  fi
}

prepare_jest_coverage_report() {
	local component_name=$1

    if [ ! -d "coverage" ]; then
        echo "ValidationError: Missing required directory coverage after running unit tests"
        exit 129
    fi

	# prepare coverage reports
    rm -fr coverage/lcov-report
    mkdir -p "$coverage_reports_top_path"/jest
    coverage_report_path=$coverage_reports_top_path/jest/$component_name
    rm -fr "$coverage_report_path"
    mv coverage "$coverage_report_path"
}

run_python_tests() {
  local component_path=$1
  local component_name=$2

  echo "------------------------------------------------------------------------------"
  echo "[Test] Run unit test with coverage for $component_name"
  echo "------------------------------------------------------------------------------"
  echo "cd $component_path"
  cd "$component_path"

  echo "python3 -m pip install --upgrade pipenv"
  python3 -m pip install --upgrade pipenv
  echo "pipenv install --deploy --dev"
  pipenv install --deploy --dev
  echo "pipenv run python -m coverage run -m pytest"
  pipenv run python -m coverage run -m pytest

  echo "pipenv run python -m coverage xml --omit '*/tests/*'"
  pipenv run python -m coverage xml --omit "*/tests/*"

  # The coverage module uses absolutes paths in its coverage output. To avoid dependencies of tools (such as SonarQube)
  # on different absolute paths for source directories, this substitution is used to convert each absolute source
  # directory path to the corresponding project relative path. The $source_dir holds the absolute path for source
  # directory.
  sed -i -e "s,<source>$source_dir,<source>source,g" coverage.xml
}


run_gradle_tests() {
  local component_path=$1
  local component_name=$2
  local gradle_arguments=$3

  echo "------------------------------------------------------------------------------"
  echo "[Test] Run unit test with coverage for $component_name"
  echo "------------------------------------------------------------------------------"
  echo "cd $component_path"
  cd "$component_path"

  ./gradlew $gradle_arguments
}

run_npm_tests() {
  local component_path=$1
  local component_name=$2

  echo "------------------------------------------------------------------------------"
  echo "[Test] Run unit test with coverage for $component_name"
  echo "------------------------------------------------------------------------------"
  echo "cd $component_path"
  cd "$component_path"

  # install dependencies
  npm install

  # run unit tests
  npm test

  # prepare coverage reports
  prepare_jest_coverage_report "$component_name"
  rm -rf coverage node_modules package-lock.json
}

check_test_failure() {
  local component_name=$1

  # Check the result of the test and exit if a failure is identified
  if [ $? -eq 0 ]
  then
    echo "Test for $component_name passed"
  else
    echo "******************************************************************************"
    echo "Test FAILED for $component_name"
    echo "******************************************************************************"
    exit 1
  fi
}

if aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin "$ECR_ACCOUNT" && pull_from_ecr "amazonlinux:2023" "amazonlinux-2023"; then
  echo "Successful accessed ECR account $ECR_ACCOUNT and pulled amazonlinux-2023, pulling remaining base images from here..."
  pull_from_ecr "opensearchproject/opensearch:1.3.16" "opensearch-1.3.16"
  pull_from_ecr "opensearchproject/opensearch:2.14.0" "opensearch-2.14.0"
  pull_from_ecr "docker.elastic.co/elasticsearch/elasticsearch-oss:7.10.2" "elasticsearch-oss-7.10.2"
  pull_from_ecr "docker.elastic.co/elasticsearch/elasticsearch:7.17.22" "elasticsearch-7.17.22"
  pull_from_ecr "docker.elastic.co/elasticsearch/elasticsearch:6.8.23" "elasticsearch-6.8.23"
  pull_from_ecr "httpd:alpine" "httpd-alpine"
  pull_from_ecr "alpine:3.16" "alpine-3.16"
  pull_from_ecr "confluentinc/cp-kafka:7.5.0" "cp-kafka-7.5.0"
  pull_from_ecr "ghcr.io/shopify/toxiproxy:latest" "toxiproxy-latest"
else
  echo "Failed to access $ECR_ACCOUNT or pull image from this ECR, will not pull base images from this ECR"
  # com.rfs.framework.SearchClusterContainer Images
  pull_docker_image "docker.elastic.co/elasticsearch/elasticsearch-oss:7.10.2"
  pull_docker_image "docker.elastic.co/elasticsearch/elasticsearch:7.17.22"
  pull_docker_image "docker.elastic.co/elasticsearch/elasticsearch:6.8.23"
  pull_docker_image "opensearchproject/opensearch:1.3.16"
  pull_docker_image "opensearchproject/opensearch:2.14.0"
  # org.opensearch.migrations.trafficcapture.proxyserver.testcontainers.HttpdContainerTestBase
  pull_docker_image "httpd:alpine"
  pull_docker_image "alpine:3.16"
  # org.opensearch.migrations.trafficcapture.proxyserver.testcontainers.KafkaContainerTestBase
  pull_docker_image "confluentinc/cp-kafka:7.5.0"
  # org.opensearch.migrations.trafficcapture.proxyserver.testcontainers.ToxiproxyContainerTestBase
  pull_docker_image "ghcr.io/shopify/toxiproxy:latest"
  # TrafficCapture/dockerSolution/src/main/docker/elasticsearchTestConsole/Dockerfile
  pull_docker_image "amazonlinux:2023"
fi

echo "Images pulled successfully. Continuing to unit tests."

# Run unit tests
echo "Running unit tests"

# Get reference for source folder
source_dir="$(cd $PWD/../source; pwd -P)"
coverage_reports_top_path=$source_dir/test/coverage-reports

run_gradle_tests "$source_dir/opensearch-migrations" "opensearch-migrations" "build copyDependencies mergeJacocoReports -x spotlessCheck"
check_test_failure "opensearch-migrations"

run_python_tests "$source_dir/opensearch-migrations/TrafficCapture/dockerSolution/src/main/docker/migrationConsole/lib/console_link" "ConsoleLibrary"
check_test_failure "ConsoleLibrary"

# Test packages from /source directory
declare -a packages=(
    "solutions-infrastructure" "opensearch-migrations/deployment/cdk/opensearch-service-migration"
)
for package in "${packages[@]}"; do
  package_name=$(echo "$package" | sed 's/.*\///')
  run_npm_tests "$source_dir"/"$package" "$package_name"
  check_test_failure "$package_name"
done
