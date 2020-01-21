import 'dart:async';
import 'dart:io';

import 'package:runtime/runtime.dart';

Future main(List<String> args) async {
  final f = File(args.first);
  final ctx = BuildContext(
      Directory.current.uri.resolve("lib/").resolve("aqueduct.dart"),
      Directory.current.uri.resolve("_build/"),
      Directory.current.uri.resolve("run"),
      f.readAsStringSync(),
      forTests: true);
  final bm = BuildManager(ctx);
  await bm.build();
}
