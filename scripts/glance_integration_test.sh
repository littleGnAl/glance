#!/usr/bin/env bash

set -e
set -x

# MY_PATH=$(realpath $(dirname "$0"))
MY_PATH=$(dirname "$0")
# PROJECT_ROOT=${MY_PATH}/..
PLATFORM=$1 # android/ios/macos/windows/web

pushd ${MY_PATH}/../example

export SAVE_DEBUG_GOLDEN="true"

dart pub get
dart run glance_integration_test/glance_integration_test_runner.dart

popd