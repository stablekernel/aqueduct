import 'dart:io';
import 'dart:async';

import 'package:aqueduct/executable.dart';

main(List<String> args) async {
  var runner = new Runner();
  var values = runner.options.parse(args);
  exitCode = await runner.process(values);
}
