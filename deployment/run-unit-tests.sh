#!/bin/bash
# This script runs all tests for the root CDK project,

[ "$DEBUG" == 'true' ] && set -x
set -e


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

  python3 -m venv .venv
  source .venv/bin/activate
  pip install -r requirements.txt
  pip install -r dev-requirements.txt
  python3 -m coverage run -m unittest
  python3 -m coverage xml --omit "*/tests/*"
  # The coverage module uses absolutes paths in its coverage output. To avoid dependencies of tools (such as SonarQube)
  # on different absolute paths for source directories, this substitution is used to convert each absolute source
  # directory path to the corresponding project relative path. The $source_dir holds the absolute path for source
  # directory.
  sed -i -e "s,<source>$source_dir,<source>source,g" coverage.xml
  deactivate
  rm -rf .venv
}


run_gradle_tests() {
  local component_path=$1
  local component_name=$2

  echo "------------------------------------------------------------------------------"
  echo "[Test] Run unit test with coverage for $component_name"
  echo "------------------------------------------------------------------------------"
  echo "cd $component_path"
  cd "$component_path"

  ./gradlew build copyDependencies jacocoTestReport
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

# Run unit tests
echo "Running unit tests"

# Get reference for source folder
source_dir="$(cd $PWD/../source; pwd -P)"
coverage_reports_top_path=$source_dir/test/coverage-reports

run_gradle_tests "$source_dir/opensearch-migrations/TrafficCapture" "TrafficCapture"
check_test_failure "TrafficCapture"

run_python_tests "$source_dir/opensearch-migrations/FetchMigration/python" "FetchMigration"
check_test_failure "FetchMigration"

# Test packages from /source directory
declare -a packages=(
    "solutions-infrastructure" "opensearch-migrations/deployment/cdk/opensearch-service-migration"
)
for package in "${packages[@]}"; do
  package_name=$(echo "$package" | sed 's/.*\///')
  run_npm_tests "$source_dir"/"$package" "$package_name"
  check_test_failure "$package_name"
done
