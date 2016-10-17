part of aqueduct;

/// A predicate contains instructions for identifying criteria of objects.
///
/// Predicates currently are simply the 'where' clause in a SQL statement and are used verbatim
/// by the database adapter. THe format string should use model object property names. Values should be
/// passed through the [parameters] map, not directly in the string. Values are interpolated
/// in the format string by prefixing the @ in front of an identifier. Thus, to form the
/// full predicate "where x = 5", the predicate object should be constructed like so:
///
///     new Predicate("x = @xValue", {"xValue" : 5});
class QueryPredicate {
  /// The string format of the predicate.
  ///
  /// This is the predicate text. Do not add values to the format string, instead, prefix an identifier with @
  /// and add that identifier to the parameters map.
  String format;

  /// A map of values to interpolate into the format string at execution time.
  ///
  /// Input values should not be in the format string, but instead provided in this map.
  /// Keys of this map will be searched for in the format string and be replaced by the value in this map.
  Map<String, dynamic> parameters;

  /// Default constructor
  ///
  /// The [format] and [parameters] of this predicate.
  QueryPredicate(this.format, this.parameters);

  factory QueryPredicate._fromQueryIncludable(QueryMatchable obj, PersistentStore persistentStore) {
    var entity = obj.entity;
    var attributeKeys = obj._matcherMap.keys.where((propertyName) {
      var desc = entity.properties[propertyName];
      if (desc is ManagedRelationshipDescription) {
        return desc.relationshipType == ManagedRelationshipType.belongsTo;
      }

      return true;
    });

    return QueryPredicate.andPredicates(attributeKeys.map((queryKey) {
      var desc = entity.properties[queryKey];
      var matcher = obj._matcherMap[queryKey];

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

      throw new QueryPredicateException("Unknown MatcherExpression ${matcher.runtimeType}");
    }).toList());
  }

  /// Joins together a list of predicates by the 'and' token.
  ///
  /// For combining multiple predicate together.
  static QueryPredicate andPredicates(List<QueryPredicate> predicates) {
    if (predicates == null) {
      return null;
    }

    if (predicates.length == 0) {
      return null;
    }

    var predicateFormat = predicates.map((pred) => "${pred.format}").join(" and ");

    var valueMap = <String, dynamic>{};
    predicates.forEach((p) {
      var pValueMap = p.parameters;

      pValueMap.keys.forEach((k) {
        if (valueMap.containsKey(k)) {
          throw new QueryPredicateException("Duplicate keys in and predicate, ${k} appears in multiple predicates. Make keys more specific.");
        }
      });

      valueMap.addAll(pValueMap);
    });

    return new QueryPredicate(predicateFormat, valueMap);
  }
}

class QueryPredicateException implements Exception {
  final String message;
  QueryPredicateException(this.message);

  String toString() {
    return "PredicateException: $message";
  }
}
