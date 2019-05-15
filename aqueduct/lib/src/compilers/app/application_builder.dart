import 'dart:mirrors';
import 'package:aqueduct/src/application/channel.dart';
import 'package:aqueduct/src/runtime/app/channel.dart';
import 'package:aqueduct/src/runtime/app/mirror.dart';

class ApplicationBuilder {
  ApplicationBuilder();

  Map<Type, ChannelRuntime> get runtimes {
    return Map.fromEntries(_channelTypes?.map((t) => MapEntry(t, ChannelRuntimeImpl(t))));
  }
  static List<Type> get _channelTypes {
    final channelType = reflectClass(ApplicationChannel);
    final classes = currentMirrorSystem()
        .libraries
        .values
        .where((lib) => lib.uri.scheme == "package" || lib.uri.scheme == "file")
        .expand((lib) => lib.declarations.values)
        .whereType<ClassMirror>()
        .where((decl) =>
            decl.isSubclassOf(channelType) &&
            decl.reflectedType != ApplicationChannel)
        .toList();

    return classes.map((c) => c.reflectedType).toList();
  }
}
