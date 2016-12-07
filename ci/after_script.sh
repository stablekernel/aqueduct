#!/usr/bin/env bash

if [ "$TRAVIS_BRANCH" == "master" ]; then
  bash <(curl -s https://codecov.io/bash)
fi