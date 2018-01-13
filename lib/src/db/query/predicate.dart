import 'query.dart';
import '../persistent_store/persistent_store.dart';

/// A predicate contains instructions for filtering rows when performing a [Query].
///
/// Predicates currently are the WHERE clause in a SQL statement and are used verbatim
/// by the [PersistentStore]. In general, you should use [Query.where] instead of using this class directly, as [Query.where] will
/// use the underlying [PersistentStore] to generate a [QueryPredicate] for you.
///
/// A predicate has a format and parameters. The format is the [String] that comes after WHERE in a SQL query. The format may
/// have parameterized values, for which the corresponding value is in the [parameters] map. A parameter is prefixed with '@' in the format string. Currently,
/// the format string's parameter syntax is defined by the [PersistentStore] it is used on. An example of that format:
///
///     var predicate = new QueryPredicate("x = @xValue", {"xValue" : 5});
class QueryPredicate {
  /// The string format of the this predicate.
  ///
  /// This is the predicate text. Do not write dynamic values directly to the format string, instead, prefix an identifier with @
  /// and add that identifier to the [parameters] map.
  String format;

  /// A map of values to replace in the format string at execution time.
  ///
  /// Input values should not be in the format string, but instead provided in this map.
  /// Keys of this map will be searched for in the format string and be replaced by the value in this map.
  Map<String, dynamic> parameters;

  /// Default constructor
  ///
  /// The [format] and [parameters] of this predicate. [parameters] may be null.
  QueryPredicate(this.format, this.parameters);

  /// Joins together a list of predicates by the 'and' token.
  ///
  /// For combining multiple predicate together.
  static QueryPredicate andPredicates(Iterable<QueryPredicate> predicates) {
    var predicateList = predicates.toList();
    if (predicateList == null) {
      return null;
    }

    if (predicateList.length == 0) {
      return null;
    }

    if (predicateList.length == 1) {
      return predicateList.first;
    }

    var predicateFormat =
        "(" + predicateList.map((pred) => "${pred.format}").join(" AND ") + ")";

    var valueMap = <String, dynamic>{};
    predicateList.forEach((p) {
      p.parameters?.forEach((k, v) {
        if (valueMap.containsKey(k)) {
          throw new ArgumentError("Invalid query predicate when creating 'andPredicate'. "
              "Substitution key '$k' appears in multiple predicates and cannot be disambiguated.");
        }
        valueMap[k] = v;
      });
    });

    return new QueryPredicate(predicateFormat, valueMap);
  }
}
