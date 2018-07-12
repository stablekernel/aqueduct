import 'dart:io';

import 'package:matcher/matcher.dart';
import 'partial_matcher.dart';
import 'http_value_wrapper.dart';

class HTTPHeaderMatcher extends Matcher {
  HTTPHeaderMatcher(Map<String, dynamic> headerMatchSpecifications, this.shouldFailIfOthersPresent) {
    headerMatchSpecifications.forEach((k, v) {
      if (v is! Matcher) {
        if (v is ContentType) {
          _matchHeaders[k] = new HTTPValueMatcherWrapper(equals(v.toString()));
        } else {
          _matchHeaders[k] = new HTTPValueMatcherWrapper(equals(v));
        }
      } else {
        if (v is! NotPresentMatcher) {
          _matchHeaders[k] = new HTTPValueMatcherWrapper(v);
        } else {
          _matchHeaders[k] = v;
        }
      }
    });
  }

  Map<String, Matcher> _matchHeaders = {};
  bool shouldFailIfOthersPresent;

  @override
  bool matches(dynamic item, Map matchState) {
    HttpHeaders headers = item;
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

      var headerValue = headers.value(headerKey.toLowerCase());
      if (!valueMatcher.matches(headerValue, matchState)) {
        mismatches.add(headerKey);
        foundMismatchInHeaders = true;
      }
    });

    if (foundMismatchInHeaders) {
      return false;
    }

    if (shouldFailIfOthersPresent) {
      var extraHeaders = <String>[];
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
  Description describeMismatch(
      dynamic item, Description mismatchDescription, Map matchState, bool verbose) {
    List<String> extraKeys = matchState["HTTPHeaderMatcher.extra"] ?? <String>[];
    if (extraKeys.length > 0) {
      mismatchDescription.add("actual has extra headers: ").add(extraKeys.join(", ")).add("\n");
    }

    List<String> mismatches = matchState["HTTPHeaderMatcher.mismatches"] ?? <String>[];
    if (mismatches.length > 0) {
      mismatchDescription.add(
          "the following headers differ: "
          "${mismatches.map((s) => "'$s'").join(", ")}");
    }

    return mismatchDescription;
  }
}