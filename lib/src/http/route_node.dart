import 'http.dart';

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

  RouteSegment.direct(
      {String literal: null,
      String variableName: null,
      String expression: null,
      bool matchesAnything: false}) {
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

  bool get isLiteralMatcher =>
      !isRemainingMatcher && !isVariable && !hasRegularExpression;
  bool get hasRegularExpression => matcher != null;
  bool get isVariable => variableName != null;
  bool isRemainingMatcher = false;

  bool operator ==(dynamic other) {
    return literal == other.literal &&
        variableName == other.variableName &&
        isRemainingMatcher == other.isRemainingMatcher &&
        matcher?.pattern == other.matcher?.pattern;
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

class RouteNode {
  RouteNode(List<RouteSpecification> specs,
      {int level: 0, RegExp matcher: null}) {
    patternMatcher = matcher;

    var terminatedAtLevel =
        specs.where((spec) => spec.segments.length == level).toList();
    if (terminatedAtLevel.length > 1) {
      throw new RouterException(
          "Cannot disambiguate from the following routes: $terminatedAtLevel");
    } else if (terminatedAtLevel.length == 1) {
      specification = terminatedAtLevel.first;
    }

    specs = new List.from(specs.where((rps) => level < rps.segments.length));
    Set<String> distinctSegmentsAtLevel = new Set.from(specs
        .where((spec) => spec.segments[level].isLiteralMatcher)
        .map((spec) => spec.segments[level].literal));

    distinctSegmentsAtLevel.forEach((segmentLiteral) {
      var literalMatcher = (RouteSpecification spec) =>
          spec.segments[level].literal == segmentLiteral;

      literalChildren[segmentLiteral] =
          new RouteNode(specs.where(literalMatcher).toList(), level: level + 1);
      specs.removeWhere(literalMatcher);
    });

    var anyMatcher = specs.firstWhere(
        (rps) => rps.segments[level].isRemainingMatcher,
        orElse: () => null);
    if (anyMatcher != null) {
      anyMatcherChildNode = new RouteNode.withSpecification(anyMatcher);
      specs.removeWhere((rps) => rps.segments[level].isRemainingMatcher);
    }

    Set<String> distinctPatternsAtLevel =
        new Set.from(specs.map((rps) => rps.segments[level].matcher?.pattern));
    patternMatchChildren = distinctPatternsAtLevel.map((pattern) {
      var matchingSpecs = specs
          .where((rps) => rps.segments[level].matcher?.pattern == pattern)
          .toList();
      if (matchingSpecs.any((rps) => rps.segments[level].matcher == null) &&
          matchingSpecs.any((rps) => rps.segments[level].matcher != null)) {
        throw new RouterException(
            "Cannot disambiguate from the following routes, as one of them will match anything: $matchingSpecs");
      }

      return new RouteNode(matchingSpecs,
          level: level + 1,
          matcher: matchingSpecs.first.segments[level].matcher);
    }).toList();
  }

  RouteNode.withSpecification(this.specification);

  bool matchingAnything = false;
  RegExp patternMatcher;
  RequestController get controller => specification?.controller;
  RouteSpecification specification;
  List<RouteNode> patternMatchChildren = [];
  Map<String, RouteNode> literalChildren = {};
  RouteNode anyMatcherChildNode;

  RouteNode nodeForPathSegments(List<String> requestSegments) {
    if (requestSegments.isEmpty) {
      return this;
    }

    var nextSegment = requestSegments.first;
    var literalChild = literalChildren[nextSegment];
    if (literalChild != null) {
      return literalChild.nodeForPathSegments(
          requestSegments.sublist(1, requestSegments.length));
    }

    for (var node in patternMatchChildren) {
      if (node.patternMatcher == null) {
        return node.nodeForPathSegments(
            requestSegments.sublist(1, requestSegments.length));
      }
      if (node.patternMatcher.firstMatch(nextSegment) != null) {
        return node.nodeForPathSegments(
            requestSegments.sublist(1, requestSegments.length));
      }
    }

    return anyMatcherChildNode;
  }
}
