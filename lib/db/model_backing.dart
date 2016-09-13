part of aqueduct;


abstract class _ModelBacking {
  dynamic valueForProperty(ModelEntity entity, String propertyName);
  void setValueForProperty(ModelEntity entity, String propertyName, dynamic value);
  void removeProperty(String propertyName) {
    valueMap.remove(propertyName);
  }

  Map<String, dynamic> get valueMap;
}

class _ModelValueBacking extends _ModelBacking {
  Map<String, dynamic> valueMap = {};

  dynamic valueForProperty(ModelEntity entity, String propertyName) {
    if (entity.properties[propertyName] == null) {
      throw new DataModelException("Model type ${MirrorSystem.getName(entity.instanceTypeMirror.simpleName)} has no property $propertyName.");
    }

    return valueMap[propertyName];
  }

  void setValueForProperty(ModelEntity entity, String propertyName, dynamic value) {
    var property = entity.properties[propertyName];
    if (property == null) {
      throw new DataModelException("Model type ${MirrorSystem.getName(entity.instanceTypeMirror.simpleName)} has no property $propertyName.");
    }

    if (value != null) {
      if (!property.isAssignableWith(value)) {
        var valueTypeName = MirrorSystem.getName(reflect(value).type.simpleName);
        throw new DataModelException("Type mismatch for property $propertyName on ${MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName)}, expected assignable type matching ${property.type} but got $valueTypeName.");
      }
    }

    valueMap[propertyName] = value;
  }
}

class _ModelMatcherBacking extends _ModelBacking {
  Map<String, dynamic> valueMap = {};

  dynamic valueForProperty(ModelEntity entity, String propertyName) {
    if (!valueMap.containsKey(propertyName)) {
      var relDesc = entity.relationships[propertyName];
      if (relDesc?.relationshipType == RelationshipType.hasMany) {
        valueMap[propertyName] = new OrderedSet()
          ..entity = relDesc.destinationEntity;
      } else if (relDesc?.relationshipType == RelationshipType.hasOne) {
        valueMap[propertyName] = relDesc.destinationEntity.newInstance()
            .._backing = new _ModelMatcherBacking();
      }
    }

    return valueMap[propertyName];
  }

  void setValueForProperty(ModelEntity entity, String propertyName, dynamic value) {
    if (value == null) {
      valueMap.remove(propertyName);
      return;
    }

    if (value is MatcherExpression) {
      var relDesc = entity.relationships[propertyName];

      if (value is _IncludeModelMatcherExpression && relDesc?.relationshipType != RelationshipType.hasOne) {
        throw new QueryException(500, "Attempting to set hasOne matcher for property $propertyName on ${entity.tableName}, but that property is not a hasOne relationship.", -1);
      }

      valueMap[propertyName] = value;
    } else if (value is OrderedSet) {
      var relDesc = entity.relationships[propertyName];
      if (relDesc?.relationshipType != RelationshipType.hasMany) {
        throw new QueryException(500, "Attempting to set hasMany matcher for property $propertyName on ${entity.tableName}, but that property is not a hasMany relationship.", -1);
      }

      value.entity = relDesc.destinationEntity;
      valueMap[propertyName] = value;
    } else {
      // Setting simply a value, wrap it with an AssignmentMatcher if applicable.
      if (entity.relationships.containsKey(propertyName)) {
        throw new QueryException(500, "Attempting to set simple value matcher for property $propertyName on ${entity.tableName}, but that property is a relationship.", -1);
      }

      valueMap[propertyName] = new _ComparisonMatcherExpression(value, MatcherOperator.equalTo);
    }
  }
}