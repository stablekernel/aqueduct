You may also run Aqueduct applications with a standalone script, instead of `aqueduct serve`. In fact, `aqueduct serve` creates a temporary Dart script to run the application. If you created your application with `aqueduct create`, a standalone already exists in your project named `bin/main.dart`.

A sample script looks like this:

```dart
import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:my_application/my_application.dart';

Future main() async {
  var app = new Application<MyApplicationChannel>()
    ..options.port = 8888
    ..options.configurationFilePath = "config.yaml";

  await app.start(numberOfInstances: 3);    
}
```

This script can be used in place of `aqueduct serve`, but you must configure all `ApplicationOptions` in this script and not through the CLI.
