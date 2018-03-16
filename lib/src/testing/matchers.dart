import 'package:aqueduct/aqueduct.dart';
import 'package:matcher/matcher.dart';
import 'package:test/test.dart';

import 'client.dart';
import 'response_matcher.dart';
import 'body_matcher.dart';
import 'header_matcher.dart';
import 'partial_matcher.dart';

/// Validates that value is a [num].
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"id": isNumber}));
///
const Matcher isNumber = const isInstanceOf<num>();

/// Validates that value is an [int].
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"id": isInteger}));
///
const Matcher isInteger = const isInstanceOf<int>();

/// Validates that value is a [double].
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"id": isDouble}));
///
const Matcher isDouble = const isInstanceOf<double>();

/// Validates that value is a [String].
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"id": isString}));
///
const Matcher isString = const isInstanceOf<String>();

/// Validates that value is a [bool].
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"isActive": isBoolean}));
///
const Matcher isBoolean = const isInstanceOf<bool>();


/// Validates that a [DateTime] is after [date].
///
/// When using this matcher with methods like [expectResponse], [hasResponse], [hasHeaders], [hasBody],
/// the compared value will be parsed into a [DateTime] prior to running this matcher.
Matcher isAfter(DateTime date) {
  return predicate((DateTime d) => d.isAfter(date),
      "after ${date.toIso8601String()}");
}

/// Validates that a [DateTime] is before [date].
///
/// When using this matcher with methods like [expectResponse], [hasResponse], [hasHeaders], [hasBody],
/// the compared value will be parsed into a [DateTime] prior to running this matcher.
Matcher isBefore(DateTime date) {
  return predicate((DateTime d) => d.isBefore(date),
      "before ${date.toIso8601String()}");
}


/// Validates that a [DateTime] is before or the same moment as [date].
///
/// When using this matcher with methods like [expectResponse], [hasResponse], [hasHeaders], [hasBody],
/// the compared value will be parsed into a [DateTime] prior to running this matcher.
Matcher isBeforeOrSameMomentAs(DateTime date) {
  return predicate((DateTime d) => d.isBefore(date) || d == date,
      "before or same moment as ${date.toIso8601String()}");
}

/// Validates that a [DateTime] is after or the same moment as [date].
///
/// When using this matcher with methods like [expectResponse], [hasResponse], [hasHeaders], [hasBody],
/// the compared value will be parsed into a [DateTime] prior to running this matcher.
Matcher isAfterOrSameMomentAs(DateTime date) {
  return predicate((DateTime d) => d.isAfter(date) || d == date,
      "after or same moment as ${date.toIso8601String()}");
}

/// Validates that a [DateTime] is the same moment as [date].
///
/// When using this matcher with methods like [expectResponse], [hasResponse], [hasHeaders], [hasBody],
/// the compared value will be parsed into a [DateTime] prior to running this matcher.
Matcher isSameMomentAs(DateTime date) {
  return predicate((DateTime d) => d == date,
      "same moment as ${date.toIso8601String()}");
}

/// Validates that a value is a ISO8601 timestamp.
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
/// This matcher only matches the keys from [map]. If the compared map has additional keys,
/// those keys are not evaluated and will always succeed in matching.
///
/// Example:
///
///         var map = {"id": 1, "name": "foo"};
///         // Validates that the key 'id' is an integer, but ignores key 'name'.
///         // The following succeeds:
///         expect(map, partial({"id": isInteger}));
///
/// You may enforce that the compared value does not have keys with [isNotPresent].
///
/// Example:
///
///       var map = {"id": 1, "name": "foo"};
///       // Validates that the key 'id' is an integer and expects 'name' does not exist
///       // The following will fail because name exists
///       expect(map, partial({"id": isInteger, "name": isNotPresent}));
Matcher partial(Map map) => new PartialMapMatcher(map);

/// This instance is used to validate that a key does not exist in [partial] or HTTP response headers.
///
/// This matcher only works when using [partial] or when matching headers in one of the various HTTP response matchers
/// like [expectResponse], [hasResponse] or [hasHeaders].
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
/// This matcher will validate the status code, body and headers of a [TestResponse]. See also [expectResponse].
///
/// Example:
///
///     var response = await client.request("/foo").get();
///     // Expects that response has status code 200, its body is decoded to a list with a single string element "a",
///     // and has a header "x-version" whose value is "1.0".
///     expect(response, hasResponse(200, ["a"], headers: {
///       "x-version" : "1.0"
///     });
///
/// If the status code of the response does not match the expected status code in this matcher, the matcher will fail.
///
/// [bodyMatcher] is used to evaluate the *decoded* value of an HTTP response body. Decoding occurs according to
/// [HTTPCodecRepository]. In doing so, this method will implicitly ensure that the HTTP response body was decoded
/// according to its Content-Type header.
///
/// If [bodyMatcher] is a primitive type ([Map], [List], [String], etc.), it will be wrapped in an [equals] matcher. Otherwise,
/// it will use the behavior of the matcher specified.
///
/// When matching headers, header keys are evaluated case-insensitively. By default, only the key-value pairs specified by this method
/// are evaluated - if the response contains more headers than [headers], the additional response headers do not impact matching. Set [failIfContainsUnmatchedHeader]
/// to true to expect the exact set of headers.
///
/// The values for [headers] must be [String], [DateTime], [num], or a [Matcher] that compares to one of these types.
///
Matcher hasResponse(int statusCode, dynamic bodyMatcher,
    {Map<String, dynamic> headers,
    bool failIfContainsUnmatchedHeader: false}) {
  return new HTTPResponseMatcher(
      statusCode,
      (headers != null
          ? new HTTPHeaderMatcher(headers, failIfContainsUnmatchedHeader)
          : null),
      (bodyMatcher != null ? new HTTPBodyMatcher(bodyMatcher) : null));
}

/// Short-hand for [expect] and [hasResponse] that returns [response].
///
/// This convenience method runs an expectation on [response] using [hasResponse] built from [statusCode], [body], and [headers], that is:
///
///         expect(response, hasResponse(statusCode, body, headers: headers));
///
/// It makes typical test code easier to compose without having to declare local variables:
///
///         expectResponse(await client.request("/foo").get(),
///           200, body: "foo", headers: {"x-foo": "foo"});
///
/// This method always returns [response] so that it can be used elsewhere in the test.
TestResponse expectResponse(
    TestResponse response,
    int statusCode, {dynamic body, Map<String, dynamic> headers}) {
  expect(response, hasResponse(statusCode, body, headers: headers));
  return response;
}