import 'dart:mirrors';

import 'package:postgres/postgres.dart';

import '../db.dart';
import 'postgresql_mapping.dart';

class ManagedInstantiator {
  static Map<ManagedPropertyType, PostgreSQLDataType> typeMap = {
    ManagedPropertyType.integer: PostgreSQLDataType.integer,
    ManagedPropertyType.bigInteger: PostgreSQLDataType.bigInteger,
    ManagedPropertyType.string: PostgreSQLDataType.text,
    ManagedPropertyType.datetime: PostgreSQLDataType.timestampWithoutTimezone,
    ManagedPropertyType.boolean: PostgreSQLDataType.boolean,
    ManagedPropertyType.doublePrecision: PostgreSQLDataType.double
  };

  ManagedInstantiator(this.rootEntity,
      {List<String> returningProperties,
        Map<String, dynamic> values,
        ManagedObject whereBuilder,
        QueryPredicate predicate}) {
   this.properties = returningProperties;
   this.values = values;
   if (whereBuilder != null) {
     // Build it
   }

   // OK, add it to whereBuilder built predicate, which may not exist
   // at this point. It'll be the sum
   if (predicate != null) {
    // If its empty, make it null
   }
  }

  QueryPredicate queryPredicate;
  ManagedObject queryPredicateObject;

  Map<String, Map<dynamic, ManagedObject>> distinctObjects = {};
  List<PropertyMapper> orderedMappingElements;
  ManagedEntity rootEntity;
  String get tableDefinition {
    return rootEntity.tableName;
  }

  bool get containsJoins {
    return orderedMappingElements.reversed.any((m) => m is PropertyToRowMapper);
  }

  List<PropertyToColumnValue> _values;

  Map<String, dynamic> get insertionValueMap {
    var substitutionValues = <String, dynamic>{};
    _values.forEach((v) {
      substitutionValues[v.name] = v.value;
    });
    return substitutionValues;
  }

  // Must return null is empty
  String get whereClause {
    return "";
  }

  Map<String, dynamic> get predicateValueMap {
    // When joining, must contain join vars
    return {};
  }

  Map<String, dynamic> get updateValueMap {
    // Must include values, but also predicateValueMap combined
    // updateValueMap[namer.columnNameForProperty(k, withPrefix: prefix)] = v;
    return {};
  }

  String get updateValueString {
    return _values.map((m) {
      return "${m.name}=@u_${m.name}${typeSuffixForProperty(m.property)}";
    }).join(",");
  }

  String get valuesColumnString {
    return _values.map((c) => c.name).join(",");
  }

  String get insertionValueString {
    return _values.map((c) => "@${c.name}${typeSuffixForProperty(c.property)}").join(",");
  }

  void set values(Map<String, dynamic> valueMap) {
    if (valueMap == null) {
      _values = [];
    }

    _values = valueMap.keys.map((key) {
      var value = valueMap[key];
      var property = rootEntity.properties[key];
      if (property == null) {
        throw new QueryException(QueryExceptionEvent.requestFailure,
            message:
            "Property $key in values does not exist on ${rootEntity.tableName}");
      }

      if (property is ManagedRelationshipDescription) {
        if (property.relationshipType != ManagedRelationshipType.belongsTo) {
          return null;
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

      return new PropertyToColumnValue(property, value);
    })
    .where((v) => v != null)
    .toList();
  }

  String get joinString {
    var joinElements = orderedMappingElements
        .where((mapElement) => mapElement is PropertyToRowMapper)
        .map((mapElement) => mapElement as PropertyToRowMapper)
        .toList();
    var hasJoins = joinElements.isNotEmpty;
    Map<String, dynamic> joinVariables;
    var joinBuffer = new StringBuffer();
    if (hasJoins) {
//      namer.addAliasForEntity(entity);
      joinVariables = {};

      var joinWriter = (PropertyToRowMapper j) {
//        namer.addAliasForEntity(j.joinProperty.entity);
        var p = j.where == null ? j.explicitPredicate : predicateFromMatcherBackedObject(j.where, namer);
        joinBuffer.write("${joinStringForJoin(j, p, namer)} ");
        if (p?.parameters != null) {
          joinVariables.addAll(p.parameters);
        }
      };

      joinElements.forEach((joinElement) {
        joinWriter(joinElement);
        joinElement.orderedNestedRowMappings.forEach(joinWriter);
      });
    }

    return joinBuffer.toString();
  }

  String get namespacedReturningColumnString {
    return orderedMappingElements
        .map((p) => "${p.property.entity.tableName}.${p.name}")
        .join(",");
  }

  String get returningColumnString {
    return orderedMappingElements
        .map((p) => p.name)
        .join(",");
  }

  void set properties(List<String> props) {
    if (props != null) {
      orderedMappingElements = PropertyToColumnMapper.fromKeys(rootEntity, props);
    }
  }

  List<PropertyMapper> get flattenedMappingElements {
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
      Iterator<PropertyMapper> mappingIterator) {
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
      Iterator<PropertyMapper> mappingIterator,
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

  static String typeSuffixForProperty(ManagedPropertyDescription desc) {
    var type = PostgreSQLFormat.dataTypeStringForDataType(typeMap[desc.type]);
    if (type != null) {
      return ":$type";
    }

    return "";
  }
}

class ManagedInstanceWrapper {
  ManagedInstanceWrapper(this.instance, this.isNew);

  bool isNew;
  ManagedObject instance;
}
