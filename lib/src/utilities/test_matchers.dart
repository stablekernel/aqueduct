import 'package:matcher/matcher.dart';
import 'test_client.dart';

/// Validates that expected result is a [num].
const Matcher isNumber = const isInstanceOf<num>();

/// Validates that expected result is an [int].
const Matcher isInteger = const isInstanceOf<int>();

/// Validates that expected result is a [double].
const Matcher isDouble = const isInstanceOf<double>();

/// Validates that expected result is a [String].
const Matcher isString = const isInstanceOf<String>();

/// Validates that expected result is a [bool].
const Matcher isBoolean = const isInstanceOf<bool>();

/// Validates that expected result is a ISO8601 timestamp.
Matcher isTimestamp = predicate((str) {
  try {
    var value = DateTime.parse(str);
    return value != null;
  } catch (e) {
    return false;
  }
}, "is timestamp");

/// A matcher that partially matches a [Map].
///
/// This matcher allows you to specify a subset of keys in a [Map] to be matched,
/// without having to match every key in a [Map]. This is useful for specific conditions
/// in an HTTP response without validating the entire data structure, especially when that
/// data structure is large. See [hasResponse] for more details.
_PartialMapMatcher partial(Map map) => new _PartialMapMatcher(map);

/// This instance is used to validate that a header or key does not exist.
///
/// When using [hasResponse], [hasHeaders] or [partial], this instance can be used
/// as a value to indicate that a particular key should not exist. For example, the following
/// would ensure that the evaluated map does not have the key 'foo':
///
///         expect(map, partial(
///           "id" : greaterThan(0),
///           "foo" : isNotPresent
///         });
const isNotPresent = const _NotPresentMatcher();

/// Converts a header value to an instance of [int] to be used inside a matcher.
///
/// See [hasResponse] for more details.
_Converter asNumber(dynamic term) =>
    new _Converter(_ConverterType.number, term);

/// Converts a header value to an instance of [DateTime] to be used inside a matcher.
///
/// See [hasResponse] for more details.
_Converter asDateTime(dynamic term) =>
    new _Converter(_ConverterType.datetime, term);

/// Validates that a [TestResponse] has the specified HTTP status code.
///
/// This matcher only validates the status code. See [hasResponse] for more details.
HTTPResponseMatcher hasStatus(int statusCode) =>
    new HTTPResponseMatcher(statusCode, null, null);

/// Validates that a [TestResponse] has the specified HTTP response body.
///
/// This matcher only validates the HTTP response body. See [hasResponse] for more details.
HTTPBodyMatcher hasBody(dynamic matchSpec) => new HTTPBodyMatcher(matchSpec);

/// Validates that a [TestResponse] has the specified HTTP headers.
///
/// This matcher only validates the HTTP headers. See [hasResponse] for more details.
HTTPHeaderMatcher hasHeaders(Map<String, dynamic> matchers,
        {bool failIfContainsUnmatchedHeader: false}) =>
    new HTTPHeaderMatcher(matchers, failIfContainsUnmatchedHeader);

/// Validates that a [TestResponse] has the specified status code, body and headers.
///
/// This matcher will validate the status code, body and headers of a [TestResponse].
///
/// If the status code of the response does not match the expected status code in this matcher, the matcher will fail.
///
/// [bodyMatcher] is used to evaluate the *decoded* value of the HTTP response body. In doing so, this method will implicitly
/// ensure that the HTTP response body was decoded according to its Content-Type header. [bodyMatcher] may be a matcher or it may
/// be [Map] or [List]. When [bodyMatcher] is a [Map] or [List], the value is compared for equality to the decoded HTTP response body. For example,
/// the following would match on a response with Content-Type: application/json and a body of '{"key" : "value"}':
///
///         expect(response, hasResponse(200, {"key" : "value"});
///
/// When using a matcher, the matcher will use its own matching behavior. For example, if the response had a JSON list of strings, the following
/// would expect that each object contains the substring 'foo':
///
///         expect(response, hasResponse(200, everyElement(contains("foo")));
///
/// For matching a subset of keys in a [Map], see [partial].
///
/// You may optionally validate HTTP headers as well. By default, only key-value pairs in [headers] are evaluated for matches. Headers
/// that exist in the response but are not included in [headers] will not be evaluated and will not impact whether or not this matcher succeeds
/// or fails. If you wish to match an exhaustive list of all headers in a request, pass [failIfContainsUnmatchedHeader] as true.
///
/// Header keys are case-insensitive strings. Header values are typically instances of [String] or instances of [Matcher]. If using a matcher,
/// you may optionally wrap the matcher in [asNumber] or [asDateTime] to convert the header value in the response to an instance of [int] or [DateTime]
/// prior to it being matched.
///
/// Example:
///
///      expect(response, hasResponse(200, [], headers: {
///         "x-version" : asNumber(greaterThan(1))(
///      });
HTTPResponseMatcher hasResponse(int statusCode, dynamic bodyMatcher,
    {Map<String, dynamic> headers: null,
    bool failIfContainsUnmatchedHeader: false}) {
  return new HTTPResponseMatcher(
      statusCode,
      (headers != null
          ? new HTTPHeaderMatcher(headers, failIfContainsUnmatchedHeader)
          : null),
      (bodyMatcher != null ? new HTTPBodyMatcher(bodyMatcher) : null));
}

/// A test matcher that matches a response from an HTTP server.
///
/// See [hasStatus] or [hasResponse] for more details.
class HTTPResponseMatcher extends Matcher {
  HTTPResponseMatcher(this.statusCode, this.headers, this.body);

  int statusCode = null;
  HTTPHeaderMatcher headers = null;
  HTTPBodyMatcher body = null;

  bool matches(item, Map matchState) {
    if (item is! TestResponse) {
      matchState["Response Type"] = item.runtimeType;
      return false;
    }

    if (statusCode != null && item.statusCode != statusCode) {
      matchState["Status Code"] = item.statusCode;
      return false;
    }

    if (headers != null) {
      if (!headers.matches(item, matchState)) {
        return false;
      }
    }

    if (body != null) {
      if (!body.matches(item, matchState)) {
        return false;
      }
    }

    return true;
  }

  Description describe(Description description) {
    if (statusCode != null) {
      description.add("\n\tStatus Code: $statusCode");
    }
    if (headers != null) {
      description.add("\n\t");
      headers.describe(description);
    }
    if (body != null) {
      description.add("\n\t");
      body.describe(description);
    }

    return description;
  }

  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    var responseTypeMismatch = matchState["Response Type"];
    if (responseTypeMismatch != null) {
      mismatchDescription.add(
          "Actual value is not a TestResponse, but instead $responseTypeMismatch.");
    }

    var statusMismatch = matchState["Status Code"];
    if (statusMismatch != null) {
      mismatchDescription.add("Status Code $statusCode != $statusMismatch");
    }

    return mismatchDescription;
  }
}

/// A test matcher that matches an HTTP response body.
///
/// See [hasBody] or [hasResponse] for more details.
class HTTPBodyMatcher extends Matcher {
  HTTPBodyMatcher(dynamic matcher) {
    if (matcher is Matcher) {
      contentMatcher = matcher;
    } else {
      contentMatcher = equals(matcher);
    }
  }

  dynamic contentMatcher;

  bool matches(dynamic item, Map matchState) {
    if (item is! TestResponse) {
      matchState["Response Type"] = item.runtimeType;
      return false;
    }

    var decodedData = item.decodedBody;
    if (!contentMatcher.matches(decodedData, matchState)) {
      return false;
    }

    return true;
  }

  Description describe(Description description) {
    description.add("Body: ");
    description.addDescriptionOf(contentMatcher);

    return description;
  }

  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    var responseTypeMismatch = matchState["Response Type"];
    if (responseTypeMismatch != null) {
      mismatchDescription.add(
          "Actual value is not a TestResponse, but instead $responseTypeMismatch.");
    }

    mismatchDescription
        .add('has value ')
        .addDescriptionOf(contentMatcher)
        .add(' which ');

    try {
      var subDescription = new StringDescription();
      contentMatcher.describeMismatch(
          item, subDescription, matchState, verbose);
      if (subDescription.length > 0) {
        mismatchDescription.add(subDescription.toString());
      } else {
        mismatchDescription.add("doesn't match ");
        contentMatcher.describe(mismatchDescription);
      }
    } catch (_) {}

    return mismatchDescription;
  }
}

/// A test matcher that matches HTTP headers.
///
/// See [hasHeaders] or [hasResponse] for more details.
class HTTPHeaderMatcher extends Matcher {
  HTTPHeaderMatcher(this.matchHeaders, this.shouldFailIfOthersPresent);
  Map<String, dynamic> matchHeaders;
  bool shouldFailIfOthersPresent;

  bool matches(item, Map matchState) {
    if (item is! TestResponse) {
      matchState["Response Type"] = item.runtimeType;
      return false;
    }

    var failedToMatch = false;
    matchHeaders.forEach((headerKey, valueMatcher) {
      var headerValue = item.headers.value(headerKey.toLowerCase());

      if (valueMatcher is _NotPresentMatcher) {
        if (headerValue != null) {
          matchState[headerKey] = "must not be present, but was $headerValue.";
          failedToMatch = true;
        }
        return;
      }

      if (valueMatcher is _Converter) {
        headerValue = valueMatcher.convertValue(headerValue);
        valueMatcher = valueMatcher.term;
      }

      if (valueMatcher is Matcher) {
        if (!valueMatcher.matches(headerValue, matchState)) {
          failedToMatch = true;
        }
      } else {
        if (headerValue != valueMatcher) {
          matchState[headerKey] =
              "must equal to $valueMatcher, but was $headerValue";
          failedToMatch = true;
        }
      }
    });

    if (failedToMatch) {
      return false;
    }

    if (shouldFailIfOthersPresent) {
      item.headers.forEach((key, _) {
        if (!matchHeaders.containsKey(key)) {
          failedToMatch = true;
          matchState["Header $key"] =
              "was in response headers, but not part of the match set and failIfContainsUnmatchedHeader was true.";
        }
      });

      if (failedToMatch) {
        return false;
      }
    }

    return true;
  }

  Description describe(Description description) {
    description.add("Headers: ");
    var first = false;
    matchHeaders.forEach((key, value) {
      if (first) {
        description.add("\n\t\t\t");
        first = false;
      }
      if (value is _NotPresentMatcher) {
        description.add("$key: (Must Not Exist)");
      } else if (value is Matcher) {
        description.add("$key: ");
        value.describe(description);
      } else {
        description.add("$key: $value");
      }
    });

    return description;
  }

  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    var responseTypeMismatch = matchState["Response Type"];
    if (responseTypeMismatch != null) {
      mismatchDescription.add(
          "Actual value is not a TestResponse, but instead $responseTypeMismatch.");
    }

    var errors = matchState.keys.map((k) {
      return "$k ${matchState[k]}";
    }).join("\n\t\t  ");

    mismatchDescription.add(errors);

    return mismatchDescription;
  }
}

class _PartialMapMatcher extends Matcher {
  _PartialMapMatcher(Map m) {
    m.forEach((key, val) {
      if (val is Matcher || val is _NotPresentMatcher) {
        map[key] = val;
      } else {
        map[key] = equals(val);
      }
    });
  }

  Map<dynamic, Matcher> map = {};

  bool matches(item, Map matchState) {
    if (item is! Map) {
      matchState["Not Map"] = "was ${item.runtimeType}";
      return false;
    }

    for (var matchKey in map.keys) {
      var matchValue = map[matchKey];
      var value = item[matchKey];
      if (matchValue is _NotPresentMatcher) {
        if (item.containsKey(matchKey)) {
          var extra = matchState["extra"];
          if (extra == null) {
            extra = [];
            matchState["extra"] = extra;
          }
          extra = matchKey;
          return false;
        }
      } else if (value == null && !matchValue.matches(value, matchState)) {
        var missing = matchState["missing"];
        if (missing == null) {
          missing = [];
          matchState["missing"] = missing;
        }
        missing = matchKey;
        return false;
      }

      if (matchValue is Matcher) {
        if (!matchValue.matches(value, matchState)) {
          addStateInfo(matchState, {"key": matchKey, "element": value});
          return false;
        }
      }
    }

    return true;
  }

  Description describe(Description description) {
    description.add("Partially matches: {");
    map.forEach((key, matcher) {
      description.add("$key: ");
      description.addDescriptionOf(matcher);
      description.add(",");
    });
    description.add("}");

    return description;
  }

  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    if (matchState["Not Map"] != null) {
      mismatchDescription.add("${matchState["Not Map"]} is not a map");
    }

    if (matchState["missing"] != null) {
      mismatchDescription.add("Missing ${matchState["missing"].join(",")}");
    }

    if (matchState["extra"] != null) {
      mismatchDescription
          .add("Should not include ${matchState["extra"].join(",")}");
    }

    if (matchState["key"] != null) {
      var key = matchState["key"];
      var element = matchState["element"];
      mismatchDescription
          .add('has value ')
          .addDescriptionOf(element)
          .add(' which ');

      var subMatcher = map[key];
      var subDescription = new StringDescription();
      subMatcher.describeMismatch(
          element, subDescription, matchState['state'], verbose);
      if (subDescription.length > 0) {
        mismatchDescription.add(subDescription.toString());
      } else {
        mismatchDescription.add("doesn't match ");
        subMatcher.describe(mismatchDescription);
      }
      mismatchDescription.add(' for key $key');
    }

    return mismatchDescription;
  }
}

class _NotPresentMatcher {
  const _NotPresentMatcher();
}

enum _ConverterType { number, datetime }

class _Converter {
  _Converter(this.type, this.term);
  final _ConverterType type;
  final dynamic term;

  dynamic convertValue(dynamic value) {
    switch (type) {
      case _ConverterType.number:
        return num.parse(value);
      case _ConverterType.datetime:
        return DateTime.parse(value);
    }
    return value;
  }
}
