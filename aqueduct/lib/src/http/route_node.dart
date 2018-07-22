import 'http.dart';
import 'route_specification.dart';

class RouteSegment {
  RouteSegment(String segment) {
    if (segment == "*") {
      isRemainingMatcher = true;
      return;
    }

    var regexIndex = segment.indexOf("(");
    if (regexIndex != -1) {
      var regexText = segment.substring(regexIndex + 1, segment.length - 1);
      matcher = RegExp(regexText);

      segment = segment.substring(0, regexIndex);
    }

    if (segment.startsWith(":")) {
      variableName = segment.substring(1, segment.length);
    } else if (regexIndex == -1) {
      literal = segment;
    }
  }

  RouteSegment.direct(
      {String literal,
      String variableName,
      String expression,
      bool matchesAnything = false}) {
    this.literal = literal;
    this.variableName = variableName;
    isRemainingMatcher = matchesAnything;
    if (expression != null) {
      matcher = RegExp(expression);
    }
  }

  String literal;
  String variableName;
  RegExp matcher;

  bool get isLiteralMatcher =>
      !isRemainingMatcher && !isVariable && !hasRegularExpression;

  bool get hasRegularExpression => matcher != null;

  bool get isVariable => variableName != null;
  bool isRemainingMatcher = false;

  @override
  bool operator ==(dynamic other) {
    return literal == other.literal &&
        variableName == other.variableName &&
        isRemainingMatcher == other.isRemainingMatcher &&
        matcher?.pattern == other.matcher?.pattern;
  }

  @override
  int get hashCode => (literal ?? variableName).hashCode;

  @override
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

class RouteNode {
  RouteNode(List<RouteSpecification> specs, {int depth = 0, RegExp matcher}) {
    patternMatcher = matcher;

    var terminatedAtThisDepth =
        specs.where((spec) => spec.segments.length == depth).toList();
    if (terminatedAtThisDepth.length > 1) {
      throw ArgumentError(
          "Router compilation failed. Cannot disambiguate from the following routes: $terminatedAtThisDepth.");
    } else if (terminatedAtThisDepth.length == 1) {
      specification = terminatedAtThisDepth.first;
    }

    final remainingSpecifications = List<RouteSpecification>.from(
        specs.where((spec) => depth != spec.segments.length));

    Set<String> childEqualitySegments = Set.from(remainingSpecifications
        .where((spec) => spec.segments[depth].isLiteralMatcher)
        .map((spec) => spec.segments[depth].literal));

    childEqualitySegments.forEach((childSegment) {
      final childrenBeginningWithThisSegment = remainingSpecifications
          .where((spec) => spec.segments[depth].literal == childSegment)
          .toList();
      equalityChildren[childSegment] =
          RouteNode(childrenBeginningWithThisSegment, depth: depth + 1);
      remainingSpecifications
          .removeWhere(childrenBeginningWithThisSegment.contains);
    });

    var takeAllSegment = remainingSpecifications.firstWhere(
        (spec) => spec.segments[depth].isRemainingMatcher,
        orElse: () => null);
    if (takeAllSegment != null) {
      takeAllChild = RouteNode.withSpecification(takeAllSegment);
      remainingSpecifications
          .removeWhere((spec) => spec.segments[depth].isRemainingMatcher);
    }

    Set<String> childPatternedSegments = Set.from(remainingSpecifications
        .map((spec) => spec.segments[depth].matcher?.pattern));

    patternedChildren = childPatternedSegments.map((pattern) {
      var childrenWithThisPattern = remainingSpecifications
          .where((spec) => spec.segments[depth].matcher?.pattern == pattern)
          .toList();

      if (childrenWithThisPattern
              .any((spec) => spec.segments[depth].matcher == null) &&
          childrenWithThisPattern
              .any((spec) => spec.segments[depth].matcher != null)) {
        throw ArgumentError(
            "Router compilation failed. Cannot disambiguate from the following routes, as one of them will match anything: $childrenWithThisPattern.");
      }

      return RouteNode(childrenWithThisPattern,
          depth: depth + 1,
          matcher: childrenWithThisPattern.first.segments[depth].matcher);
    }).toList();
  }

  RouteNode.withSpecification(this.specification);

  // Regular expression matcher for this node. May be null.
  RegExp patternMatcher;
  Controller get controller => specification?.controller;
  RouteSpecification specification;

  // Includes children that are variables with and without regex patterns
  List<RouteNode> patternedChildren = [];

  // Includes children that are literal path segments that can be matched with simple string equality
  Map<String, RouteNode> equalityChildren = {};

  // Valid if has child that is a take all (*) segment.
  RouteNode takeAllChild;

  RouteNode nodeForPathSegments(
      Iterator<String> requestSegments, RequestPath path) {
    if (!requestSegments.moveNext()) {
      return this;
    }

    var nextSegment = requestSegments.current;

    if (equalityChildren.containsKey(nextSegment)) {
      return equalityChildren[nextSegment]
          .nodeForPathSegments(requestSegments, path);
    }

    for (var node in patternedChildren) {
      if (node.patternMatcher == null) {
        // This is a variable with no regular expression
        return node.nodeForPathSegments(requestSegments, path);
      }

      if (node.patternMatcher.firstMatch(nextSegment) != null) {
        // This segment has a regular expression
        return node.nodeForPathSegments(requestSegments, path);
      }
    }

    // If this is null, then we return null from this method
    // and the router knows we didn't find a match.
    return takeAllChild;
  }

  @override
  String toString({int depth = 0}) {
    var buf = StringBuffer();
    for (var i = 0; i < depth; i++) {
      buf.write("\t");
    }

    if (patternMatcher != null) {
      buf.write("(match: ${patternMatcher.pattern})");
    }

    buf.writeln(
        "Controller: ${specification?.controller?.nextController?.runtimeType}");
    equalityChildren.forEach((seg, spec) {
      for (var i = 0; i < depth; i++) {
        buf.write("\t");
      }

      buf.writeln("/$seg");
      buf.writeln(spec.toString(depth: depth + 1));
    });

    return buf.toString();
  }
}
