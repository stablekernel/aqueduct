import 'package:matcher/matcher.dart';

class NotPresentMatcher extends Matcher {
  const NotPresentMatcher();

  @override
  bool matches(dynamic item, Map matchState) {
    // Always returns false, since if it is being evaluated, then the value is present
    return false;
  }

  @override
  Description describe(Description description) {
    return description.add("non-existent");
  }
}

class PartialMapMatcher extends Matcher {
  PartialMapMatcher(Map m) {
    m.forEach((key, val) {
      if (val is Matcher) {
        _matcherMap[key] = val;
      } else {
        _matcherMap[key] = equals(val);
      }
    });
  }

  Map<dynamic, Matcher> _matcherMap = {};

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! Map) {
      matchState["PartialMatcher.runtimeType"] = item.runtimeType;
      return false;
    }

    var mismatches = [];
    matchState["PartialMatcher.mismatches"] = mismatches;

    var foundMismatch = false;
    _matcherMap.forEach((bodyKey, valueMatcher) {
      if (valueMatcher is NotPresentMatcher) {
        if (item.containsKey(bodyKey)) {
          mismatches.add(bodyKey);
          foundMismatch = true;
        }

        return;
      }

      var value = item[bodyKey];
      if (!valueMatcher.matches(value, matchState)) {
        mismatches.add(bodyKey);
        foundMismatch = true;
      }
    });

    if (foundMismatch) {
      return false;
    }

    return true;
  }

  @override
  Description describe(Description description) {
    description.add("a map that contains at least the following: \n");
    _matcherMap.forEach((key, matcher) {
      description.add("    - key '$key' must be ").addDescriptionOf(matcher);
    });

    return description;
  }

  @override
  Description describeMismatch(
      dynamic item, Description mismatchDescription, Map matchState, bool verbose) {
    if (matchState["PartialMatcher.runtimeType"] != null) {
      mismatchDescription.add("is not a map");
      return mismatchDescription;
    }

    List<String> mismatches = matchState["PartialMatcher.mismatches"] ?? [];
    if (mismatches.length > 0) {
      mismatchDescription.add("the following keys differ from partial matcher: \n");
      mismatches.forEach((s) {
        var matcher = _matcherMap[s];
        var value = item[s];
        mismatchDescription.add("  - '$s' ");
        matcher.describeMismatch(value, mismatchDescription, matchState, verbose);
        mismatchDescription.add("\n");
      });
    }

    return mismatchDescription;
  }
}