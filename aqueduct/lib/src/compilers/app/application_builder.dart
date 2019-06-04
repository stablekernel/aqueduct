import 'dart:mirrors';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/application/channel.dart';
import 'package:aqueduct/src/runtime/app/app.dart';
import 'package:aqueduct/src/runtime/app/mirror.dart';
import 'package:aqueduct/src/runtime/runtime.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

class ApplicationBuilder {
  ApplicationBuilder() {
    _types = currentMirrorSystem()
        .libraries
        .values
        .where((lib) => lib.uri.scheme == "package" || lib.uri.scheme == "file")
        .expand((lib) => lib.declarations.values)
        .whereType<ClassMirror>()
        .where((cm) => firstMetadataOfType<PreventCompilation>(cm) == null)
        .toList();
  }

  List<ClassMirror> _types;

  Map<String, ChannelRuntime> get channels {
    return Map.fromEntries(_subclassesOf(ApplicationChannel)
        .map((t) => MapEntry(_getClassName(t), ChannelRuntimeImpl(t))));
  }

  Map<String, SerializableRuntime> get serializables {
    return Map.fromEntries(_subclassesOf(Serializable)
        .map((t) => MapEntry(_getClassName(t), SerializableRuntimeImpl(t))));
  }

  Map<String, ControllerRuntime> get controllers {
    return Map.fromEntries(_subclassesOf(Controller)
        .map((t) => MapEntry(_getClassName(t), ControllerRuntimeImpl(t))));
  }

  T Function<T>(dynamic object, {Type runtimeType}) get caster {
    return <T>(object, {Type runtimeType}) {
      final intoType = reflectType(runtimeType ?? T);
      return _runtimeCast(object, intoType) as T;
    };
  }

  dynamic _runtimeCast(dynamic object, TypeMirror intoType) {
    if (intoType.reflectedType == dynamic) {
      return object;
    }

    final objectType = reflect(object).type;
    if (objectType.isAssignableTo(intoType)) {
      return object;
    }

    if (intoType.isSubtypeOf(reflectType(List))) {
      if (object is! List) {
        throw CastError();
      }

      final elementType = intoType.typeArguments.first;
      final elements = (object as List).map((e) => _runtimeCast(e, elementType));
      return (intoType as ClassMirror).newInstance(#from, [elements]).reflectee;
    } else if (intoType.isSubtypeOf(reflectType(Map, [String, dynamic]))) {
      if (object is! Map<String, dynamic>) {
        throw CastError();
      }

      final output =
      (intoType as ClassMirror).newInstance(const Symbol(""), []).reflectee as Map<String, dynamic>;
      final valueType = intoType.typeArguments.last;
      (object as Map<String, dynamic>).forEach((key, val) {
        output[key] = _runtimeCast(val, valueType);
      });
      return output;
    }

    throw CastError();
  }

  List<ClassMirror> _subclassesOf(Type type) {
    final mirror = reflectClass(type);
    return _types
        .where((decl) {
          if (decl.isAbstract) {
            return false;
          }

          if (!decl.isSubclassOf(mirror)) {
            return false;
          }

          if (decl.hasReflectedType) {
            if (decl.reflectedType == type) {
              return false;
            }
          }

          return true;
        })
        .toList();
  }

  String _getClassName(ClassMirror mirror) {
    return MirrorSystem.getName(mirror.simpleName);
  }
}
