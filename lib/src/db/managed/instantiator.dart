import 'dart:mirrors';
import '../db.dart';

class ManagedInstantiator {
  ManagedInstantiator(this.rootEntity);

  Map<String, Map<dynamic, ManagedObject>> matchMap = {};
  List<PropertyToColumnMapper> orderedMappingElements;
  ManagedEntity rootEntity;

  void set properties(List<String> props) {
    orderedMappingElements = PropertyToColumnMapper.mappersForKeys(rootEntity, props);
  }

  List<PropertyToColumnMapper> get flattenedMappingElements {
    return orderedMappingElements.expand((c) {
      if (c is PropertyToRowMapping) {
        return c.flattened;
      }
      return [c];
    }).toList();
  }

  void addJoinElements(List<PropertyToRowMapping> elements) {
    orderedMappingElements.addAll(elements);
  }

  Map<ManagedPropertyDescription, dynamic> propertyValueMap(Map<String, dynamic> valueMap) {
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
                "Property $key on ${rootEntity.tableName} in Query values must be a Map or ${MirrorSystem.getName(
                    property.destinationEntity.instanceType.simpleName)} ");
          }
        }
      }

      returnMap[property] = value;
    });

    return returnMap;
  }

  ManagedInstanceWrapper instanceFromRow(Iterator<dynamic> rowIterator, Iterator<PropertyToColumnMapper> mappingIterator, {ManagedEntity entity}) {
    entity ??= rootEntity;

    // Inspect the primary key first.  We are guaranteed to have the primary key come first in any rowIterator.
    rowIterator.moveNext();
    mappingIterator.moveNext();

    var primaryKeyValue = rowIterator.current;
    if (primaryKeyValue == null) {
      while (mappingIterator.moveNext()) {
        var mapper = mappingIterator.current;
        if (mapper is PropertyToRowMapping) {
          var _ = instanceFromRow(rowIterator, mapper.orderedMappingElements.iterator, entity: entity);
        } else {
          rowIterator.moveNext();
        }
      }
      return null;
    }

    var alreadyExists = true;
    var instance = existingInstance(entity, primaryKeyValue);
    if (instance == null) {
      alreadyExists = false;
      instance = entity.newInstance();
      instance[entity.primaryKey] = primaryKeyValue;
      trackInstance(instance);
    }

    while (mappingIterator.moveNext()) {
      var mapper = mappingIterator.current;
      if (mapper is! PropertyToRowMapping) {
        rowIterator.moveNext();

        if (mapper.property is ManagedRelationshipDescription) {
          // A belongsTo relationship, keep the foreign key.
          if (rowIterator.current != null) {
            ManagedRelationshipDescription relDesc = mapper.property;
            ManagedObject innerInstance = relDesc.destinationEntity.newInstance();
            innerInstance[relDesc.destinationEntity.primaryKey] = rowIterator.current;
            instance[mapper.property.name] = innerInstance;
          } else {
            instance[mapper.property.name] = null;
          }
        } else {
          instance[mapper.property.name] = rowIterator.current;
        }
      } else if (mapper is PropertyToRowMapping) {
        var innerInstanceWrapper = instanceFromRow(
            rowIterator, mapper.orderedMappingElements.iterator, entity: mapper.joinProperty.entity);


        if (mapper.isToMany) {
          ManagedSet list = instance[mapper.property.name] ?? new ManagedSet();
          if (innerInstanceWrapper != null && innerInstanceWrapper.isNew) {
            list.add(innerInstanceWrapper.instance);
          }
          instance[mapper.property.name] = list;
        } else {
          var existingInnerInstance = instance[mapper.property.name];

          if (existingInnerInstance == null) {
            instance[mapper.property.name] = innerInstanceWrapper?.instance;
          }
        }
      }
    }

    return new ManagedInstanceWrapper(instance, !alreadyExists);
  }

  List<ManagedObject> instancesForRows(List<List<dynamic>> rows) {
    return rows
      .map((row) => instanceFromRow(row.iterator, orderedMappingElements.iterator))
      .where((wrapper) => wrapper.isNew)
      .map((wrapper) => wrapper.instance)
      .toList();
  }

  void trackInstance(ManagedObject instance) {
    var typeMap = matchMap[instance.entity.tableName];
    if (typeMap == null) {
      typeMap = {};
      matchMap[instance.entity.tableName] = typeMap;
    }

    typeMap[instance[instance.entity.primaryKey]] = instance;
  }

  ManagedObject existingInstance(ManagedEntity entity, dynamic primaryKeyValue) {
    var byType = matchMap[entity.tableName];
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