import 'auth.dart';

/// An exception thrown by [AuthServer].
class AuthServerException implements Exception {
  AuthServerException(this.reason, this.client);

  /// Returns a string suitable to be included in a query string or JSON response body
  /// to indicate the error during processing an OAuth 2.0 request.
  static String errorString(AuthRequestError error) {
    switch (error) {
      case AuthRequestError.invalidRequest:
        return "invalid_request";
      case AuthRequestError.invalidClient:
        return "invalid_client";
      case AuthRequestError.invalidGrant:
        return "invalid_grant";
      case AuthRequestError.invalidScope:
        return "invalid_scope";
      case AuthRequestError.invalidToken:
        return "invalid_token";

      case AuthRequestError.unsupportedGrantType:
        return "unsupported_grant_type";
      case AuthRequestError.unsupportedResponseType:
        return "unsupported_response_type";

      case AuthRequestError.unauthorizedClient:
        return "unauthorized_client";
      case AuthRequestError.accessDenied:
        return "access_denied";

      case AuthRequestError.serverError:
        return "server_error";
      case AuthRequestError.temporarilyUnavailable:
        return "temporarily_unavailable";
    }
    return null;
  }

  AuthRequestError reason;
  AuthClient client;

  String get reasonString {
    return errorString(reason);
  }

  @override
  String toString() {
    return "AuthServerException: $reason $client";
  }
}

/// The possible errors as defined by the OAuth 2.0 specification.
///
/// Auth endpoints will use this list of values to determine the response sent back
/// to a client upon a failed request.
enum AuthRequestError {
  /// The request was invalid...
  ///
  /// The request is missing a required parameter, includes an
  /// unsupported parameter value (other than grant type),
  /// repeats a parameter, includes multiple credentials,
  /// utilizes more than one mechanism for authenticating the
  /// client, or is otherwise malformed.
  invalidRequest,

  /// The client was invalid...
  ///
  /// Client authentication failed (e.g., unknown client, no
  /// client authentication included, or unsupported
  /// authentication method).  The authorization server MAY
  /// return an HTTP 401 (Unauthorized) status code to indicate
  /// which HTTP authentication schemes are supported.  If the
  /// client attempted to authenticate via the "Authorization"
  /// request header field, the authorization server MUST
  /// respond with an HTTP 401 (Unauthorized) status code and
  /// include the "WWW-Authenticate" response header field
  /// matching the authentication scheme used by the client.
  invalidClient,

  /// The grant was invalid...
  ///
  /// The provided authorization grant (e.g., authorization
  /// code, resource owner credentials) or refresh token is
  /// invalid, expired, revoked, does not match the redirection
  /// URI used in the authorization request, or was issued to
  /// another client.
  invalidGrant,

  /// The requested scope is invalid, unknown, malformed, or exceeds the scope granted by the resource owner.
  ///
  invalidScope,

  /// The authorization grant type is not supported by the authorization server.
  ///
  unsupportedGrantType,

  /// The authorization server does not support obtaining an authorization code using this method.
  ///
  unsupportedResponseType,

  /// The authenticated client is not authorized to use this authorization grant type.
  ///
  unauthorizedClient,

  /// The resource owner or authorization server denied the request.
  ///
  accessDenied,

  /// The server encountered an error during processing the request.
  ///
  serverError,

  /// The server is temporarily unable to fulfill the request.
  ///
  temporarilyUnavailable,

  /// Indicates that the token is invalid.
  ///
  /// This particular error reason is not part of the OAuth 2.0 spec.
  invalidToken
}
