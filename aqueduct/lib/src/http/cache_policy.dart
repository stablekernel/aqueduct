import 'http.dart';

/// Instances of this type provide configuration for the 'Cache-Control' header.
///
/// Typically used by [FileController]. See [FileController.addCachePolicy].
class CachePolicy {
  /// Creates a new cache policy.
  ///
  /// Policies applied to [Response.cachePolicy] will add the appropriate
  /// headers to that response. See properties for definitions of arguments
  /// to this constructor.
  const CachePolicy(
      {this.preventIntermediateProxyCaching = false,
      this.preventCaching = false,
      this.requireConditionalRequest = false,
      this.expirationFromNow});

  /// Prevents a response from being cached by an intermediate proxy.
  ///
  /// This sets 'Cache-Control: private' if true. Otherwise, 'Cache-Control: public' is used.
  final bool preventIntermediateProxyCaching;

  /// Prevents any caching of a response by a proxy or client.
  ///
  /// If true, sets 'Cache-Control: no-cache, no-store'. If this property is true,
  /// no other properties are evaluated.
  final bool preventCaching;

  /// Requires a client to send a conditional GET to use a cached response.
  ///
  /// If true, sets 'Cache-Control: no-cache'.
  final bool requireConditionalRequest;

  /// Sets how long a resource is valid for.
  ///
  /// Sets 'Cache-Control: max-age=x', where 'x' is [expirationFromNow] in seconds.
  final Duration expirationFromNow;

  /// Constructs a header value configured from this instance.
  ///
  /// This value is used for the 'Cache-Control' header.
  String get headerValue {
    if (preventCaching) {
      return "no-cache, no-store";
    }

    var items = [];

    if (preventIntermediateProxyCaching) {
      items.add("private");
    } else {
      items.add("public");
    }

    if (expirationFromNow != null) {
      items.add("max-age=${expirationFromNow.inSeconds}");
    }

    if (requireConditionalRequest) {
      items.add("no-cache");
    }

    return items.join(", ");
  }
}
