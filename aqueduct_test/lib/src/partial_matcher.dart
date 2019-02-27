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
  PartialMapMatcher(Map<String, dynamic> m) {
    m.forEach((key, val) {
      if (val is Matcher) {
        _matcherMap[key] = val;
      } else {
        _matcherMap[key] = equals(val);
      }
    });
  }

  final Map<String, Matcher> _matcherMap = {};

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! Map<String, dynamic>) {
      matchState["PartialMatcher.runtimeType"] = item.runtimeType;
      return false;
    }

    final inputMap = item as Map<String, dynamic>;
    final mismatches = <String>[];
    matchState["PartialMatcher.mismatches"] = mismatches;
    var foundMismatch = false;
    _matcherMap.forEach((bodyKey, valueMatcher) {
      if (valueMatcher is NotPresentMatcher) {
        if (inputMap.containsKey(bodyKey)) {
          mismatches.add(bodyKey);
          foundMismatch = true;
        }

        return;
      }

      final value = inputMap[bodyKey];
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
  Description describeMismatch(dynamic item, Description mismatchDescription,
      Map matchState, bool verbose) {
    if (matchState["PartialMatcher.runtimeType"] != null) {
      mismatchDescription.add("is not a map");
      return mismatchDescription;
    }

    final mismatches =
        matchState["PartialMatcher.mismatches"] as List<String> ?? <String>[];
    if (mismatches.isNotEmpty) {
      mismatchDescription
          .add("the following keys differ from partial matcher: \n");
      mismatches.forEach((s) {
        final matcher = _matcherMap[s];
        final value = item[s];
        mismatchDescription.add("  - '$s' ");
        matcher.describeMismatch(
            value, mismatchDescription, matchState, verbose);
        mismatchDescription.add("\n");
      });
    }

    return mismatchDescription;
  }
}
