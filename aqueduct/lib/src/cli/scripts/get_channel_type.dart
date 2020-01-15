import 'dart:async';
import 'dart:mirrors';

import 'package:aqueduct/src/application/channel.dart';
import 'package:isolate_executor/isolate_executor.dart';
import 'package:runtime/runtime.dart';

class GetChannelExecutable extends Executable<String> {
  GetChannelExecutable(Map<String, dynamic> message) : super(message);

  @override
  Future<String> execute() async {
    final channels = RuntimeContext.current.runtimes.iterable.whereType<ChannelRuntime>();
    if (channels.length != 1) {
      throw StateError("No ApplicationChannel subclass was found for this project. "
        "Make sure it is imported in your application library file.");
    }
    var runtime = channels.first;

    if (runtime == null) {
      return null;
    }
    return MirrorSystem.getName(reflectClass(runtime.channelType).simpleName);
  }

  static List<String> importsForPackage(String packageName) => [
        "package:aqueduct/aqueduct.dart",
        "package:$packageName/$packageName.dart",
        "package:runtime/runtime.dart"
      ];
}
