#!/bin/bash

set -e

if [[ "$STAGE" == "tests" ]]; then
  pub run test -j 1 -r expanded
fi

if [[ "$STAGE" == "coverage" && "$TRAVIS_BRANCH" == "master" ]]; then
  dart tool/coverage.dart
  curl -s https://codecov.io/bash > .codecov
  chmod +x .codecov
  ./.codecov -f coverage/lcov.info -X xcode
fi