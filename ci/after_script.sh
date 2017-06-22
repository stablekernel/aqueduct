#!/bin/bash

if [[ "$STAGE" == "coverage" && "$TRAVIS_BRANCH" == "master" ]]; then
  $HOME/.local/bin/aws s3 sync coverage_json s3://aqueduct-coverage-storage/coverage
fi