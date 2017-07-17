import 'dart:io';

import 'package:matcher/matcher.dart';
import 'package:test/test.dart';

import 'client.dart';
import 'response_matcher.dart';
import 'body_matcher.dart';
import 'header_matcher.dart';
import 'partial_matcher.dart';

/// Validates that expected result is a [num].
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"id": isNumber}));
///
const Matcher isNumber = const isInstanceOf<num>();

/// Validates that expected result is an [int].
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"id": isInteger}));
///
const Matcher isInteger = const isInstanceOf<int>();

/// Validates that expected result is a [double].
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"id": isDouble}));
///
const Matcher isDouble = const isInstanceOf<double>();

/// Validates that expected result is a [String].
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"id": isString}));
///
const Matcher isString = const isInstanceOf<String>();

/// Validates that expected result is a [bool].
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"isActive": isBoolean}));
///
const Matcher isBoolean = const isInstanceOf<bool>();

Matcher isAfter(DateTime date) {
  return predicate((DateTime d) => d.isAfter(date),
      "after ${date.toIso8601String()}");
}

Matcher isBefore(DateTime date) {
  return predicate((DateTime d) => d.isBefore(date),
      "before ${date.toIso8601String()}");
}

Matcher isBeforeOrSameMomentAs(DateTime date) {
  return predicate((DateTime d) => d.isBefore(date) || d == date,
      "before or same moment as ${date.toIso8601String()}");
}

Matcher isAfterOrSameMomentAs(DateTime date) {
  return predicate((DateTime d) => d.isAfter(date) || d == date,
      "after or same moment as ${date.toIso8601String()}");
}

Matcher isSameMomentAs(DateTime date) {
  return predicate((DateTime d) => d == date,
      "same moment as ${date.toIso8601String()}");
}

/// Validates that expected result is a ISO8601 timestamp.
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"createdDate": isTimestamp}));
///
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
///
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         // Validates that the key 'id' is an integer, but the map may contain more keys.
///         expect(response, hasResponse(200, partial({"id": isInteger})));
///
Matcher partial(Map map) => new PartialMapMatcher(map);

/// This instance is used to validate that a header or key does not exist.
///
/// When using [hasResponse], [hasHeaders] or [partial], this instance can be used
/// as a value to indicate that a particular key should not exist. For example, the following
/// would ensure that the evaluated map does not have the key 'foo':
///
///         expect(map, partial({
///           "id" : greaterThan(0),
///           "foo" : isNotPresent
///         });
const Matcher isNotPresent = const NotPresentMatcher();

/// Validates that a [TestResponse] has the specified HTTP status code.
///
/// This matcher only validates the status code. See [hasResponse] for more details. Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasStatus(404));
Matcher hasStatus(int statusCode) =>
    new HTTPResponseMatcher(statusCode, null, null);

/// Validates that a [TestResponse] has the specified HTTP response body.
///
/// This matcher only validates the HTTP response body. See [hasResponse] for more details. Usage:
///
///       var response = await client.request("/foo").get();
///       expect(response, hasBody("string body"));
Matcher hasBody(dynamic matchSpec) =>
    new HTTPResponseMatcher(null, null, new HTTPBodyMatcher(matchSpec));

/// Validates that a [TestResponse] has the specified HTTP headers.
///
/// This matcher only validates the HTTP headers. See [hasResponse] for more details. Usage:
///
///       var response = await client.request("/foo").get();
///       expect(response, hasHeaders(partial({"x-request-id": 4})));
Matcher hasHeaders(Map<String, dynamic> matchers,
        {bool failIfContainsUnmatchedHeader: false}) =>
    new HTTPResponseMatcher(
        null, 
        new HTTPHeaderMatcher(matchers, failIfContainsUnmatchedHeader),
        null);

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
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"key" : "value"});
///
/// When using a matcher, the matcher will use its own matching behavior. For example, if the response had a JSON list of strings, the following
/// would expect that each object contains the substring 'foo':
///
///         var response = await client.request("/foo").get();
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
///      var response = await client.request("/foo").get();
///      expect(response, hasResponse(200, [], headers: {
///         "x-version" : asNumber(greaterThan(1))(
///      });
Matcher hasResponse(int statusCode, dynamic bodyMatcher,
    {Map<String, dynamic> headers: null,
    bool failIfContainsUnmatchedHeader: false}) {
  return new HTTPResponseMatcher(
      statusCode,
      (headers != null
          ? new HTTPHeaderMatcher(headers, failIfContainsUnmatchedHeader)
          : null),
      (bodyMatcher != null ? new HTTPBodyMatcher(bodyMatcher) : null));
}

TestResponse expectResponse(
    TestResponse response,
    int statusCode, {dynamic body, Map<String, dynamic> headers}) {
  expect(response, hasResponse(statusCode, body, headers: headers));
  return response;
}

@Deprecated("3.0, no longer necessary")
dynamic asNumber(dynamic value) => value;

@Deprecated("3.0, no longer necessary")
dynamic asDateTime(dynamic value) => value;