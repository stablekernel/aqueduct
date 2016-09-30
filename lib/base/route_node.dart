part of aqueduct;

class _RouteNode {
  _RouteNode(List<RoutePathSpecification> specs, {int level: 0, RegExp matcher: null}) {
    patternMatcher = matcher;

    var terminatedAtLevel = specs
        .where((spec) => spec.segments.length == level)
        .toList();
    if (terminatedAtLevel.length > 1) {
      throw new RouterException("Cannot disambiguate from the following routes: $terminatedAtLevel");
    } else if (terminatedAtLevel.length == 1) {
      specification = terminatedAtLevel.first;
    }

    specs = new List.from(specs.where((rps) => level < rps.segments.length));
    Set<String> distinctSegmentsAtLevel = new Set.from(specs
        .where((spec) => spec.segments[level].isLiteralMatcher)
        .map((spec) => spec.segments[level].literal)
    );

    distinctSegmentsAtLevel.forEach((segmentLiteral) {
      var literalMatcher = (RoutePathSpecification spec) => spec.segments[level].literal == segmentLiteral;

      literalChildren[segmentLiteral] = new _RouteNode(specs.where(literalMatcher).toList(), level: level + 1);
      specs.removeWhere(literalMatcher);
    });

    var anyMatcher = specs.firstWhere((rps) => rps.segments[level].isRemainingMatcher, orElse: () => null);
    if (anyMatcher != null) {
      anyMatcherChildNode = new _RouteNode.withSpecification(anyMatcher);
      specs.removeWhere((rps) => rps.segments[level].isRemainingMatcher);
    }

    Set<String> distinctPatternsAtLevel = new Set.from(specs.map((rps) => rps.segments[level].matcher?.pattern));
    patternMatchChildren = distinctPatternsAtLevel
        .map((pattern) {
            var matchingSpecs = specs.where((rps) => rps.segments[level].matcher?.pattern == pattern).toList();
            if (matchingSpecs.any((rps) => rps.segments[level].matcher == null)
            && matchingSpecs.any((rps) => rps.segments[level].matcher != null)) {
              throw new RouterException("Cannot disambiguate from the following routes, as one of them will match anything: $matchingSpecs");
            }

            return new _RouteNode(matchingSpecs, level: level + 1, matcher: matchingSpecs.first.segments[level].matcher);
        })
        .toList();
  }

  _RouteNode.withSpecification(this.specification);

  bool matchingAnything = false;
  RegExp patternMatcher;
  RequestController get controller => specification?.controller;
  RoutePathSpecification specification;
  List<_RouteNode> patternMatchChildren = [];
  Map<String, _RouteNode> literalChildren = {};
  _RouteNode anyMatcherChildNode;

  _RouteNode nodeForPathSegments(List<String> requestSegments) {
    if (requestSegments.isEmpty) {
      return this;
    }

    var nextSegment = requestSegments.first;
    var literalChild = literalChildren[nextSegment];
    if (literalChild != null) {
      return literalChild.nodeForPathSegments(requestSegments.sublist(1, requestSegments.length));
    }

    for (var node in patternMatchChildren) {
      if (node.patternMatcher == null) {
        return node.nodeForPathSegments(requestSegments.sublist(1, requestSegments.length));
      }
      if (node.patternMatcher.firstMatch(nextSegment) != null) {
        return node.nodeForPathSegments(requestSegments.sublist(1, requestSegments.length));
      }
    }

    return anyMatcherChildNode;
  }
}
