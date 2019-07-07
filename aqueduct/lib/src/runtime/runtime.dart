import 'package:aqueduct/src/runtime/app/app.dart';
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
  RuntimeTypeCollection runtimes;

  T cast<T>(dynamic object, {Type runtimeType}) {
    return caster(object, runtimeType: runtimeType);
  }
}

class RuntimeTypeCollection {
  RuntimeTypeCollection(this._runtimes);

  Map<String, RuntimeBase> _runtimes;

  Iterable<RuntimeBase> get iterable => _runtimes.values;
  
  RuntimeBase operator [] (Type t) {
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