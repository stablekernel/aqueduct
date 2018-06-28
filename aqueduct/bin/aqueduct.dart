import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/cli/runner.dart';

Future main(List<String> args) async {
  var runner = new Runner();
  var values = runner.options.parse(args);
  exitCode = await runner.process(values);
}

