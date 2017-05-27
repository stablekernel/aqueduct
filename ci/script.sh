#!/bin/bash

set -e

pub run test -j 1

if [[ "$TRAVIS_BRANCH" == "master" ]]; then
  dart tool/coverage.dart
fi