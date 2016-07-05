part of aqueduct;

/// A representation of a Route match, containing the elements of the matched path.
///
/// Instances of this class can be used by handlers after the router to inspect
/// specifics of the incoming path without having to dissect the path on their own.
class RequestPath {
  /// A map of variable to values in this match.
  ///
  /// If a path has variables (indicated by the :name syntax) in the path,
  /// the matching segments for the path will be stored in the map. The key
  /// will be the variable name (without the colon) and the value will be the
  /// path segment as a string.
  ///
  /// Example:
  /// Consider a match specification /users/:id. If the evaluated path is
  ///     /users/2
  /// This property will be {'id' : '2'}.
  ///
  Map<String, String> variables = {};

  /// A list of the segments in a matched path.
  ///
  /// This property will contain every segment of the matched path, including
  /// constant segments. It will not contain any part of the path caught by
  /// the asterisk 'match all' token, however. Those are in [remainingPath].
  List<String> segments = [];

  /// If a match specification uses the asterisk 'match all' token,
  /// the part of the path matched by that token will be stored in this property.
  ///
  /// The remaining path will will be a single string, including any path delimiters (/),
  /// but will not have a leading path delimiter.
  String remainingPath = null;

  /// The name (key in [variables]) of the first matched variable.
  ///
  /// The first variable is often the identifier for a specific resource in a resource collection.
  dynamic firstVariableName = null;
}

/// Specifies a matchable route path.
///
/// Contains [RouteSegment]s for each path segment.
class RoutePathSpecification implements APIDocumentable {
  static List<RoutePathSpecification> specificationsForRoutePattern(String routePattern) {
    return pathsFromRoutePattern(routePattern)
        .map((path) => new RoutePathSpecification(path))
        .toList();
  }

  /// Creates a new [RoutePathSpecification] from a [String].
  ///
  /// The [patternString] must be stripped of any optionals.
  RoutePathSpecification(String patternString) {
    segments = splitPathSegments(patternString);
    firstVariableName = segments.firstWhere((e) => e.isVariable, orElse: () => null)?.variableName;
    variableNames = segments.where((e) => e.variableName != null).map((e) => e.variableName).toList();
  }

  /// A list of this specification's [RouteSegment]s.
  List<RouteSegment> segments;

  /// The first variable name in this route.
  String firstVariableName;

  /// A list of all variables in this route.
  List<String> variableNames;

  /// A reference back to the [RequestHandler] to be used when this specification is matched.
  RequestHandler handler;

  RequestPath requestPathForSegments(List<String> requestSegments) {
    var p = new RequestPath();

    p.firstVariableName = firstVariableName;
    p.segments = requestSegments;

    var requestIterator = requestSegments.iterator;
    for (var segment in segments) {
      requestIterator.moveNext();
      var requestSegment = requestIterator.current;

      if (segment.isVariable) {
        p.variables[segment.variableName] = requestSegment;
      } else if (segment.isRemainingMatcher) {
        var remaining = [];
        remaining.add(requestIterator.current);
        while(requestIterator.moveNext()) {
          remaining.add(requestIterator.current);
        }
        p.remainingPath = remaining.join("/");

        return p;
      }
    }

    return p;
  }

  @override
  dynamic document(PackagePathResolver resolver) {
    var p = new APIPath();
    p.path = "/" + segments.map((rs) {
      if (rs.isLiteralMatcher) {
        return rs.literal;
      } else if (rs.isVariable) {
        return "{${rs.variableName}}";
      } else if (rs.isRemainingMatcher) {
        return "*";
      }
    }).join("/");

    p.parameters = segments
        .where((seg) => seg.isVariable)
        .map((seg) {
          var param = new APIParameter()
              ..name = seg.variableName
              ..parameterLocation = APIParameterLocation.path;

          return param;
        }).toList();


    return p;
  }

  String toString() => segments.join("/");
}

class RouteSegment {
  RouteSegment(String segment) {
    if (segment == "*") {
      isRemainingMatcher = true;
      return;
    }

    var regexIndex = segment.indexOf("(");
    if (regexIndex != -1) {
      var regexText = segment.substring(regexIndex + 1, segment.length - 1);
      matcher = new RegExp(regexText);

      segment = segment.substring(0, regexIndex);
    }

    if (segment.startsWith(":")) {
      variableName = segment.substring(1, segment.length);
    } else if (regexIndex == -1) {
      literal = segment;
    }
  }

  RouteSegment.direct({String literal: null, String variableName: null, String expression: null, bool matchesAnything: false}) {
    this.literal = literal;
    this.variableName = variableName;
    this.isRemainingMatcher = matchesAnything;
    if (expression != null) {
      this.matcher = new RegExp(expression);
    }
  }

  String literal;
  String variableName;
  RegExp matcher;

  bool get isLiteralMatcher => !isRemainingMatcher && !isVariable && !hasRegularExpression;
  bool get hasRegularExpression => matcher != null;
  bool get isVariable => variableName != null;
  bool isRemainingMatcher = false;

  bool matches(String pathSegment) {
    if (isLiteralMatcher) {
      return pathSegment == literal;
    }

    if (hasRegularExpression) {
      if (matcher.firstMatch(pathSegment) == null) {
        return false;
      }
    }

    if (isVariable) {
      return true;
    }

    return false;
  }

  operator ==(dynamic other) {
    if (other is! RouteSegment) {
      return false;
    }

    return literal == other.literal
        && variableName == other.variableName
        && isRemainingMatcher == other.isRemainingMatcher
        && matcher?.pattern == other.matcher?.pattern;
  }

  String toString() {
    if (isLiteralMatcher) {
      return literal;
    }

    if (isVariable) {
      return variableName;
    }

    if (hasRegularExpression) {
      return "(${matcher.pattern})";
    }

    return "*";
  }
}

/// Utility method to take Route syntax into one or more full paths.
///
/// This method strips away optionals in the route syntax, yielding an individual path for every combination of the route syntax.
/// The returned [String]s no longer contain optional syntax.
List<String> pathsFromRoutePattern(String routePattern) {
  var endingOptionalCloseCount = 0;
  while (routePattern.endsWith("]")) {
    routePattern = routePattern.substring(0, routePattern.length - 1);
    endingOptionalCloseCount ++;
  }

  var chars = routePattern.codeUnits;
  var patterns = [];
  var buffer = new StringBuffer();
  var openOptional = '['.codeUnitAt(0);
  var openExpression = '('.codeUnitAt(0);
  var closeExpression = ')'.codeUnitAt(0);

  bool insideExpression = false;
  for (var i = 0; i < chars.length; i++) {
    var code = chars[i];

    if (code == openExpression) {
      if (insideExpression) {
        throw new RouterException("Invalid route $routePattern, cannot use expression that contains '(' or ')'");
      } else {
        buffer.writeCharCode(code);
        insideExpression = true;
      }
    } else if (code == closeExpression) {
      if (insideExpression) {
        buffer.writeCharCode(code);
        insideExpression = false;
      } else {
        buffer.writeCharCode(code);
      }
    } else if (code == openOptional) {
      if (insideExpression) {
        buffer.writeCharCode(code);
      } else {
        patterns.add(buffer.toString());
      }
    } else {
      buffer.writeCharCode(code);
    }
  }

  if (insideExpression) {
    throw new RouterException("Invalid route $routePattern, unterminated regular expression");
  }

  if (endingOptionalCloseCount != patterns.length) {
    throw new RouterException("Invalid pattern specifiation, $routePattern, does not close all optionals");
  }

  // Add the final pattern - if no optionals, this is the only pattern.
  patterns.add(buffer.toString());

  return patterns;
}


/// Utility method for turning a path into a list of [RouteSegment]s.
List<RouteSegment> splitPathSegments(String path) {
  // Once we've gotten into this method, the path has been validated for optionals and regex and optionals have been removed.

  // Trim leading and trailing
  while (path.startsWith("/")) {
    path = path.substring(1, path.length);
  }
  while(path.endsWith("/")) {
    path = path.substring(0, path.length - 1);
  }

  var segments = [];
  var chars = path.codeUnits;
  var buffer = new StringBuffer();

  var openExpression = '('.codeUnitAt(0);
  var closeExpression = ')'.codeUnitAt(0);
  var pathDelimiter = '/'.codeUnitAt(0);
  bool insideExpression = false;

  for (var i = 0; i < path.length; i++) {
    var code = chars[i];

    if (code == openExpression) {
      buffer.writeCharCode(code);
      insideExpression = true;
    } else if (code == closeExpression) {
      buffer.writeCharCode(code);
      insideExpression = false;
    } else if (code == pathDelimiter) {
      if (insideExpression) {
        buffer.writeCharCode(code);
      } else {
        segments.add(buffer.toString());
        buffer = new StringBuffer();
      }
    } else {
      buffer.writeCharCode(code);
    }
  }

  if (segments.any((seg) => seg == "")) {
    throw new RouterException("Invalid route path $path, contains an empty path segment");
  }

  // Add final
  segments.add(buffer.toString());

  return segments.map((seg) => new RouteSegment(seg)).toList();
}