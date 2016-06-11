part of aqueduct;

HTTPResponseMatcher hasStatus(int v) => new HTTPResponseMatcher(v, [], null);
HTTPResponseMatcher hasResponse(int statusCode, List<HTTPHeaderMatcher> headers, HTTPBodyMatcher body) => new HTTPResponseMatcher(statusCode, headers, body);

class HTTPResponseMatcher extends Matcher {
  HTTPResponseMatcher(this.statusCode, this.headers, this.body);

  int statusCode = null;
  List<HTTPHeaderMatcher> headers = [];
  HTTPBodyMatcher body = null;

  bool matches(item, Map matchState) {
    if (item is! http.Response) {
      matchState["Response Type Is Actually"] = "${item.runtimeType}";
      return false;
    }

    if (item.body != null) {
      matchState["Response Body"] = item.body;
    }

    var tr = item as http.Response;
    if (tr.statusCode != statusCode) {
      matchState["Status Code Is Actually"] = "${tr.statusCode}";
      return false;
    }


    if (body != null) {
      body.contentType = ContentType.parse(tr.headers["content-type"]);
      if (!body.matches(tr.body, matchState)) {
        return false;
      }
    }

    return true;
  }

  Description describe(Description description) {
    if (statusCode != null) {
      description.add("Status Code: $statusCode");
    }

    headers.forEach((h) => h.describe(description));
    if (body != null) {
      body.describe(description);
    }

    return description;
  }

  Description describeMismatch(item, Description mismatchDescription, Map matchState, bool verbose) {
    mismatchDescription.add(matchState.keys.map((key) {
      return "${key}: ${matchState[key]}";
    }).join(", "));
    return mismatchDescription;
  }
}

HTTPBodyMatcher matchesJSONExactly(dynamic jsonMatchSpec) => new HTTPBodyMatcher()
  ..requiresExactMatch = true
  ..contentMatcher = jsonMatchSpec
  ..expectedContentType = ContentType.JSON;

HTTPBodyMatcher matchesJSON(dynamic jsonMatchSpec) => new HTTPBodyMatcher()
  ..requiresExactMatch = false
  ..contentMatcher = jsonMatchSpec
  ..expectedContentType = ContentType.JSON;

HTTPBodyMatcher matchesForm(dynamic jsonMatchSpec) => new HTTPBodyMatcher()
  ..contentMatcher = jsonMatchSpec
  ..expectedContentType = new ContentType("application", "x-www-form-urlencoded");


class HTTPBodyMatcher extends Matcher {
  dynamic contentMatcher;
  ContentType expectedContentType;
  ContentType contentType;
  bool requiresExactMatch = false;

  bool matches(dynamic incomingItem, Map matchState) {
    if (contentType != null && expectedContentType != null
        && (contentType.primaryType != expectedContentType.primaryType || contentType.subType != expectedContentType.subType)) {
      matchState["Content Type Is Actually"] = "${contentType}";
      return false;
    }

    var decodedData = incomingItem;
    if (contentType.primaryType == "application" && contentType.subType == "json") {
      decodedData = JSON.decode(decodedData);
    } else if (contentType.primaryType == "application" && contentType.subType == "x-www-form-urlencoded") {
      var split = (decodedData as String).split("&");
      var map = {};
      split.forEach((str) {
        var innerSplit = str.split("=");
        if (innerSplit.length == 2) {
          map[innerSplit[0]] = innerSplit[1];
        } else {
          map[innerSplit[0]] = true;
        }
      });
      decodedData = map;
    }

    if (contentMatcher is List && decodedData is List) {
      var dataIterator = decodedData.iterator;
      if (requiresExactMatch) {
        for (var matcher in contentMatcher) {
          dataIterator.moveNext();
          var element = dataIterator.current;
          if (matcher is Matcher) {
            if (!matcher.matches(element, matchState)) {
              return false;
            }
          } else {
            if (!mapMatches(element, matcher, matchState)) {
              return false;
            }
          }
        }
      } else {
        var matcher = contentMatcher.first;
        for (var element in decodedData) {
          if (matcher is Matcher) {
            if (!matcher.matches(element, matchState)) {
              return false;
            } else {
              if (!mapMatches(element, matcher, matchState)) {
                return false;
              }
            }
          }
        }
      }
      return true;
    } else if (contentMatcher is Map && decodedData is Map) {
      return mapMatches(decodedData, contentMatcher, matchState);
    } else if (contentMatcher is Matcher) {
      return contentMatcher.matches(decodedData, matchState);
    }

    return false;
  }

  bool mapMatches(Map<String, dynamic> item, Map<String, Matcher> keyMatches, Map matchState) {
    return !keyMatches.keys.map((str) {
      var matcher = keyMatches[str];
      var value = item[str];

      var matches = false;
      if (matcher is Matcher) {
        matches = matcher.matches(value, matchState);
      } else {
        matches = value == matcher;
      }

      if (!matches) {
        matchState["Value for $str Actually Is"] = value;
      }

      return matches;
    }).any((b) => b == false);
  }

  Description describe(Description description) {
    return description;
  }
}

class HTTPHeaderMatcher extends Matcher {
  bool matches(item, Map matchState) {
    return false;
  }

  Description describe(Description description) {
    return description;
  }
}