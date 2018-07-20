import 'http.dart';
import 'route_specification.dart';

/// Stores path info for a [Request].
///
/// Contains the raw path string, the path as segments and values created by routing a request.
///
/// Note: The properties [variables], [orderedVariableNames] and [remainingPath] are not set until
/// after the owning request has passed through a [Router].
class RequestPath {
  /// Default constructor for [RequestPath].
  ///
  /// There is no need to invoke this constructor manually.
  RequestPath(this.segments);

  void setSpecification(RouteSpecification spec, {int segmentOffset = 0}) {
    var requestIterator = segments.iterator;
    for (var i = 0; i < segmentOffset; i++) {
      requestIterator.moveNext();
    }

    for (var segment in spec.segments) {
      requestIterator.moveNext();
      var requestSegment = requestIterator.current;

      if (segment.isVariable) {
        variables[segment.variableName] = requestSegment;
        orderedVariableNames.add(segment.variableName);
      } else if (segment.isRemainingMatcher) {
        var remaining = [];
        remaining.add(requestIterator.current ?? "");
        while (requestIterator.moveNext()) {
          remaining.add(requestIterator.current);
        }
        remainingPath = remaining.join("/");

        return;
      }
    }
  }

  /// A [Map] of path variables.
  ///
  /// If a path has variables (indicated by the :variable syntax),
  /// the matching segments for the path variables will be stored in the map. The key
  /// will be the variable name (without the colon) and the value will be the
  /// path segment as a string.
  ///
  /// Consider a match specification /users/:id. If the evaluated path is
  ///     /users/2
  /// This property will be {'id' : '2'}.
  ///
  Map<String, String> variables = {};

  /// A list of the segments in a matched path.
  ///
  /// This property will contain every segment of the matched path, including
  /// constant segments. It will not contain any part of the path caught by
  /// the asterisk 'match all' token (*), however. Those are in [remainingPath].
  final List<String> segments;

  /// If a match specification uses the 'match all' token (*),
  /// the part of the path matched by that token will be stored in this property.
  ///
  /// The remaining path will will be a single string, including any path delimiters (/),
  /// but will not have a leading path delimiter.
  String remainingPath;

  /// An ordered list of variable names (the keys in [variables]) based on their position in the path.
  ///
  /// If no path variables are present in the request, this list is empty. Only path variables that are
  /// available for the specific request are in this list. For example, if a route has two path variables,
  /// but the incoming request this [RequestPath] represents only has one variable, only that one variable
  /// will appear in this property.
  List<String> orderedVariableNames = [];

  /// The path of the requested URI.
  ///
  /// Always contains a leading '/', but never a trailing '/'.
  String get string => "/${segments.join("/")}";
}
