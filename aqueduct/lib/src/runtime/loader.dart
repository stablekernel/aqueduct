import 'package:aqueduct/src/compilers/app/application_builder.dart';
import 'package:aqueduct/src/compilers/generator/runtime_generator.dart';
import 'package:aqueduct/src/compilers/orm/data_model_builder.dart';
import 'package:aqueduct/src/runtime/app/app.dart';
import 'package:aqueduct/src/runtime/orm/orm.dart';
import 'package:aqueduct/src/runtime/runtime.dart';

class RuntimeLoader {
  static Runtime load() {
    final out = Runtime();

    final app = ApplicationBuilder();
    out.channels = RuntimeTypeCollection(app.channels);
    out.serializables = RuntimeTypeCollection(app.serializables);
    out.controllers = RuntimeTypeCollection(app.controllers);
    out.caster = app.caster;

    final dm = DataModelBuilder();
    out.managedEntities = RuntimeTypeCollection(dm.runtimes);

    return out;
  }

  static RuntimeGenerator createGenerator() {
    final app = ApplicationBuilder();
    final dm = DataModelBuilder();
    final out = RuntimeGenerator();

    app.channels.forEach((key, runtime) {
      out.addRuntime(ChannelRuntime, key, runtime.source);
    });

    app.serializables.forEach((key, runtime) {
      out.addRuntime(SerializableRuntime, key, runtime.source);
    });

    app.controllers.forEach((key, runtime) {
      out.addRuntime(ControllerRuntime, key, runtime.source);
    });

    /* app.caster ?? */

    dm.runtimes.forEach((key, runtime) {
      out.addRuntime(ManagedEntityRuntime, key, runtime.source);
    });

    return out;
  }
}