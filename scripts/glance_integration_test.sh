#!/usr/bin/env bash

set -e
set -x

MY_PATH=$(dirname "$0")
PLATFORM=${1:-"android"} # android/ios

pushd ${MY_PATH}/../example

export SAVE_DEBUG_GOLDEN="true"

dart pub get
dart run glance_integration_test/glance_integration_test_runner.dart --run-on=$PLATFORM

popd