#!/bin/bash

set -e

pub run test -j 1 -r expanded

if [[ "$TRAVIS_BRANCH" == "master" ]]; then
  dart bin/coverage.dart
fi