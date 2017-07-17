#!/bin/bash

if [[ "$STAGE" == "coverage" && "$TRAVIS_BRANCH" == "master" && "$TRAVIS_PULL_REQUST" == "false" ]]; then
  pip install --user awscli
  mkdir -p coverage_json
  $HOME/.local/bin/aws s3 sync s3://aqueduct-coverage-storage/coverage coverage_json
fi