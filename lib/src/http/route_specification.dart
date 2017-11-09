import 'http.dart';
import 'route_node.dart';

/// Specifies a matchable route path.
///
/// Contains [RouteSegment]s for each path segment. This class is used internally by [Router].
class RouteSpecification extends Object with APIDocumentable {
  /// Creates a new [RouteSpecification] from a [String].
  ///
  /// The [patternString] must be stripped of any optionals.
  RouteSpecification(String patternString) {
    segments = _splitPathSegments(patternString);
    variableNames =
        segments.where((e) => e.isVariable).map((e) => e.variableName).toList();
  }


  static List<RouteSpecification> specificationsForRoutePattern(
      String routePattern) {
    return _pathsFromRoutePattern(routePattern)
        .map((path) => new RouteSpecification(path))
        .toList();
  }

  /// A list of this specification's [RouteSegment]s.
  List<RouteSegment> segments;

  /// A list of all variables in this route.
  List<String> variableNames;

  /// A reference back to the [Controller] to be used when this specification is matched.
  Controller controller;

  @override
  List<APIPath> documentPaths(PackagePathResolver resolver) {
    var p = new APIPath();
    p.path = "/" +
        segments.map((rs) {
          if (rs.isLiteralMatcher) {
            return rs.literal;
          } else if (rs.isVariable) {
            return "{${rs.variableName}}";
          } else if (rs.isRemainingMatcher) {
            return "*";
          }
        }).join("/");

    p.parameters = segments.where((seg) => seg.isVariable).map((seg) {
      var param = new APIParameter()
        ..name = seg.variableName
        ..parameterLocation = APIParameterLocation.path;

      return param;
    }).toList();

    List<APIOperation> allOperations = controller.documentOperations(resolver) ?? [];
    p.operations = allOperations.where((op) {
      var opPathParamNames = op.parameters
          .where((p) => p.parameterLocation == APIParameterLocation.path)
          .map((p) => p.name)
          .toList();
      var pathParamNames = p.parameters
          .where((p) => p.parameterLocation == APIParameterLocation.path)
          .toList();

      if (pathParamNames.length != opPathParamNames.length) {
        return false;
      }

      return pathParamNames.every((p) => opPathParamNames.contains(p.name));
    }).toList();

    // Strip operation parameters that are already in the path, but move their type into
    // the path's path parameters
    p.operations.forEach((op) {
      var typedPathParameters = op.parameters
          .where((pi) => pi.parameterLocation == APIParameterLocation.path)
          .toList();
      p.parameters.forEach((p) {
        var matchingTypedPathParam = typedPathParameters.firstWhere(
                (typedParam) => typedParam.name == p.name,
            orElse: () => null);
        p.schemaObject ??= matchingTypedPathParam?.schemaObject;
      });

      op.parameters = op.parameters
          .where((p) => p.parameterLocation != APIParameterLocation.path)
          .toList();
    });

    return [p];
  }

  @override
  String toString() => segments.join("/");
}

/// Utility method to take Route syntax into one or more full paths.
///
/// This method strips away optionals in the route syntax, yielding an individual path for every combination of the route syntax.
/// The returned [String]s no longer contain optional syntax.
List<String> _pathsFromRoutePattern(String routePattern) {
  var endingOptionalCloseCount = 0;
  while (routePattern.endsWith("]")) {
    routePattern = routePattern.substring(0, routePattern.length - 1);
    endingOptionalCloseCount++;
  }

  var chars = routePattern.codeUnits;
  var patterns = <String>[];
  var buffer = new StringBuffer();
  var openOptional = '['.codeUnitAt(0);
  var openExpression = '('.codeUnitAt(0);
  var closeExpression = ')'.codeUnitAt(0);

  bool insideExpression = false;
  for (var i = 0; i < chars.length; i++) {
    var code = chars[i];

    if (code == openExpression) {
      if (insideExpression) {
        throw new RouterException(
            "Invalid route $routePattern, cannot use expression that contains '(' or ')'");
      } else {
        buffer.writeCharCode(code);
        insideExpression = true;
      }
    } else if (code == closeExpression) {
      if (insideExpression) {
        buffer.writeCharCode(code);
        insideExpression = false;
      } else {
        throw new RouterException(
            "Invalid route $routePattern, cannot use expression that contains '(' or ')'");
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
    throw new RouterException(
        "Invalid route $routePattern, unterminated regular expression");
  }

  if (endingOptionalCloseCount != patterns.length) {
    throw new RouterException(
        "Invalid pattern specifiation, $routePattern, does not close all optionals");
  }

  // Add the final pattern - if no optionals, this is the only pattern.
  patterns.add(buffer.toString());

  return patterns;
}

List<RouteSegment> _splitPathSegments(String path) {
  // Once we've gotten into this method, the path has been validated for optionals and regex and optionals have been removed.

  // Trim leading and trailing
  while (path.startsWith("/")) {
    path = path.substring(1, path.length);
  }
  while (path.endsWith("/")) {
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
    throw new RouterException(
        "Invalid route path $path, contains an empty path segment");
  }

  // Add final
  segments.add(buffer.toString());

  return segments.map((seg) => new RouteSegment(seg)).toList();
}
