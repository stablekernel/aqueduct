import 'dart:mirrors';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/application/channel.dart';
import 'package:aqueduct/src/runtime/app/app.dart';
import 'package:aqueduct/src/runtime/app/mirror.dart';

class ApplicationBuilder {
  ApplicationBuilder() {
    _types = currentMirrorSystem()
      .libraries
      .values
      .where((lib) => lib.uri.scheme == "package" || lib.uri.scheme == "file")
      .expand((lib) => lib.declarations.values)
      .whereType<ClassMirror>().toList();
  }
  
  List<ClassMirror> _types;

  Map<Type, ChannelRuntime> get channels {
    return Map.fromEntries(_subclassesOf(ApplicationChannel).map((t) => MapEntry(t, ChannelRuntimeImpl(t))));
  }

  Map<Type, SerializableRuntime> get serializables {
    return Map.fromEntries(_subclassesOf(Serializable).map((t) => MapEntry(t, SerializableRuntimeImpl(t))));
  }

  Map<Type, ControllerRuntime> get controllers {
    return Map.fromEntries(_subclassesOf(Serializable).map((t) => MapEntry(t, ControllerRuntimeImpl(t))));
  }
  
  List<Type> _subclassesOf(Type type) {
    final mirror = reflectClass(type);
    return _types
        .where((decl) =>
            decl.isSubclassOf(mirror) &&
            decl.reflectedType != type)
        .map((c) => c.reflectedType).toList();
  }
}
