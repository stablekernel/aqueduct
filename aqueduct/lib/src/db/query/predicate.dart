import '../persistent_store/persistent_store.dart';
import 'query.dart';

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
  /// Default constructor
  ///
  /// The [format] and [parameters] of this predicate. [parameters] may be null.
  QueryPredicate(this.format, this.parameters) {
    format ??= "";
    parameters ??= {};
  }

  /// Creates an empty predicate.
  ///
  /// The format string is the empty string and parameters is the empty map.
  QueryPredicate.empty()
    : format = "",
      parameters = {};

  /// Combines [predicates] with 'AND' keyword.
  ///
  /// The [format] of the return value is produced by joining together each [predicates]
  /// [format] string with 'AND'. Each [parameters] from individual [predicates] is combined
  /// into the returned [parameters].
  ///
  /// If there are duplicate parameter names in [predicates], they will be disambiguated by suffixing
  /// the parameter name in both [format] and [parameters] with a unique integer.
  ///
  /// If [predicates] is null or empty, an empty predicate is returned. If [predicates] contains only
  /// one predicate, that predicate is returned.
  factory QueryPredicate.and(Iterable<QueryPredicate> predicates) {
    var predicateList = predicates
      ?.where((p) => p?.format != null && p.format.isNotEmpty)
      ?.toList();
    if (predicateList == null) {
      return QueryPredicate.empty();
    }

    if (predicateList.isEmpty) {
      return QueryPredicate.empty();
    }

    if (predicateList.length == 1) {
      return predicateList.first;
    }

    // If we have duplicate keys anywhere, we need to disambiguate them.
    int dupeCounter = 0;
    final allFormatStrings = [];
    final valueMap = <String, dynamic>{};
    for (var predicate in predicateList) {
      final duplicateKeys = predicate.parameters?.keys
        ?.where((k) => valueMap.keys.contains(k))
        ?.toList() ??
        [];

      if (duplicateKeys.isNotEmpty) {
        var fmt = predicate.format;
        Map<String, String> dupeMap = {};
        duplicateKeys.forEach((key) {
          final replacementKey = "$key$dupeCounter";
          fmt = fmt.replaceAll("@$key", "@$replacementKey");
          dupeMap[key] = replacementKey;
          dupeCounter++;
        });

        allFormatStrings.add(fmt);
        predicate?.parameters?.forEach((key, value) {
          valueMap[dupeMap[key] ?? key] = value;
        });
      } else {
        allFormatStrings.add(predicate.format);
        valueMap.addAll(predicate?.parameters ?? {});
      }
    }

    final predicateFormat = "(${allFormatStrings.join(" AND ")})";
    return QueryPredicate(predicateFormat, valueMap);
  }

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
}
