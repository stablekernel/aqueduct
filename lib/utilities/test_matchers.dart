part of aqueduct;

const Matcher isNumber = const isInstanceOf<num>();
const Matcher isInteger = const isInstanceOf<int>();
const Matcher isDouble = const isInstanceOf<double>();
const Matcher isString = const isInstanceOf<String>();
const Matcher isBoolean = const isInstanceOf<bool>();
Matcher isTimestamp = predicate((str) {
  try {
    var value = DateTime.parse(str);
    return value != null;
  } catch (e) {
    return false;
  }
}, "is timestamp");

HTTPResponseMatcher hasStatus(int v) => new HTTPResponseMatcher(v, null, null);
HTTPResponseMatcher hasResponse(int statusCode, dynamic bodyMatcher, {Map<String, dynamic> headers: null, bool failIfContainsUnmatchedHeader: false}) {
  return new HTTPResponseMatcher(statusCode,
      (headers != null ? new HTTPHeaderMatcher(headers, failIfContainsUnmatchedHeader) : null),
      (bodyMatcher != null ? new HTTPBodyMatcher(bodyMatcher) : null));
}

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

  Description describeMismatch(item, Description mismatchDescription, Map matchState, bool verbose) {
    var responseTypeMismatch = matchState["Response Type"];
    if (responseTypeMismatch != null) {
      mismatchDescription.add("Actual value is not a TestResponse, but instead $responseTypeMismatch.");
    }

    var statusMismatch = matchState["Status Code"];
    if (statusMismatch != null) {
       mismatchDescription.add("Status Code $statusCode != $statusMismatch");
    }

    return mismatchDescription;
  }
}

HTTPBodyMatcher hasBody(dynamic matchSpec) => new HTTPBodyMatcher(matchSpec);

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

  Description describeMismatch(item, Description mismatchDescription, Map matchState, bool verbose) {
    var responseTypeMismatch = matchState["Response Type"];
    if (responseTypeMismatch != null) {
      mismatchDescription.add("Actual value is not a TestResponse, but instead $responseTypeMismatch.");
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

HTTPHeaderMatcher hasHeaders(Map<String, dynamic> matchers, {bool failIfContainsUnmatchedHeader: false}) => new HTTPHeaderMatcher(matchers, failIfContainsUnmatchedHeader);

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
          matchState[headerKey] = "must equal to $valueMatcher, but was $headerValue";
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
          matchState["Header $key"] = "was in response headers, but not part of the match set and failIfContainsUnmatchedHeader was true.";
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

  Description describeMismatch(item, Description mismatchDescription, Map matchState, bool verbose) {
    var responseTypeMismatch = matchState["Response Type"];
    if (responseTypeMismatch != null) {
      mismatchDescription.add("Actual value is not a TestResponse, but instead $responseTypeMismatch.");
    }

    var errors = matchState.keys.map((k) {
      return "$k ${matchState[k]}";
    }).join("\n\t\t  ");

    mismatchDescription.add(errors);

    return mismatchDescription;
  }
}

_PartialMapMatcher partial(Map map) => new _PartialMapMatcher(map);

class _PartialMapMatcher extends Matcher {
  _PartialMapMatcher(Map m) {
    m.forEach((key, val) {
      if (val is Matcher) {
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

      if (value == null) {
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
          addStateInfo(matchState, {"key" : matchKey, "element" : value});
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

  Description describeMismatch(item, Description mismatchDescription, Map matchState, bool verbose) {
    if (matchState["Not Map"] != null) {
      mismatchDescription.add("${matchState["Not Map"]} is not a map");
    }

    if(matchState["missing"] != null) {
      mismatchDescription.add("Missing ${matchState["missing"].join(",")}");
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
      subMatcher.describeMismatch(element, subDescription, matchState['state'], verbose);
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

const isNotPresent = const _NotPresentMatcher();
class _NotPresentMatcher {
  const _NotPresentMatcher();
}

_Converter asNumber(dynamic term) => new _Converter(_ConverterType.number, term);
_Converter asDateTime(dynamic term) => new _Converter(_ConverterType.datetime, term);

enum _ConverterType {
  number,
  datetime
}
class _Converter {
  _Converter(this.type, this.term);
  final _ConverterType type;
  final dynamic term;

  dynamic convertValue(dynamic value) {
    switch (type) {
      case _ConverterType.number: return num.parse(value);
      case _ConverterType.datetime: return DateTime.parse(value);
    }
    return value;
  }
}