#!/bin/bash

if [[ "$TRAVIS_BRANCH" == "master" ]]; then
  curl -s https://codecov.io/bash > .codecov
  chmod +x .codecov
  ./.codecov -f coverage/lcov.info -X xcode
fi