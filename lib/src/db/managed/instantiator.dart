import 'dart:mirrors';

import '../db.dart';
import '../query/mapper.dart';

class ManagedInstantiator {
  ManagedInstantiator(this.rootEntity);

  Map<String, Map<dynamic, ManagedObject>> trackedObjects = {};
  List<PropertyToColumnMapper> orderedMappingElements;
  ManagedEntity rootEntity;

  void set properties(List<String> props) {
    orderedMappingElements = mappersForKeys(rootEntity, props);
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

  Map<ManagedPropertyDescription, dynamic> translateValueMap(
      Map<String, dynamic> valueMap) {
    if (valueMap == null) {
      return null;
    }

    var returnMap = <ManagedPropertyDescription, dynamic>{};
    valueMap.forEach((key, value) {
      var property = rootEntity.properties[key];

      if (property == null) {
        throw new QueryException(QueryExceptionEvent.requestFailure,
            message:
                "Property $key in values does not exist on ${rootEntity.tableName}");
      }

      var value = valueMap[key];
      if (property is ManagedRelationshipDescription) {
        if (property.relationshipType != ManagedRelationshipType.belongsTo) {
          return;
        }

        if (value != null) {
          if (value is ManagedObject) {
            value = value[property.destinationEntity.primaryKey];
          } else if (value is Map) {
            value = value[property.destinationEntity.primaryKey];
          } else {
            throw new QueryException(QueryExceptionEvent.internalFailure,
                message:
                    "Property $key on ${rootEntity.tableName} in 'Query.values' must be a 'Map' or ${MirrorSystem.getName(
                    property.destinationEntity.instanceType.simpleName)} ");
          }
        }
      }

      returnMap[property] = value;
    });

    return returnMap;
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
    trackInstance(instance);

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

  void trackInstance(ManagedObject instance) {
    var typeMap = trackedObjects[instance.entity.tableName];
    if (typeMap == null) {
      typeMap = {};
      trackedObjects[instance.entity.tableName] = typeMap;
    }

    typeMap[instance[instance.entity.primaryKey]] = instance;
  }

  ManagedObject getExistingInstance(
      ManagedEntity entity, dynamic primaryKeyValue) {
    var byType = trackedObjects[entity.tableName];
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
