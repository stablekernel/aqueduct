import 'package:aqueduct/src/compilers/app/application_builder.dart';
import 'package:aqueduct/src/compilers/orm/data_model_builder.dart';
import 'package:aqueduct/src/runtime/runtime.dart';

class RuntimeLoader {
  static Runtime load() {
    final out = Runtime();

    final app = ApplicationBuilder();
    out.channels = RuntimeTypeCollection(app.channels);
    out.serializables = RuntimeTypeCollection(app.serializables);
    out.controllers = RuntimeTypeCollection(app.controllers);

    final dm = DataModelBuilder();
    out.managedEntities = RuntimeTypeCollection(dm.runtimes);

    return out;
  }
}