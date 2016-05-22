part of aqueduct;

class ModelQuery<T extends Model> extends Query<T> {
  ModelQuery() : super();
  ModelQuery.withModelType(Type t) : super.withModelType(t);

  Map<String, dynamic> _queryMap = {};
  Map<String, Query> get subQueries {
    var map = {};
    _queryMap.forEach((k, m) {
      if (_matcherIsSubquery(m)) {
        if (m is List) {
          map[k] = m.first;
        } else {
          map[k] = m;
        }
      }
    });

    return map;
  }
  @override
  void set subQueries(_) { throw new QueryException(500, "Cannot set subQueries of ModelQuery, it is derived.", -1); }

  Predicate get predicate {
    if (_queryMap.length == 1) {
      var exprKey = _queryMap.keys.first;
      return _predicateForPropertyName(exprKey);
    }

    var allPredicates = _queryMap.keys
        .map((propertyKey) => _predicateForPropertyName(propertyKey))
        .where((p) => p != null).toList();

    if (allPredicates.length > 1) {
      return Predicate.andPredicates(allPredicates.toList());
    } else if (allPredicates.length == 1) {
      return allPredicates.first;
    }

    return null;
  }
  void set predicate(Predicate p) { throw new QueryException(500, "Cannot set Predicate of ModelQuery, it is derived.", -1); }

  Predicate _predicateForPropertyName(String propertyKey) {
    dynamic expr = _queryMap[propertyKey];
    if (_matcherIsSubquery(expr)) {
      return null;
    }

    return expr.getPredicate(entity.tableName, propertyKey);
  }

  dynamic _createSubqueryForPropertyName(String propertyName) {
    var relationshipDesc = entity.relationships[propertyName];
    if (relationshipDesc == null) {
      return null;
    }

    if (relationshipDesc.relationshipType == RelationshipType.hasMany) {
      return new ModelQuery.withModelType(relationshipDesc.destinationEntity.instanceTypeMirror.reflectedType);
    } else if (relationshipDesc.relationshipType == RelationshipType.hasOne) {
      return [new ModelQuery.withModelType(relationshipDesc.destinationEntity.instanceTypeMirror.reflectedType)];
    }

    throw new QueryException(500, "Right joins not supported, subquery for $propertyName references foreign key column.", -1);
  }

  dynamic operator [](String key) {
    return _getMatcherForPropertyName(key);
  }

  void operator []=(String key, dynamic value) {
    _setMatcherForPropertyName(key, value);
  }

  dynamic _getMatcherForPropertyName(String propertyName) {
    var expr = _queryMap[propertyName];
    if (expr != null) {
      return expr;
    }

    var subquery = _createSubqueryForPropertyName(propertyName);
    if (subquery != null) {
      _queryMap[propertyName] = subquery;
      return subquery;
    }

    return null;
  }

  void _setMatcherForPropertyName(String propertyName, dynamic value) {
    if (value == null) {
      _queryMap.remove(propertyName);
      return;
    }

    if (_matcherIsSubquery(value)) {
      _queryMap[propertyName] = value; //TODO: Add type checking to blow this up here to prevent it from blowing up later.
    } else if (value is _BelongsToModelMatcherExpression) {
      var relationshipDesc = entity.relationships[propertyName];
      if (relationshipDesc == null || relationshipDesc.relationshipType != RelationshipType.belongsTo) {
        throw new PredicateMatcherException("Type mismatch for property $propertyName; expecting property with RelationshipType.belongsTo.");
      }
      _queryMap[relationshipDesc.columnName] = value;
    } else if (value is _IncludeModelMatcherExpression) {
      _queryMap[propertyName] = _createSubqueryForPropertyName(propertyName);
    } else if (value is MatcherExpression) {
      _queryMap[propertyName] = value;
    } else {
      // Setting simply a value, wrap it with an AssignmentMatcher
      var attributeDesc = entity.attributes[propertyName];
      if (attributeDesc.isAssignableWith(value)) {
        _queryMap[propertyName] = new _ComparisonMatcherExpression(value, _MatcherOperator.equalTo);
      } else {
        var valueTypeName = MirrorSystem.getName(reflect(value).type.simpleName);
        throw new PredicateMatcherException("Type mismatch for property $propertyName on ${MirrorSystem.getName(entity.instanceTypeMirror.simpleName)}, expected ${attributeDesc.type} but got $valueTypeName.");
      }
    }
  }

  noSuchMethod(Invocation i) {
    if (i.isGetter) {
      var propertyName  = MirrorSystem.getName(i.memberName);

      return _getMatcherForPropertyName(propertyName);
    } else if (i.isSetter) {
      var propertyName = MirrorSystem.getName(i.memberName);
      propertyName = propertyName.substring(0, propertyName.length - 1);

      var value = i.positionalArguments.first;
      _setMatcherForPropertyName(propertyName, value);

      return null;
    }
    return super.noSuchMethod(i);
  }

  static bool _matcherIsSubquery(dynamic expr) {
    return expr is ModelQuery || expr is List<ModelQuery>;
  }
}

