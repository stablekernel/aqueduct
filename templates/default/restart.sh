#!/usr/bin/env bash

git fetch
git checkout master
git reset --hard
git pull

/usr/lib/dart/bin/pub get

pkill dart
nohup dart bin/start.dart > /dev/null 2>&1 &
