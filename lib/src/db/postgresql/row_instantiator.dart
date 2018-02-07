import '../db.dart';
import 'package:aqueduct/src/db/postgresql/mappers/column.dart';
import 'package:aqueduct/src/db/postgresql/mappers/table.dart';

abstract class RowInstantiator {
  List<PostgresMapper> get returningOrderedMappers;

  Map<EntityTableMapper, Map<dynamic, ManagedObject>> distinctObjects = {};

  EntityTableMapper get rootTableMapper;

  List<ManagedObject> instancesForRows(List<List<dynamic>> rows) {
    try {
      return rows
          .map((row) => instanceFromRow(row.iterator, returningOrderedMappers.iterator))
          .where((wrapper) => wrapper.isNew)
          .map((wrapper) => wrapper.instance)
          .toList();
    } on ValidationException catch (e) {
      throw new StateError("Database error when retrieving value. ${e.toString()}");
    }
  }

  InstanceWrapper instanceFromRow(Iterator<dynamic> rowIterator, Iterator<ColumnMapper> mappingIterator,
      {EntityTableMapper forTableMapper}) {
    forTableMapper ??= rootTableMapper;

    // Inspect the primary key first.  We are guaranteed to have the primary key come first in any rowIterator.
    rowIterator.moveNext();
    mappingIterator.moveNext();

    var primaryKeyValue = rowIterator.current;
    if (primaryKeyValue == null) {
      exhaustNullInstanceIterator(rowIterator, mappingIterator);
      return null;
    }

    var alreadyExists = true;
    var instance = getExistingInstance(forTableMapper, primaryKeyValue);
    if (instance == null) {
      alreadyExists = false;
      instance = createInstanceWithPrimaryKeyValue(forTableMapper, primaryKeyValue);
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

  ManagedObject createInstanceWithPrimaryKeyValue(EntityTableMapper tableMapper, dynamic primaryKeyValue) {
    var instance = tableMapper.entity.newInstance();

    instance[tableMapper.entity.primaryKey] = primaryKeyValue;

    var typeMap = distinctObjects[tableMapper];
    if (typeMap == null) {
      typeMap = {};
      distinctObjects[tableMapper] = typeMap;
    }

    typeMap[instance[instance.entity.primaryKey]] = instance;

    return instance;
  }

  ManagedObject getExistingInstance(EntityTableMapper tableMapper, dynamic primaryKeyValue) {
    var byType = distinctObjects[tableMapper];
    if (byType == null) {
      return null;
    }

    return byType[primaryKeyValue];
  }

  void applyRowValuesToInstance(ManagedObject instance, RowMapper mapper, Iterator<dynamic> rowIterator) {
    if (mapper.flattened.isEmpty) {
      return;
    }

    var innerInstanceWrapper =
        instanceFromRow(rowIterator, mapper.returningOrderedMappers.iterator, forTableMapper: mapper);

    if (mapper.isToMany) {
      // If to many, put in a managed set.
      ManagedSet list = instance[mapper.joiningProperty.name] ?? new ManagedSet();
      if (innerInstanceWrapper != null && innerInstanceWrapper.isNew) {
        list.add(innerInstanceWrapper.instance);
      }
      instance[mapper.joiningProperty.name] = list;
    } else {
      var existingInnerInstance = instance[mapper.joiningProperty.name];

      // If not assigned yet, assign this value (which may be null). If assigned,
      // don't overwrite with a null row that may come after. Once we have it, we have it.

      // Now if it is belongsTo, we may have already populated it with the foreign key object.
      // In this case, we do need to override it
      if (existingInnerInstance == null) {
        instance[mapper.joiningProperty.name] = innerInstanceWrapper?.instance;
      }
    }
  }

  void applyColumnValueToProperty(ManagedObject instance, ColumnMapper mapper, dynamic value) {
    var desc = mapper.property;

    if (desc is ManagedRelationshipDescription) {
      // This is a belongsTo relationship (otherwise it wouldn't be a column), keep the foreign key.
      // However, if we are later going to get these values and more from a join,
      // we need ignore it here.
      if (!mapper.fetchAsForeignKey) {
        if (value != null) {
          var innerInstance = desc.destinationEntity.newInstance();
          innerInstance[desc.destinationEntity.primaryKey] = value;
          instance[desc.name] = innerInstance;
        } else {
          // If null, explicitly add null to map so the value is populated.
          instance[desc.name] = null;
        }
      }
    } else if (desc is ManagedAttributeDescription) {
      instance[desc.name] = mapper.convertValueFromStorage(value);
    }
  }

  void exhaustNullInstanceIterator(Iterator<dynamic> rowIterator, Iterator<ColumnMapper> mappingIterator) {
    while (mappingIterator.moveNext()) {
      var mapper = mappingIterator.current;
      if (mapper is RowMapper) {
        var _ = instanceFromRow(rowIterator, (mapper as RowMapper).returningOrderedMappers.iterator);
      } else {
        rowIterator.moveNext();
      }
    }
  }
}

class InstanceWrapper {
  InstanceWrapper(this.instance, this.isNew);

  bool isNew;
  ManagedObject instance;
}
