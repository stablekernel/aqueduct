import 'http.dart';
import 'route_specification.dart';

/// The HTTP request path decomposed into variables and segments based on a [RouteSpecification].
///
/// After passing through a [Router], a [Request] will have an instance of [HTTPRequestPath] in [Request.path].
/// Any variable path parameters will be available in [variables].
///
/// For each request passes through a router, a new instance of this type is created specific to that request.
class HTTPRequestPath {
  /// Default constructor for [HTTPRequestPath].
  ///
  /// There is no need to invoke this constructor manually.
  HTTPRequestPath(
      RouteSpecification specification, List<String> requestSegments) {
    segments = requestSegments;
    orderedVariableNames = [];

    var requestIterator = requestSegments.iterator;
    for (var segment in specification.segments) {
      requestIterator.moveNext();
      var requestSegment = requestIterator.current;

      if (segment.isVariable) {
        variables[segment.variableName] = requestSegment;
        orderedVariableNames.add(segment.variableName);
      } else if (segment.isRemainingMatcher) {
        var remaining = [];
        remaining.add(requestIterator.current);
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
  List<String> segments = [];

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
  /// but the incoming request this [HTTPRequestPath] represents only has one variable, only that one variable
  /// will appear in this property.
  List<String> orderedVariableNames = [];
}
