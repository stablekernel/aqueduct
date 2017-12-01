#!/bin/bash

set -e

if [[ "$STAGE" == "tests" ]]; then
  pub run test -j 1 -r expanded
fi

if [[ "$STAGE" == "coverage" && "$TRAVIS_BRANCH" == "master" && "$TRAVIS_PULL_REQUEST" == false ]]; then
  pub global activate -sgit https://github.com/stablekernel/aqueduct-coverage-tool.git
  pub global run aqueduct_coverage_tool:main
fi