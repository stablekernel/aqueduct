#!/bin/bash

if [[ "$TRAVIS_BRANCH" == "master" ]]; then
    echo 'ok'
fi

pub run test -j 1 -r expanded
if [[ "$TRAVIS_BRANCH" == "master" ]]; then
  pub global activate -sgit https://github.com/stablekernel/codecov_dart.git
  dart_codecov_generator --report-on=lib/ --verbose --no-html
fi