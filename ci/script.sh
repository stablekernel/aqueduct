#!/bin/bash

set -e

if [[ "$STAGE" == "tests" ]]; then
  pub run test -j 1 -r expanded
fi

if [[ "$STAGE" == "coverage" && "$TRAVIS_BRANCH" == "master" && "$TRAVIS_PULL_REQUST" == "false" ]]; then
  dart tool/coverage.dart
fi