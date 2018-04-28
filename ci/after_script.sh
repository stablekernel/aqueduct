#!/bin/bash

if [[ "$STAGE" == "coverage" && "$TRAVIS_BRANCH" == "master" && "$TRAVIS_PULL_REQUEST" == false ]]; then
  if [ -a "$TEST_DIR"/coverage/lcov.info ]; then
    curl -s https://codecov.io/bash > .codecov
    chmod +x .codecov
    ./.codecov -f "$TEST_DIR"/coverage/lcov.info -X xcode

    rm -rf "$TEST_DIR"/coverage_json
    mkdir "$TEST_DIR"/coverage_json
    $HOME/.local/bin/aws s3 sync "$TEST_DIR"/coverage_json s3://aqueduct-coverage-storage/coverage --delete
  fi
fi

