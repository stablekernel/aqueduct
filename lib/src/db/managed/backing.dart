import 'dart:mirrors';
import '../query/query.dart';
import 'managed.dart';
import '../query/matcher_internal.dart';

class ManagedValueBacking extends ManagedBacking {
  @override
  Map<String, dynamic> valueMap = {};

  @override
  dynamic valueForProperty(ManagedEntity entity, String propertyName) {
    if (entity.properties[propertyName] == null) {
      throw new ManagedDataModelException(
          "'${MirrorSystem.getName(entity.instanceType.simpleName)}' has no property named '$propertyName'.");
    }

    return valueMap[propertyName];
  }

  @override
  void setValueForProperty(
      ManagedEntity entity, String propertyName, dynamic value) {
    var property = entity.properties[propertyName];
    if (property == null) {
      throw new QueryException(QueryExceptionEvent.requestFailure, message:
          "'${MirrorSystem.getName(entity.instanceType.simpleName)}' has no property named '$propertyName'.");
    }

    if (value != null) {
      if (!property.isAssignableWith(value)) {
        var valueTypeName =
            MirrorSystem.getName(reflect(value).type.simpleName);
        throw new QueryException(QueryExceptionEvent.requestFailure, message:
            "Invalid type '$valueTypeName' for '$propertyName' on '${MirrorSystem.getName(entity.instanceType.simpleName)}', expected ${property.type}.");
      }
    }

    valueMap[propertyName] = value;
  }
}

class ManagedMatcherBacking extends ManagedBacking {
  @override
  Map<String, dynamic> valueMap = {};

  @override
  dynamic valueForProperty(ManagedEntity entity, String propertyName) {
    if (!valueMap.containsKey(propertyName)) {
      var relDesc = entity.relationships[propertyName];
      if (relDesc?.relationshipType == ManagedRelationshipType.hasMany) {
        valueMap[propertyName] = new ManagedSet()
          ..entity = relDesc.destinationEntity;
      } else if (relDesc?.relationshipType == ManagedRelationshipType.hasOne ||
          relDesc?.relationshipType == ManagedRelationshipType.belongsTo) {
        valueMap[propertyName] = relDesc.destinationEntity.newInstance()
          ..backing = new ManagedMatcherBacking();
      }
    }

    return valueMap[propertyName];
  }

  @override
  void setValueForProperty(
      ManagedEntity entity, String propertyName, dynamic value) {
    if (value == null) {
      valueMap.remove(propertyName);
      return;
    }

    if (value is MatcherExpression) {
      var property = entity.properties[propertyName];

      if (property is ManagedRelationshipDescription) {
        var innerObject = valueForProperty(entity, propertyName);
        if (innerObject is ManagedObject) {
          innerObject[innerObject.entity.primaryKey] = value;
        } else if (innerObject is ManagedSet) {
          innerObject.haveAtLeastOneWhere[innerObject.entity.primaryKey] =
              value;
        }
      } else {
        valueMap[propertyName] = value;
      }
    } else {
      // Setting simply a value, wrap it with an AssignmentMatcher if applicable.
      if (entity.relationships.containsKey(propertyName)) {
        throw new QueryException(QueryExceptionEvent.internalFailure,
            message:
                "Attempting to set a value for property '${entity.tableName}.$propertyName' "
                "on, but that property is a relationship. Valid values for relationship "
                "properties are whereRelatedByValue, whereNull, or whereNotNull.");
      }

      valueMap[propertyName] =
          new ComparisonMatcherExpression(value, MatcherOperator.equalTo);
    }
  }
}

class ManagedAccessTrackingBacking extends ManagedBacking {
  @override
  Map<String, dynamic> get valueMap => null;

  @override
  dynamic valueForProperty(ManagedEntity entity, String propertyName) =>
      propertyName;

  @override
  void setValueForProperty(
      ManagedEntity entity, String propertyName, dynamic value) {
    // no-op
  }
}
