part of monadart;

class ModelQuery<T extends Model> extends Query<T> {
  ModelQuery() : super();
  ModelQuery.withModelType(Type t) : super.withModelType(t);

  Map<String, dynamic> _map = {};
  Map<String, Query> get subQueries {
    var map = {};
    _map.forEach((k, m) {
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

  void set subQueries(Map<String, Query> e) { throw new QueryException(500, "Cannot set subQueries of ModelQuery, it is dervied.", -1);}

  Predicate get predicate {
    return _buildPredicate(0);
  }
  void set predicate(Predicate p) { throw new QueryException(500, "Cannot set Predicate of ModelQuery, it is derived.", -1); }

  Predicate _buildPredicate(int indexOffset) {
    if (_map.length == 1) {
      var exprKey = _map.keys.first;
      return _predicateForPropertyName(exprKey, indexOffset);
    }

    int index = indexOffset;
    var allPredicates = _map.keys.map((propertyKey) {
      var pred = _predicateForPropertyName(propertyKey, index);
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

  Predicate _predicateForPropertyName(String propertyKey, int index) {
    dynamic expr = _map[propertyKey];

    if (expr is ModelQuery) {
      return expr._buildPredicate(index);
    } else if (expr is List<ModelQuery>) {
      return expr.first._buildPredicate(index);
    }

    return expr.getPredicate(entity.tableName, propertyKey, index);
  }

  dynamic _createSubqueryForPropertyName(String propertyName) {
    var ivar = entity._propertyMirrorForProperty(propertyName);
    ClassMirror ivarType = ivar.type;
    if (ivarType.isSubtypeOf(reflectType(Model))) {
      return new ModelQuery.withModelType(ivarType.reflectedType);
    } else if (ivarType.isSubtypeOf(reflectType(List))) {
      ClassMirror innerIvarType = ivarType.typeArguments.first;
      return [new ModelQuery.withModelType(innerIvarType.reflectedType)];
    }

    return null;
  }

  dynamic operator [](String key) {
    return _getMatcherForPropertyName(key);
  }

  void operator []=(String key, dynamic value) {
    _setMatcherForPropertyName(key, value);
  }

  dynamic _getMatcherForPropertyName(String propertyName) {
    var expr = _map[propertyName];
    if (expr != null) {
      return expr;
    }

    var subquery = _createSubqueryForPropertyName(propertyName);
    if (subquery != null) {
      _map[propertyName] = subquery;
      return subquery;
    }

    return null;
  }

  void _setMatcherForPropertyName(String propertyName, dynamic value) {
    if (value == null) {
      _map.remove(propertyName);
      return;
    }

    if (_matcherIsSubquery(value)) {
      _map[propertyName] = value; //TODO: Add type checking to blow this up here to prevent it from blowing up later.
    } else if (value is _BelongsToModelMatcherExpression) {
      var ivarRelationship = entity.relationshipAttributeForProperty(propertyName);
      if (ivarRelationship == null || ivarRelationship.type != RelationshipType.belongsTo) {
        throw new PredicateMatcherException("Type mismatch for property $propertyName; expecting property with RelationshipType.belongsTo.");
      }
      _map[entity.foreignKeyForProperty(propertyName)] = value;
    } else if (value is _IncludeModelMatcherExpression) {
      _map[propertyName] = _createSubqueryForPropertyName(propertyName);
    } else if (value is MatcherExpression) {
      _map[propertyName] = value;
    } else {
      // Setting simply a value, wrap it with an AssignmentMatcher
      var ivarType = entity._typeMirrorForProperty(propertyName);
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

