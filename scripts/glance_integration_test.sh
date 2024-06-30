#!/usr/bin/env bash

set -e
set -x

MY_PATH=$(realpath $(dirname "$0"))
PROJECT_ROOT=$(realpath ${MY_PATH}/..)
PLATFORM=$1 # android/ios/macos/windows/web

pushd ${MY_PATH}/../example

export SAVE_DEBUG_GOLDEN="true"

# flutter packages get

# flutter build apk --profile --split-debug-info=debug-info-integration --target test_driver/glance_test.dart --no-shrink --no-obfuscate
# flutter build apk --profile --target test_driver/glance_test.dart --extra-gen-snapshot-options=--dwarf-stack-traces,--no-strip,--code-comments,--ignore_unrecognized_flags

# flutter drive \
#     --driver=test_driver/glance_test_test.dart \
#     --use-application-binary=/Users/littlegnal/codes/personal-project/glance_plugin/glance/example/build/app/outputs/flutter-apk/app-profile.apk \
#     --profile \
#     -v

# flutter drive --driver=test_driver/integration_test.dart --target=integration_test/glance_test.dart --profile

dart run integration_test/glance_integration_test_runner.dart

popd