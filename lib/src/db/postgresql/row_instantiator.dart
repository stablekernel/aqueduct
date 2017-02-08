import 'package:postgres/postgres.dart';

import '../db.dart';
import 'property_mapper.dart';
import 'query_builder.dart';

abstract class RowInstantiator {
  List<PostgresMapper> get returningOrderedMappers;
  Map<String, Map<dynamic, ManagedObject>> distinctObjects = {};
  ManagedEntity get entity;

  void exhaustNullInstanceIterator(
      Iterator<dynamic> rowIterator, Iterator<PropertyMapper> mappingIterator) {
    while (mappingIterator.moveNext()) {
      var mapper = mappingIterator.current;
      if (mapper is RowMapper) {
        var _ = instanceFromRow(rowIterator,
            (mapper as RowMapper).returningOrderedMappers.iterator);
      } else {
        rowIterator.moveNext();
      }
    }
  }

  void applyColumnValueToProperty(
      ManagedObject instance, PropertyToColumnMapper mapper, dynamic value) {
    if (mapper.property is ManagedRelationshipDescription) {
      // A belongsTo relationship, keep the foreign key.
      if (value != null) {
        ManagedRelationshipDescription relDesc = mapper.property;

        var innerInstance = relDesc.destinationEntity.newInstance();
        innerInstance[relDesc.destinationEntity.primaryKey] = value;
        instance[mapper.property.name] = innerInstance;
      } else {
        // If null, explicitly add null to map so the value is populated.
        instance[mapper.property.name] = null;
      }
    } else {
      instance[mapper.property.name] = value;
    }
  }

  void applyRowValuesToInstance(
      ManagedObject instance, RowMapper mapper, Iterator<dynamic> rowIterator) {
    if (mapper.flattened.isEmpty) {
      return;
    }

    var innerInstanceWrapper = instanceFromRow(
        rowIterator, mapper.returningOrderedMappers.iterator,
        incomingEntity: mapper.joinProperty.entity);

    if (mapper.isToMany) {
      // If to many, put in a managed set.
      ManagedSet list =
          instance[mapper.parentProperty.name] ?? new ManagedSet();
      if (innerInstanceWrapper != null && innerInstanceWrapper.isNew) {
        list.add(innerInstanceWrapper.instance);
      }
      instance[mapper.parentProperty.name] = list;
    } else {
      var existingInnerInstance = instance[mapper.parentProperty.name];

      // If not assigned yet, assign this value (which may be null). If assigned,
      // don't overwrite with a null row that may come after. Once we have it, we have it.
      if (existingInnerInstance == null) {
        instance[mapper.parentProperty.name] = innerInstanceWrapper?.instance;
      }
    }
  }

  ManagedObject createInstanceWithPrimaryKeyValue(
      ManagedEntity entity, dynamic primaryKeyValue) {
    var instance = entity.newInstance();

    instance[entity.primaryKey] = primaryKeyValue;

    var typeMap = distinctObjects[instance.entity.tableName];
    if (typeMap == null) {
      typeMap = {};
      distinctObjects[instance.entity.tableName] = typeMap;
    }

    typeMap[instance[instance.entity.primaryKey]] = instance;

    return instance;
  }

  InstanceWrapper instanceFromRow(
      Iterator<dynamic> rowIterator, Iterator<PropertyMapper> mappingIterator,
      {ManagedEntity incomingEntity}) {
    incomingEntity ??= entity;

    // Inspect the primary key first.  We are guaranteed to have the primary key come first in any rowIterator.
    rowIterator.moveNext();
    mappingIterator.moveNext();

    var primaryKeyValue = rowIterator.current;
    if (primaryKeyValue == null) {
      exhaustNullInstanceIterator(rowIterator, mappingIterator);
      return null;
    }

    var alreadyExists = true;
    var instance = getExistingInstance(incomingEntity, primaryKeyValue);
    if (instance == null) {
      alreadyExists = false;
      instance =
          createInstanceWithPrimaryKeyValue(incomingEntity, primaryKeyValue);
    }

    while (mappingIterator.moveNext()) {
      var mapper = mappingIterator.current;
      if (mapper is! RowMapper) {
        rowIterator.moveNext();
        applyColumnValueToProperty(instance, mapper, rowIterator.current);
      } else if (mapper is RowMapper) {
        applyRowValuesToInstance(instance, mapper as RowMapper, rowIterator);
      }
    }

    return new InstanceWrapper(instance, !alreadyExists);
  }

  List<ManagedObject> instancesForRows(List<List<dynamic>> rows) {
    return rows
        .map((row) =>
            instanceFromRow(row.iterator, returningOrderedMappers.iterator))
        .where((wrapper) => wrapper.isNew)
        .map((wrapper) => wrapper.instance)
        .toList();
  }

  ManagedObject getExistingInstance(
      ManagedEntity incomingEntity, dynamic primaryKeyValue) {
    var byType = distinctObjects[incomingEntity.tableName];
    if (byType == null) {
      return null;
    }

    return byType[primaryKeyValue];
  }
}

class InstanceWrapper {
  InstanceWrapper(this.instance, this.isNew);

  bool isNew;
  ManagedObject instance;
}
