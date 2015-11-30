part of monadart;

/// A predicate contains instructions for identifying criteria of objects.
///
/// Predicates currently are simply the 'where' clause in a SQL statement and are used verbatim
/// by the database adapter. THe format string should use model object property names. Values should be
/// passed through the [parameters] map, not directly in the string. Values are interpolated
/// in the format string by prefixing the @ in front of an identifier. Thus, to form the
/// full predicate "where x = 5", the predicate object should be constructed like so:
///
///     new Predicate("x = @xValue", {"xValue" : 5});
class Predicate {
  /// The string format of the predicate.
  ///
  /// This is the predicate text. Do not add values to the format string, instead, prefix an identifier with @
  /// and add that identifier to the parameters map.
  String get format => _format;
  String _format;

  /// A map of values to interpolate into the format string at execution time.
  ///
  /// Input values should not be in the format string, but instaed provided in this map.
  /// Keys of this map will be searched for in the format string and be replaced by the value in this map.
  Map<String, dynamic> get parameters => _parameters;
  Map<String, dynamic> _parameters;

  /// Default constructor
  ///
  /// The [format] and [parameters] of this predicate.
  Predicate(this._format, this._parameters);

  /// Joins together a list of predicates by the 'and' token.
  ///
  /// For combining multiple predicate together.
  static Predicate andPredicates(List<Predicate> predicates) {
    var predicateFormat =
        predicates.map((pred) => "(${pred.format})").join(" and ");

    var valueMap = {};
    predicates.forEach((p) {
      var pValueMap = p.parameters;

      pValueMap.keys.forEach((k) {
        if (valueMap.containsKey(k)) {
          throw new PredicateException(
              "Duplicate keys in and predicate, ${k} appears in multiple predicates. Make keys more specific.");
        }
      });

      valueMap.addAll(pValueMap);
    });

    return new Predicate(predicateFormat, valueMap);
  }
}

class PredicateException implements Exception {
  final String message;
  PredicateException(this.message);
}
