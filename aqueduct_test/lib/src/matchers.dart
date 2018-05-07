import 'package:aqueduct/aqueduct.dart';
import 'package:matcher/matcher.dart';
import 'package:test/test.dart';

import 'mock_server.dart';
import 'agent.dart';
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
/// This matcher has additional behavior when used in [expectResponse], [hasResponse], [hasHeaders], [hasBody]:
/// if the actual value is a [String], it will attempted to be parsed into a [DateTime] first.
/// If parsing fails, this matcher will fail.
///
///         expectResponse(response, 200, headers: {"x-timestamp": isAfter(new DateTime())});
Matcher isAfter(DateTime date) {
  return predicate((DateTime d) => d.isAfter(date), "after ${date.toIso8601String()}");
}

/// Validates that a [DateTime] is before [date].
///
/// This matcher has additional behavior when used in [expectResponse], [hasResponse], [hasHeaders], [hasBody]:
/// if the actual value is a [String], it will attempted to be parsed into a [DateTime] first.
/// If parsing fails, this matcher will fail.
///
///         expectResponse(response, 200, headers: {"x-timestamp": isBefore(new DateTime())});
Matcher isBefore(DateTime date) {
  return predicate((DateTime d) => d.isBefore(date), "before ${date.toIso8601String()}");
}

/// Validates that a [DateTime] is before or the same moment as [date].
///
/// This matcher has additional behavior when used in [expectResponse], [hasResponse], [hasHeaders], [hasBody]:
/// if the actual value is a [String], it will attempted to be parsed into a [DateTime] first.
/// If parsing fails, this matcher will fail.
///
///         expectResponse(response, 200, headers: {"x-timestamp": isBeforeOrSameMomentAs(new DateTime())});
Matcher isBeforeOrSameMomentAs(DateTime date) {
  return predicate((DateTime d) => d.isBefore(date) || d == date, "before or same moment as ${date.toIso8601String()}");
}

/// Validates that a [DateTime] is after or the same moment as [date].
///
/// This matcher has additional behavior when used in [expectResponse], [hasResponse], [hasHeaders], [hasBody]:
/// if the actual value is a [String], it will attempted to be parsed into a [DateTime] first.
/// If parsing fails, this matcher will fail.
///
///         expectResponse(response, 200, headers: {"x-timestamp": isAfterOrSameMomentAs(new DateTime())});
Matcher isAfterOrSameMomentAs(DateTime date) {
  return predicate((DateTime d) => d.isAfter(date) || d == date, "after or same moment as ${date.toIso8601String()}");
}

/// Validates that a [DateTime] is the same moment as [date].
///
/// This matcher has additional behavior when used in [expectResponse], [hasResponse], [hasHeaders], [hasBody]:
/// if the actual value is a [String], it will attempted to be parsed into a [DateTime] first.
/// If parsing fails, this matcher will fail.
///
///         expectResponse(response, 200, headers: {"x-timestamp": isSameMomentAs(new DateTime())});
Matcher isSameMomentAs(DateTime date) {
  return predicate((DateTime d) => d == date, "same moment as ${date.toIso8601String()}");
}

/// Validates that a value is a ISO8601 timestamp.
///
/// Usage:
///
///         var response = await client.request("/foo").get();
///         expect(response, hasResponse(200, {"createdDate": isTimestamp}));
Matcher isTimestamp = predicate((str) {
  try {
    var value = DateTime.parse(str);
    return value != null;
  } catch (e) {
    return false;
  }
}, "is timestamp");

/// A matcher for maps that only checks the values of the provided keys.
///
/// This matcher only matches the keys from [map]. Other keys in
/// the actual map are ignored, and any value will be accepted.
///
/// Example:
///
///         var map = {
///           "id": 1,
///           "name": "foo"
///         };
///
///         expect(map, partial({
///           "id": isInteger
///         })); // succeeds
///
/// You may enforce that the actual value does *not* have a key by storing [isNotPresent]
/// for that key.
///
/// Example:
///
///       var map = {
///         "id": 1,
///         "name": "foo"
///       };
///
///       expect(map, partial({
///         "id": isInteger,
///         "name": isNotPresent
///       })); // fails because 'name' is present
Matcher partial(Map map) => new PartialMapMatcher(map);

/// Validates that a key is not present when using [partial].
///
/// This matcher has no effect when used outside of [partial].
/// See [partial] for usage.
const Matcher isNotPresent = const NotPresentMatcher();

/// Validates that [TestResponse] has a status code of [statusCode].
///
///         var response = await client.request("/foo").get();
///         expect(response, hasStatus(404));
Matcher hasStatus(int statusCode) => new HTTPResponseMatcher(statusCode, null, null);

/// Validates that [TestResponse] has a decoded body that matches [bodyMatcher].
///
/// The body of the actual response will be decoded according to its content-type
/// before being evaluated. For example, a JSON object encoded as
/// 'application/json' will become a `Map`. If the body cannot
/// be decoded or is decoded into the wrong type, this matcher
/// will fail.
///
///       var response = await client.request("/foo").get();
///       expect(response, hasBody({
///         "key": "value"
///       ));
Matcher hasBody(dynamic bodyMatcher) => new HTTPResponseMatcher(null, null, new HTTPBodyMatcher(bodyMatcher));

/// Validates that [TestResponse] has headers that match [headerMatcher].
///
/// Each key in [headerMatcher] is case-insensitively compared to the headers in the actual response,
/// the matcher for the key is then compared to the header value.
///
/// By default, if a response contains a header name not in [headerMatcher], it is ignored
/// and any value will be acceptable. This is the same behavior as if using [partial].
///
///       var response = await client.request("/foo").get();
///       expect(response, hasHeaders({
///         "x-timestamp": isBefore(new DateTime.now())
///       })));
///
/// You may pass [failIfContainsUnmatchedHeader] as true to force evaluate every
/// header in the response - but recall that many requests contain headers
/// that do not need to be tested or may change depending on the environment.
Matcher hasHeaders(Map<String, dynamic> headerMatcher, {bool failIfContainsUnmatchedHeader: false}) =>
    new HTTPResponseMatcher(null, new HTTPHeaderMatcher(headerMatcher, failIfContainsUnmatchedHeader), null);

/// Validates that [TestResponse] has the same status code, headers and body as [statusCode], [bodyMatcher], and [headerMatcher].
///
/// This method composes [hasStatus], [hasBody], and [hasHeaders] into a single matcher. See
/// each of these individual method for behavior details.
///
/// If either [body] or [headers] is null or not provided, they will not be matched and
/// any value will be acceptable.
///
/// Example:
///
///     var response = await client.request("/foo").get();
///     expect(response, hasResponse(200, body: ["a"], headers: {
///       "x-version" : "1.0"
///     });
///
/// For details on [failIfContainsUnmatchedHeader], see [hasHeaders].
Matcher hasResponse(int statusCode,
    {dynamic body, Map<String, dynamic> headers, bool failIfContainsUnmatchedHeader: false}) {
  return new HTTPResponseMatcher(
      statusCode,
      (headers != null ? new HTTPHeaderMatcher(headers, failIfContainsUnmatchedHeader) : null),
      (body != null ? new HTTPBodyMatcher(body) : null));
}

/// A convenience for [expect] with [hasResponse].
///
/// This method is equivalent to:
///
///         expect(response, hasResponse(statusCode, body, headers: headers));
///
/// The actual response is returned from this method for quick composition:
///
///         final response = expectResponse(
///           await client.request("/foo").get(),
///           200, body: "foo", headers: {"x-foo": "foo"});
///         print("$response");
TestResponse expectResponse(TestResponse response, int statusCode, {dynamic body, Map<String, dynamic> headers}) {
  expect(response, hasResponse(statusCode, body: body, headers: headers));
  return response;
}

/// Validates that a [Request] properties match the given values.
///
/// This matcher is used when matching requests from [MockHTTPServer].
///
/// The actual request's properties will be evaluated
///
///         final server = new MockHTTPServer(4000);
///         await server.open();
///
///         // initiate a request that triggers an HTTP request to port localhost:4000.
///         await client.request("/path").post(...);
///
///         expect(await server.next(), hasRequest(method: "POST", path: "/analytics/event"));
Matcher hasRequest({String method, dynamic path, Map<String, dynamic> query, Map<String, dynamic> headers, dynamic body}) {
  return null;
}

Request expectRequest(Request request, {String method, String path, Map<String, dynamic> query, Map<String, dynamic> headers, dynamic body}) {
  expect(request, hasRequest(method: method, path: path, query: query, headers: headers, body: body));
  return request;
}