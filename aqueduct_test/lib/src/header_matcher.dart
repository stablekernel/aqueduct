import 'dart:io';

import 'package:matcher/matcher.dart';

import 'http_value_wrapper.dart';
import 'partial_matcher.dart';

class HTTPHeaderMatcher extends Matcher {
  HTTPHeaderMatcher(Map<String, dynamic> headerMatchSpecifications,
      {this.shouldFailIfOthersPresent = false}) {
    headerMatchSpecifications.forEach((k, v) {
      if (v is Matcher) {
        if (v is! NotPresentMatcher) {
          _specification[k] = HTTPValueMatcherWrapper(v);
        } else {
          _specification[k] = v;
        }
      } else {
        if (v is ContentType) {
          _specification[k] = HTTPValueMatcherWrapper(equals(v.toString()));
        } else {
          _specification[k] = HTTPValueMatcherWrapper(equals(v));
        }
      }
    });
  }

  final Map<String, Matcher> _specification = {};
  final bool shouldFailIfOthersPresent;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! HttpHeaders) {
      throw ArgumentError(
          "Invalid input to HTTPHeaderMatcher.matches. Value is not HttpHeaders.");
    }

    final HttpHeaders input = item as HttpHeaders;
    final mismatches = <String>[];
    matchState["HTTPHeaderMatcher.mismatches"] = mismatches;

    var foundMismatchInHeaders = false;
    _specification.forEach((headerKey, valueMatcher) {
      if (valueMatcher is NotPresentMatcher) {
        if (input.value(headerKey) != null) {
          mismatches.add(headerKey);
          foundMismatchInHeaders = true;
        }

        return;
      }

      final headerValue = input.value(headerKey.toLowerCase());
      if (!valueMatcher.matches(headerValue, matchState)) {
        mismatches.add(headerKey);
        foundMismatchInHeaders = true;
      }
    });

    if (foundMismatchInHeaders) {
      return false;
    }

    if (shouldFailIfOthersPresent) {
      var foundExtraKey = false;
      final extraHeaders = <String>[];
      matchState["HTTPHeaderMatcher.extra"] = extraHeaders;
      input.forEach((key, _) {
        if (!_specification.containsKey(key)) {
          foundExtraKey = true;
          extraHeaders.add("'$key'");
        }
      });

      if (foundExtraKey) {
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
    _specification.forEach((key, value) {
      description.add("  - header '$key' must be ").addDescriptionOf(value);
    });
    description.add("\n");

    return description;
  }

  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
      Map matchState, bool verbose) {
    final extraKeys =
        matchState["HTTPHeaderMatcher.extra"] as List<String> ?? <String>[];
    if (extraKeys.isNotEmpty) {
      mismatchDescription
          .add("actual has extra headers: ")
          .add(extraKeys.join(", "))
          .add("\n");
    }

    final mismatches =
        matchState["HTTPHeaderMatcher.mismatches"] as List<String> ??
            <String>[];
    if (mismatches.isNotEmpty) {
      mismatchDescription.add("the following headers differ: "
          "${mismatches.map((s) => "'$s'").join(", ")}");
    }

    return mismatchDescription;
  }
}
