import 'package:aqueduct/src/db/managed/builders/entity_builder.dart';

import 'package:aqueduct/src/db/managed/managed.dart';

class DataModelBuilder {
  DataModelBuilder(ManagedDataModel dataModel, List<Type> instanceTypes) {
    _builders = instanceTypes.map((t) => EntityBuilder(dataModel, t)).toList();
    _builders.forEach((b) {
      b.compile(_builders);
    });
    _validate();

    _builders.forEach((b) {
      b.link(_builders.map((eb) => eb.entity).toList());

      final entity = b.entity;
      entities[entity.instanceType.reflectedType] = entity;
      tableDefinitionToEntityMap[entity.tableDefinition.reflectedType] = entity;
    });
  }

  Map<Type, ManagedEntity> entities = {};
  Map<Type, ManagedEntity> tableDefinitionToEntityMap = {};
  List<EntityBuilder> _builders;

  void _validate() {
    // Check for dupe tables
    _builders.forEach((builder) {
      final withSameName = _builders
          .where((eb) => eb.name == builder.name)
          .map((eb) => eb.instanceTypeName)
          .toList();
      if (withSameName.length > 1) {
        throw ManagedDataModelError.duplicateTables(builder.name, withSameName);
      }
    });

    _builders.forEach((b) => b.validate(_builders));
  }
}
