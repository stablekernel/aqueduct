part of aqueduct;

abstract class _ManagedBacking {
  dynamic valueForProperty(ManagedEntity entity, String propertyName);
  void setValueForProperty(
      ManagedEntity entity, String propertyName, dynamic value);
  void removeProperty(String propertyName) {
    valueMap.remove(propertyName);
  }

  Map<String, dynamic> get valueMap;
}

class _ManagedValueBacking extends _ManagedBacking {
  Map<String, dynamic> valueMap = {};

  dynamic valueForProperty(ManagedEntity entity, String propertyName) {
    if (entity.properties[propertyName] == null) {
      throw new ManagedDataModelException(
          "Model type ${MirrorSystem.getName(entity.instanceType.simpleName)} has no property $propertyName.");
    }

    return valueMap[propertyName];
  }

  void setValueForProperty(
      ManagedEntity entity, String propertyName, dynamic value) {
    var property = entity.properties[propertyName];
    if (property == null) {
      throw new ManagedDataModelException(
          "Model type ${MirrorSystem.getName(entity.instanceType.simpleName)} has no property $propertyName.");
    }

    if (value != null) {
      if (!property.isAssignableWith(value)) {
        var valueTypeName =
            MirrorSystem.getName(reflect(value).type.simpleName);
        throw new ManagedDataModelException(
            "Type mismatch for property $propertyName on ${MirrorSystem.getName(entity.persistentType.simpleName)}, expected assignable type matching ${property.type} but got $valueTypeName.");
      }
    }

    valueMap[propertyName] = value;
  }
}

class _ManagedMatcherBacking extends _ManagedBacking {
  Map<String, dynamic> valueMap = {};

  dynamic valueForProperty(ManagedEntity entity, String propertyName) {
    if (!valueMap.containsKey(propertyName)) {
      var relDesc = entity.relationships[propertyName];
      if (relDesc?.relationshipType == ManagedRelationshipType.hasMany) {
        valueMap[propertyName] = new ManagedSet()
          ..entity = relDesc.destinationEntity;
      } else if (relDesc?.relationshipType == ManagedRelationshipType.hasOne) {
        valueMap[propertyName] = relDesc.destinationEntity.newInstance()
          .._backing = new _ManagedMatcherBacking();
      } else if (relDesc?.relationshipType ==
          ManagedRelationshipType.belongsTo) {
        throw new QueryException(QueryExceptionEvent.requestFailure,
            message:
                "Attempting to access matcher on RelationshipInverse $propertyName on ${entity.tableName}. Assign this value to whereRelatedByValue instead.");
      }
    }

    return valueMap[propertyName];
  }

  void setValueForProperty(
      ManagedEntity entity, String propertyName, dynamic value) {
    if (value == null) {
      valueMap.remove(propertyName);
      return;
    }

    if (value is _MatcherExpression) {
      var relDesc = entity.relationships[propertyName];

      if (relDesc != null &&
          relDesc.relationshipType != ManagedRelationshipType.belongsTo) {
        throw new QueryException(QueryExceptionEvent.internalFailure,
            message:
                "Attempting to set matcher on hasOne or hasMany relationship. Use includeInResultSet.");
      }

      valueMap[propertyName] = value;
    } else {
      // Setting simply a value, wrap it with an AssignmentMatcher if applicable.
      if (entity.relationships.containsKey(propertyName)) {
        throw new QueryException(QueryExceptionEvent.internalFailure,
            message:
                "Attempting to set simple value matcher for property $propertyName on ${entity.tableName}, but that property is a relationship.");
      }

      valueMap[propertyName] =
          new _ComparisonMatcherExpression(value, MatcherOperator.equalTo);
    }
  }
}
