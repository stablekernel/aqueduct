#!/bin/bash

if [[ "$STAGE" == "coverage" && "$TRAVIS_BRANCH" == "master" && "$TRAVIS_PULL_REQUEST" == false ]]; then
  pip install --user awscli
  mkdir -p "$TEST_DIR"/coverage_json
  $HOME/.local/bin/aws s3 sync s3://aqueduct-coverage-storage/coverage "$TEST_DIR"/coverage_json
fi