import 'package:aqueduct/src/runtime/app/app.dart';
import 'package:aqueduct/src/runtime/orm/orm.dart';
import 'mirror_impl.dart' as compiler;

class Runtime {
  static Runtime get current {
    return _current ??= compiler.Compiler.compile();
  }

  static set runtime(Runtime runtime) {
    _current = runtime;
  }

  static Runtime _current;

  Map<Type, ChannelRuntime> channels = {};
  Map<Type, ManagedEntityRuntime> managedEntities = {};
  Map<Type, ControllerRuntime> controllers = {};
  Map<Type, SerializableRuntime> serializables = {};
}