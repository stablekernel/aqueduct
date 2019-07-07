import 'package:aqueduct/src/runtime/app/app.dart';
import 'package:aqueduct/src/runtime/orm/orm.dart';
import 'loader.dart' as loader;

typedef Caster = T Function<T>(dynamic object, {Type runtimeType});

class Runtime {
  static Runtime get current {
    return _current ??= loader.RuntimeLoader.load();
  }

  static set runtime(Runtime runtime) {
    _current = runtime;
  }

  static Runtime _current;

  Caster caster;
  RuntimeTypeCollection<ChannelRuntime> channels;
  RuntimeTypeCollection<ManagedEntityRuntime> managedEntities;
  RuntimeTypeCollection<ControllerRuntime> controllers;
  RuntimeTypeCollection<SerializableRuntime> serializables;

  T cast<T>(dynamic object, {Type runtimeType}) {
    return caster(object, runtimeType: runtimeType);
  }
}

class RuntimeTypeCollection<R> {
  RuntimeTypeCollection(this._runtimes);

  Map<String, R> _runtimes;

  Iterable<R> get iterable => _runtimes.values;
  
  R operator [] (Type t) {
    final typeName = t.toString();
    final r = _runtimes[typeName];
    if (r != null) {
      return r;
    }

    final genericIndex = typeName.indexOf("<");
    if (genericIndex == -1) {
      return null;
    }

    final genericTypeName = typeName.substring(0, genericIndex);
    return _runtimes[genericTypeName];
  }
}

class PreventCompilation {
  const PreventCompilation();
}