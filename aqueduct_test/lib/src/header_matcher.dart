import 'dart:io';

import 'package:matcher/matcher.dart';

import 'http_value_wrapper.dart';
import 'partial_matcher.dart';

class HTTPHeaderMatcher extends Matcher {
  HTTPHeaderMatcher(Map<String, dynamic> headerMatchSpecifications,
      {this.shouldFailIfOthersPresent = false}) {
    headerMatchSpecifications.forEach((k, v) {
      if (v is! Matcher) {
        if (v is ContentType) {
          _matchHeaders[k] = HTTPValueMatcherWrapper(equals(v.toString()));
        } else {
          _matchHeaders[k] = HTTPValueMatcherWrapper(equals(v));
        }
      } else {
        if (v is! NotPresentMatcher) {
          _matchHeaders[k] = HTTPValueMatcherWrapper(v);
        } else {
          _matchHeaders[k] = v;
        }
      }
    });
  }

  final Map<String, Matcher> _matchHeaders = {};
  final bool shouldFailIfOthersPresent;

  @override
  bool matches(dynamic item, Map matchState) {
    final HttpHeaders headers = item;
    final mismatches = <String>[];
    matchState["HTTPHeaderMatcher.mismatches"] = mismatches;

    var foundMismatchInHeaders = false;
    _matchHeaders.forEach((headerKey, valueMatcher) {
      if (valueMatcher is NotPresentMatcher) {
        if (headers.value(headerKey) != null) {
          mismatches.add(headerKey);
          foundMismatchInHeaders = true;
        }

        return;
      }

      final headerValue = headers.value(headerKey.toLowerCase());
      if (!valueMatcher.matches(headerValue, matchState)) {
        mismatches.add(headerKey);
        foundMismatchInHeaders = true;
      }
    });

    if (foundMismatchInHeaders) {
      return false;
    }

    if (shouldFailIfOthersPresent) {
      final extraHeaders = <String>[];
      matchState["HTTPHeaderMatcher.extra"] = extraHeaders;
      headers.forEach((key, _) {
        if (!_matchHeaders.containsKey(key)) {
          foundMismatchInHeaders = true;
          extraHeaders.add("'$key'");
        }
      });

      if (foundMismatchInHeaders) {
        return false;
      }
    }

    return true;
  }

  @override
  Description describe(Description description) {
    var modifier = "contain at least the following:";
    if (shouldFailIfOthersPresent) {
      modifier = "are exactly the following:";
    }

    description.add("- Headers $modifier\n");
    _matchHeaders.forEach((key, value) {
      description.add("  - header '$key' must be ").addDescriptionOf(value);
    });
    description.add("\n");

    return description;
  }

  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
      Map matchState, bool verbose) {
    final List<String> extraKeys =
        matchState["HTTPHeaderMatcher.extra"] ?? <String>[];
    if (extraKeys.isNotEmpty) {
      mismatchDescription
          .add("actual has extra headers: ")
          .add(extraKeys.join(", "))
          .add("\n");
    }

    final List<String> mismatches =
        matchState["HTTPHeaderMatcher.mismatches"] ?? <String>[];
    if (mismatches.isNotEmpty) {
      mismatchDescription.add("the following headers differ: "
          "${mismatches.map((s) => "'$s'").join(", ")}");
    }

    return mismatchDescription;
  }
}
