part of aqueduct;

/// A class for building [Query]s using the Hamcrest matcher style.
///
/// Instances of this class must define the type of [Model] they operate on by specifying a type argument.
/// Example:
///
///       var query = new ModelQuery<User>()
///         ..["name"] = whereEqualTo("Bob");
///       var usersWithTheNameBob = await query.fetch();
///
///  Properties on the Model type argument can be assigned matchers which will be used to generate
///  a [Predicate] for this query.
///
/// Since stringly-typed data is often difficult to work with, it often makes sense to create a subclass of
/// [ModelQuery] that implements the interface of the Model type argument:
///
///       class UserQuery extends ModelQuery<User> implements User {}
///
/// This allows the following query to be equivalent to the earlier example:
///       var query = new UserQuery()
///         ..name = whereEqualTo("Bob");
///
/// [ModelQuery]s may also perform database joins. When supplying a matcher to a [RelationshipDescription],
/// instances in that relationship will be fetched as well.
class ModelQuery<T extends Model> extends Query<T> {
  /// Creates an instance of [ModelQuery].
  ///
  /// By default, [context] will be the [ModelContext.defaultContext].
  ModelQuery({ModelContext context: null}) : super(context: context);
  ModelQuery._withModelType(Type t, {ModelContext context: null}) : super.withModelType(t, context: null);

  /// The map of sub-queries for database joins. Do not modify directly.
  Map<String, ModelQuery> subQueries = {};
  Map<String, dynamic> _queryMap = {};
  bool _representsListQuery = false;

  dynamic _createSubqueryForPropertyNameIfApplicable(PropertyDescription desc) {
    if (desc is! RelationshipDescription) {
      return null;
    }

    RelationshipDescription relDesc = desc;
    return new ModelQuery._withModelType(relDesc.inverseRelationship.entity.instanceTypeMirror.reflectedType, context: this.context)
      .._representsListQuery = relDesc.relationshipType == RelationshipType.hasMany;
  }

  /// Retrieves a matcher for a property name.
  dynamic operator [](String key) {
    return _getMatcherForPropertyName(key);
  }

  /// Sets a matcher for a property name.
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
    if (this.predicate != null) {
      throw new QueryException(500, "ModelQuery predicate must not be altered, was set to ${this.predicate}", -1);
    }

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
      } else if (matcher is _StringMatcherExpression) {
        return persistentStore.stringPredicate(desc, matcher.operator, matcher.value);
      }
    })?.toList());
  }
}