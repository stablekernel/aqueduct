import 'package:aqueduct/src/compilers/app/application_builder.dart';
import 'package:aqueduct/src/compilers/orm/data_model_builder.dart';
import 'package:aqueduct/src/runtime/runtime.dart';

class Compiler {
  static Runtime compile() {
    final out = Runtime();

    final app = ApplicationBuilder();
    out.channels = app.runtimes;

    final dm = DataModelBuilder();
    out.managedEntities = dm.runtimes;

    return out;
  }
}