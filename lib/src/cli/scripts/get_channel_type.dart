import 'dart:async';
import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:isolate_executor/isolate_executor.dart';

class GetChannelExecutable extends Executable<String> {
  GetChannelExecutable(Map<String, dynamic> message) : super(message);

  @override
  Future<String> execute() async {
    var channelType = ApplicationChannel.defaultType;

    if (channelType == null) {
      return null;
    }
    return MirrorSystem.getName(reflectClass(channelType).simpleName);
  }

  static List<String> importsForPackage(String packageName) => [
        "package:aqueduct/aqueduct.dart",
        "package:$packageName/$packageName.dart"
      ];
}
