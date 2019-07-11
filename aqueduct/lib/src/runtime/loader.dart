import 'package:aqueduct/src/compilers/app/application_builder.dart';
import 'package:aqueduct/src/compilers/generator/runtime_generator.dart';
import 'package:aqueduct/src/compilers/orm/data_model_builder.dart';
import 'package:aqueduct/src/runtime/app/app.dart';
import 'package:aqueduct/src/runtime/runtime.dart';

class RuntimeLoader {
  static Runtime load() {
    final out = Runtime();

    final runtimes = <String, RuntimeType>{};
    final app = ApplicationBuilder();
    runtimes.addAll(app.runtimes);
    out.caster = app.caster;

    final dm = DataModelBuilder();
    runtimes.addAll(dm.runtimes);

    out.runtimes = RuntimeTypeCollection(runtimes);

    return out;
  }

  static RuntimeGenerator createGenerator() {
    final app = ApplicationBuilder();
    final dm = DataModelBuilder();
    final out = RuntimeGenerator();

    app.runtimes.forEach((key, runtime) {
      if (runtime is SerializableRuntime) {
        return;
      }
      out.addRuntime(kind: runtime.kind, name: key, source: runtime.source);
    });

    /* app.caster ?? */

    dm.runtimes.forEach((key, runtime) {
      out.addRuntime(kind: runtime.kind, name: key, source: runtime.source);
    });

    return out;
  }
}