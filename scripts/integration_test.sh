#!/usr/bin/env bash

set -e
set -x

MY_PATH=$(realpath $(dirname "$0"))
PROJECT_ROOT=$(realpath ${MY_PATH}/..)
PLATFORM=$1 # android/ios/macos/windows/web

pushd ${MY_PATH}/../example

export SAVE_DEBUG_GOLDEN="true"

# flutter packages get

flutter build apk --release --split-debug-info=debug-info-integration --target integration_test/glance_test.dart

flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/glance_test.dart \
    --use-application-binary=/Users/littlegnal/codes/personal-project/glance_plugin/glance/example/build/app/outputs/flutter-apk/app-release.apk \
    --profile \
    -v

# flutter drive --driver=test_driver/integration_test.dart --target=integration_test/glance_test.dart --profile


popd