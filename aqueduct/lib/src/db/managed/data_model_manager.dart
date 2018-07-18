import 'package:aqueduct/src/db/managed/data_model.dart';
import 'package:aqueduct/src/db/managed/entity.dart';
import 'package:aqueduct/src/utilities/reference_counting_list.dart';

class ManagedDataModelManager {
  static ReferenceCountingList<ManagedDataModel> dataModels =
      ReferenceCountingList<ManagedDataModel>();

  static ManagedEntity findEntity(Type type, {ManagedEntity orElse()}) {
    for (final d in ManagedDataModelManager.dataModels) {
      final entity = d.entityForType(type);
      if (entity != null) {
        return entity;
      }
    }

    if (orElse == null) {
      throw StateError(
          "No entity found for '$type. Did you forget to create a 'ManagedContext'?");
    }

    return orElse();
  }

  static void add(ManagedDataModel model) {
    final idx = dataModels.indexOf(model);
    if (idx == -1) {
      dataModels.add(model);
    }

    model.retain();
  }
}
