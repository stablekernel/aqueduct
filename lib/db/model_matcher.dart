part of monadart;

class ModelMatcher<T> extends ModelBackable<T> {
  Map<String, MatcherExpression> _map = {};

  Predicate get predicate {
    return _buildPredicate(0);
  }

  Predicate _buildPredicate(int indexOffset) {
    if (_map.length == 1) {
      var exprKey = _map.keys.first;
      return _predicateForKey(exprKey, indexOffset);
    }

    int index = indexOffset;
    var allPredicates = _map.keys.map((propertyKey) {
      var pred = _predicateForKey(propertyKey, index);
      if (pred != null) {
        index += pred.parameters.length;
      }

      return pred;
    }).where((p) => p != null).toList();

    if (allPredicates.length > 1) {
      return Predicate.andPredicates(allPredicates.toList());
    } else if (allPredicates.length == 1) {
      return allPredicates.first;
    }

    return null;
  }

  Predicate _predicateForKey(String propertyKey, int index) {
    MatcherExpression expr = _map[propertyKey];

    if (expr is _BelongsToModelMatcherExpression) {
      propertyKey = foreignKeyForProperty(propertyKey);
    }
    return expr.getPredicate(tableName, propertyKey, index);
  }

  MatcherExpression operator [](String key) {
    return _map[key];
  }

  void operator []=(String key, dynamic value) {
    _setMatcherForPropertyName(key, value);
  }

  void _setMatcherForPropertyName(String propertyName, dynamic value) {
    if (value == null) {
      _map.remove(propertyName);
      return;
    }
    if (value is _BelongsToModelMatcherExpression) {
      var ivarRelationship = relationshipAttributeForProperty(propertyName);
      if (ivarRelationship == null || ivarRelationship.type != RelationshipType.belongsTo) {
        throw new PredicateMatcherException("Type mismatch for property $propertyName; expecting property with RelationshipType.belongsTo.");
      }

      _map[propertyName] = value;
    } else if (value is MatcherExpression) {
      _map[propertyName] = value;
    } else {
      var ivarType = _typeMirrorForProperty(propertyName);
      var valueType = reflect(value).type;
      if (!valueType.isSubtypeOf(ivarType)) {
        var ivarTypeName = MirrorSystem.getName(ivarType.simpleName);
        var valueTypeName = MirrorSystem.getName(valueType.simpleName);

        var typeName = MirrorSystem.getName(reflect(this).type.simpleName);
        throw new PredicateMatcherException("Type mismatch for property $propertyName on ${typeName}, expected $ivarTypeName but got $valueTypeName.");
      }

      _map[propertyName] = new _AssignmentMatcherExpression(value);
    }
  }

  noSuchMethod(Invocation i) {
    if (i.isGetter) {
      var propertyName  = MirrorSystem.getName(i.memberName);
      return _map[propertyName];
    } else if (i.isSetter) {
      var propertyName = MirrorSystem.getName(i.memberName);
      propertyName = propertyName.substring(0, propertyName.length - 1);

      var value = i.positionalArguments.first;
      _setMatcherForPropertyName(propertyName, value);

      return null;
    }
    return super.noSuchMethod(i);
  }
}

