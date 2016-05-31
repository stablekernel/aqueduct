part of aqueduct;

class ModelQuery<T extends Model> extends Query<T> {
  ModelQuery({ModelContext context: null}) : super(context: context);
  ModelQuery.withModelType(Type t, {ModelContext context: null}) : super.withModelType(t, context: null);

  Predicate get predicate => null;
  void set predicate(Predicate p) { throw new QueryException(500, "ModelQuery predicate is immutable", -1); }

  Map<String, ModelQuery> subQueries = {};
  Map<String, dynamic> _queryMap = {};
  bool _representsListQuery = false;

  dynamic _createSubqueryForPropertyNameIfApplicable(PropertyDescription desc) {
    if (desc is! RelationshipDescription) {
      return null;
    }

    RelationshipDescription relDesc = desc;
    print("What? ${relDesc.inverseRelationship.entity.instanceTypeMirror.reflectedType}");
    return new ModelQuery.withModelType(relDesc.inverseRelationship.entity.instanceTypeMirror.reflectedType, context: this.context)
      .._representsListQuery = relDesc.relationshipType == RelationshipType.hasMany;
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

    var subQuery = subQueries[propertyName];
    if (subQuery != null) {
      return subQuery;
    }

    // Automatically generate a subquery once accessed
    subQuery = _createSubqueryForPropertyNameIfApplicable(entity.properties[propertyName]);
    if (subQuery != null) {
      subQueries[propertyName] = subQuery;
      return subQuery;
    }

    return null;
  }

  void _setMatcherForPropertyName(String propertyName, dynamic value) {
    if (value == null) {
      _queryMap.remove(propertyName);
      subQueries?.remove(propertyName);
      return;
    }

    if (_matcherIsSubquery(value)) {
      if (value is List) {
        value = value.first;
      }
      subQueries[propertyName] = value;
    } else if (value is _IncludeModelMatcherExpression) {
      subQueries[propertyName] = _createSubqueryForPropertyNameIfApplicable(entity.properties[propertyName]);
    } else if (value is MatcherExpression) {
      _queryMap[propertyName] = value;
    } else {
      // Setting simply a value, wrap it with an AssignmentMatcher
      _queryMap[propertyName] = new _ComparisonMatcherExpression(value, MatcherOperator.equalTo);
    }
  }

  noSuchMethod(Invocation i) {
    if (i.isGetter) {
      var propertyName = MirrorSystem.getName(i.memberName);
      var matcher = _getMatcherForPropertyName(propertyName);

      if (matcher is ModelQuery) {
        if (matcher._representsListQuery) {
          return [matcher];
        }
      }

      return matcher;
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

  Predicate _compilePredicate(DataModel dataModel, PersistentStore persistentStore) {
    return Predicate.andPredicates(_queryMap?.keys?.map((queryKey) {
      var desc = dataModel.entityForType(modelType).properties[queryKey];
      var matcher = _queryMap[queryKey];

      if (matcher is _ComparisonMatcherExpression) {
        return persistentStore.comparisonPredicate(desc, matcher.operator, matcher.value);
      } else if (matcher is _RangeMatcherExpression) {
        return persistentStore.rangePredicate(desc, matcher.lhs, matcher.rhs, matcher.within);
      } else if (matcher is _NullMatcherExpression) {
        return persistentStore.nullPredicate(desc, matcher.shouldBeNull);
      } else if (matcher is _WithinMatcherExpression) {
        return persistentStore.containsPredicate(desc, matcher.values);
      }
    })?.toList());
  }
}