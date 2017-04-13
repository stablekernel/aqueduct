---
layout: page
title: "Running Aqueduct Applications With Standalone Script"
category: deploy
date: 2016-06-19 21:22:35
order: 6
---

You may also run Aqueduct applications with a standalone script, instead of `aqueduct serve`. In fact, `aqueduct serve` creates a temporary Dart script to run the application. That script looks something like this:

```dart
import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:my_application/my_application.dart';

main() async {
  try {
    var app = new Application<MyRequestSink>();
    var config = new ApplicationConfiguration()
      ..port = 8081
      ..configurationFilePath = "config.yaml";

    app.configuration = config;

    await app.start(numberOfInstances: 3);    
  } catch (e, st) {
    await writeError("$e\n $st");
  }
}

Future writeError(String error) async {
  print("$error");
}
```

The `aqueduct serve` command properly exits and reports the error if the application fails to start.

Applications that aren't use `aqueduct serve` must be sure to take appropriate action when the application fails to start such that the runner of the script is aware of the failure. A standalone start script should be placed in the `bin` directory of a project.
