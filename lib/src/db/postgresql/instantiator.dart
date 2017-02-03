import 'dart:mirrors';

import '../db.dart';
import 'postgresql_mapping.dart';

class ManagedInstantiator {
  ManagedInstantiator(this.rootEntity);

  Map<String, Map<dynamic, ManagedObject>> distinctObjects = {};
  List<PropertyToColumnMapper> orderedMappingElements;
  ManagedEntity rootEntity;

  void set properties(List<String> props) {
    orderedMappingElements = mappersForKeys(rootEntity, props);
  }

  List<PropertyToRowMapper> get joinMappers {
    return orderedMappingElements.expand((c) {
      if (c is PropertyToRowMapper) {
        var total = [c];
        total.addAll(c.orderedNestedRowMappings);
        return total;
      }
      return <PropertyToRowMapper>[];
    }).toList();
  }

  List<PropertyToColumnMapper> get flattenedMappingElements {
    return orderedMappingElements.expand((c) {
      if (c is PropertyToRowMapper) {
        return c.flattened;
      }
      return [c];
    }).toList();
  }

  void addJoinElements(List<PropertyToRowMapper> elements) {
    orderedMappingElements.addAll(elements);
  }

  void exhaustNullInstanceIterator(Iterator<dynamic> rowIterator,
      Iterator<PropertyToColumnMapper> mappingIterator) {
    while (mappingIterator.moveNext()) {
      var mapper = mappingIterator.current;
      if (mapper is PropertyToRowMapper) {
        var _ = instanceFromRow(
            rowIterator, mapper.orderedMappingElements.iterator);
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

  void applyRowValuesToInstance(ManagedObject instance,
      PropertyToRowMapper mapper, Iterator<dynamic> rowIterator) {
    if (mapper.flattened.isEmpty) {
      return;
    }

    var innerInstanceWrapper = instanceFromRow(
        rowIterator, mapper.orderedMappingElements.iterator,
        entity: mapper.joinProperty.entity);

    if (mapper.isToMany) {
      // If to many, put in a managed set.
      ManagedSet list = instance[mapper.property.name] ?? new ManagedSet();
      if (innerInstanceWrapper != null && innerInstanceWrapper.isNew) {
        list.add(innerInstanceWrapper.instance);
      }
      instance[mapper.property.name] = list;
    } else {
      var existingInnerInstance = instance[mapper.property.name];

      // If not assigned yet, assign this value (which may be null). If assigned,
      // don't overwrite with a null row that may come after. Once we have it, we have it.
      if (existingInnerInstance == null) {
        instance[mapper.property.name] = innerInstanceWrapper?.instance;
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

  ManagedInstanceWrapper instanceFromRow(Iterator<dynamic> rowIterator,
      Iterator<PropertyToColumnMapper> mappingIterator,
      {ManagedEntity entity}) {
    entity ??= rootEntity;

    // Inspect the primary key first.  We are guaranteed to have the primary key come first in any rowIterator.
    rowIterator.moveNext();
    mappingIterator.moveNext();

    var primaryKeyValue = rowIterator.current;
    if (primaryKeyValue == null) {
      exhaustNullInstanceIterator(rowIterator, mappingIterator);
      return null;
    }

    var alreadyExists = true;
    var instance = getExistingInstance(entity, primaryKeyValue);
    if (instance == null) {
      alreadyExists = false;
      instance = createInstanceWithPrimaryKeyValue(entity, primaryKeyValue);
    }

    while (mappingIterator.moveNext()) {
      var mapper = mappingIterator.current;
      if (mapper is! PropertyToRowMapper) {
        rowIterator.moveNext();
        applyColumnValueToProperty(instance, mapper, rowIterator.current);
      } else if (mapper is PropertyToRowMapper) {
        applyRowValuesToInstance(instance, mapper, rowIterator);
      }
    }

    return new ManagedInstanceWrapper(instance, !alreadyExists);
  }

  List<ManagedObject> instancesForRows(List<List<dynamic>> rows) {
    return rows
        .map((row) =>
            instanceFromRow(row.iterator, orderedMappingElements.iterator))
        .where((wrapper) => wrapper.isNew)
        .map((wrapper) => wrapper.instance)
        .toList();
  }

  ManagedObject getExistingInstance(
      ManagedEntity entity, dynamic primaryKeyValue) {
    var byType = distinctObjects[entity.tableName];
    if (byType == null) {
      return null;
    }

    return byType[primaryKeyValue];
  }
}

class ManagedInstanceWrapper {
  ManagedInstanceWrapper(this.instance, this.isNew);

  bool isNew;
  ManagedObject instance;
}
