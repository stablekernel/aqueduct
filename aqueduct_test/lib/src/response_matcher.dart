import 'package:matcher/matcher.dart';
import 'agent.dart';
import 'header_matcher.dart';
import 'body_matcher.dart';
import 'matchers.dart';

/// A test matcher that matches a response from an HTTP server.
///
/// See [hasStatus] or [hasResponse] for more details. Use [hasResponse] to create instances of this type.
class HTTPResponseMatcher extends Matcher {
  HTTPResponseMatcher(this.statusCode, this.headers, this.body);

  int statusCode;
  HTTPHeaderMatcher headers;
  HTTPBodyMatcher body;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! TestResponse) {
      matchState["runtimeType"] = item.runtimeType;
      return false;
    }

    var response = item as TestResponse;
    if (statusCode != null && response.statusCode != statusCode) {
      matchState["statusCode"] = response.statusCode;
      return false;
    }

    var success = true;
    if (headers != null) {
      if (!headers.matches(response.headers, matchState)) {
        matchState["HTTPResponseMatcher.didFailOnHeaders"] = true;
        success = false;
      }
    }

    if (body != null) {
      if (!body.matches(response.body.asDynamic(), matchState)) {
        matchState["HTTPResponseMatcher.didFailOnBody"] = true;
        success = false;
      }
    }

    return success;
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
  Description describeMismatch(
      dynamic item, Description mismatchDescription, Map matchState, bool verbose) {
    var responseTypeMismatch = matchState["runtimeType"];
    if (responseTypeMismatch != null) {
      mismatchDescription.add(
          "Is not an instance of TestResponse");
      return mismatchDescription;
    }

    var response = item as TestResponse;
    var statusMismatch = matchState["statusCode"];
    if (statusMismatch != null) {
      mismatchDescription.add("Status codes are different. Expected: $statusCode. Actual: $statusMismatch");
    }

    if (matchState["HTTPResponseMatcher.didFailOnHeaders"] == true) {
      headers.describeMismatch(response.headers, mismatchDescription, matchState, verbose);
    }

    if (matchState["HTTPResponseMatcher.didFailOnBody"] == true) {
      body.describeMismatch(response.body.asDynamic(), mismatchDescription, matchState, verbose);
    }

    return mismatchDescription;
  }
}