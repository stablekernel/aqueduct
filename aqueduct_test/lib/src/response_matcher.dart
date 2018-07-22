import 'package:matcher/matcher.dart';

import 'agent.dart';
import 'body_matcher.dart';
import 'header_matcher.dart';
import 'matchers.dart';

/// A test matcher that matches a response from an HTTP server.
///
/// See [hasStatus] or [hasResponse] for more details. Use [hasResponse] to create instances of this type.
class HTTPResponseMatcher extends Matcher {
  HTTPResponseMatcher(this.statusCode, this.headers, this.body);

  final int statusCode;
  final HTTPHeaderMatcher headers;
  final HTTPBodyMatcher body;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! TestResponse) {
      matchState["HTTPResponseMatcher.runtimeType"] = item.runtimeType;
      return false;
    }

    final shouldMatchStatusCode = statusCode != null;
    final shouldMatchHeaders = headers != null;
    final shouldMatchBody = body != null;

    final response = item as TestResponse;
    if (shouldMatchStatusCode) {
      if (response.statusCode != statusCode) {
        matchState["HTTPResponseMatcher.statusCode"] = response.statusCode;
        return false;
      }
    }

    if (shouldMatchHeaders) {
      if (!headers.matches(response.headers, matchState)) {
        matchState["HTTPResponseMatcher.didFailOnHeaders"] = true;
        return false;
      }
    }

    if (shouldMatchBody) {
      if (!body.matches(response.body.as(), matchState)) {
        matchState["HTTPResponseMatcher.didFailOnBody"] = true;
        return false;
      }
    }

    return true;
  }

  @override
  Description describe(Description description) {
    description.add("--- HTTP Response ---");
    description.add("\n- Status code ");
    if (statusCode != null) {
      description.add("must be $statusCode");
    } else {
      description.add("can be anything");
    }

    description.add("\n");

    if (headers != null) {
      headers.describe(description);
    } else {
      description.add("- Headers can be anything\n");
    }

    if (body != null) {
      body.describe(description);
    } else {
      description.add("- Body can be anything");
    }

    return description.add("\n---------------------");
  }

  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
      Map matchState, bool verbose) {
    final responseTypeMismatch = matchState["HTTPResponseMatcher.runtimeType"];
    if (responseTypeMismatch != null) {
      mismatchDescription.add("Is not an instance of TestResponse");
      return mismatchDescription;
    }

    final response = item as TestResponse;
    final statusMismatch = matchState["HTTPResponseMatcher.statusCode"];
    if (statusMismatch != null) {
      mismatchDescription.add(
          "Status codes are different. Expected: $statusCode. Actual: $statusMismatch");
    }

    if (matchState["HTTPResponseMatcher.didFailOnHeaders"] == true) {
      headers.describeMismatch(
          response.headers, mismatchDescription, matchState, verbose);
    }

    if (matchState["HTTPResponseMatcher.didFailOnBody"] == true) {
      body.describeMismatch(
          response.body.as(), mismatchDescription, matchState, verbose);
    }

    return mismatchDescription;
  }
}
