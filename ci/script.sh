#!/bin/bash

set -e

psql -c 'create user dart with createdb;' -U postgres
psql -c "alter user dart with password 'dart';" -U postgres
psql -c 'create database dart_test;' -U postgres
psql -c 'grant all on database dart_test to dart;' -U postgres


cd "$TEST_DIR"

pub get

if [[ "$STAGE" == "tests" ]]; then
  pub run test -j 1 -r expanded
fi

if [[ "$STAGE" == "coverage" && "$TRAVIS_BRANCH" == "master" && "$TRAVIS_PULL_REQUEST" == false ]]; then
  pub global activate -sgit https://github.com/stablekernel/aqueduct-coverage-tool.git
  pub global run aqueduct_coverage_tool:main
fi

cd ..