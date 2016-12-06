import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:mirrors';

import 'package:crypto/crypto.dart';

import '../http/http.dart';
import '../utilities/pbkdf2.dart';
import '../utilities/token_generator.dart';
import 'auth.dart';

/// A storage-agnostic authorization 'server'.
///
/// Instances of this type will carry out authentication and authorization tasks. This class shouldn't be subclassed. The storage required by tasks performed
/// by instances of this class - such as storing an issued token - are facilitated through its [delegate], which is application-specific.
class AuthServer<
        ResourceOwner extends Authenticatable,
        TokenType extends AuthTokenizable,
        AuthCodeType extends AuthTokenExchangable<TokenType>> extends Object
    with APIDocumentable
    implements AuthValidator {
  /// A utility method to generate a password hash using the PBKDF2 scheme.
  ///
  static String generatePasswordHash(String password, String salt,
      {int hashRounds: 1000, int hashLength: 32}) {
    var generator = new PBKDF2(hashAlgorithm: sha256);
    var key = generator.generateKey(password, salt, hashRounds, hashLength);

    return new Base64Encoder().convert(key);
  }

  /// A utility method to generate a random base64 salt.
  ///
  static String generateRandomSalt({int hashLength: 32}) {
    var random = new Random.secure();
    List<int> salt = [];
    for (var i = 0; i < hashLength; i++) {
      salt.add(random.nextInt(256));
    }

    return new Base64Encoder().convert(salt);
  }

  /// A utility method to generate a ClientID and Client Secret Pair, where secret is hashed with a salt.
  ///
  /// Secret may be null for public clients.
  static AuthClient generateAPICredentialPair(String clientID, String secret,
      {String redirectURI: null}) {
    if (secret == null) {
      return new AuthClient.withRedirectURI(clientID, null, null, redirectURI);
    }

    var salt = AuthServer.generateRandomSalt();
    var hashed = AuthServer.generatePasswordHash(secret, salt);

    return new AuthClient.withRedirectURI(clientID, hashed, salt, redirectURI);
  }

  /// Creates a new instance of an [AuthServer] with a [delegate].
  AuthServer(this.delegate);

  /// The object responsible for carrying out the storage mechanisms of this instance.
  ///
  /// This instance is responsible for storing, fetching and deleting instances of
  /// [TokenType], [ResourceOwner] and [AuthCodeType] by implementing the [AuthServerDelegate] interface.
  AuthServerDelegate<ResourceOwner, TokenType, AuthCodeType> delegate;
  Map<String, AuthClient> _clientCache = {};

  /// Returns whether or not a token from this server has expired.
  ///
  /// Checks the expiration date of a token.
  bool isTokenExpired(TokenType t) {
    return t.expirationDate.difference(new DateTime.now().toUtc()).inSeconds <=
        0;
  }

  /// Returns whether or not an authorization code from this server has expired.
  ///
  ///
  bool isAuthCodeExpired(AuthCodeType ac) {
    return ac.expirationDate.difference(new DateTime.now().toUtc()).inSeconds <=
        0;
  }

  /// Returns a [AuthClient] record for its [id].
  ///
  /// A server keeps a cache of known [AuthClient]s. If a client does not exist in the cache,
  /// it will ask its [delegate] via [clientForID].
  Future<AuthClient> clientForID(String id) async {
    AuthClient client =
        _clientCache[id] ?? (await delegate.clientForID(this, id));

    _clientCache[id] = client;

    return client;
  }

  /// Revokes a [AuthClient] record.
  ///
  /// NYI. Currently, just removes a [AuthClient] from the cache.
  void revokeClient(String clientID) {
    _clientCache.remove(clientID);

    // TODO: Call delegate method to revoke client from persistent storage.
  }

  /// Returns a [Authorization] for [accessToken].
  ///
  /// This method obtains a [TokenType] from its [delegate] and then verifies that the token is valid.
  /// If the token is valid, a [Authorization] object is returned. Otherwise, an [AuthServerException]
  /// with [AuthRequestError.invalidToken].
  Future<Authorization> verify(String accessToken) async {
    TokenType t = await delegate.tokenForAccessToken(this, accessToken);
    if (t == null || isTokenExpired(t)) {
      throw new AuthServerException(AuthRequestError.invalidToken, null);
    }

    return new Authorization(t.clientID, t.resourceOwnerIdentifier, this);
  }

  /// Returns a [Authorization] for the specified [code].
  ///
  /// This method obtains a [AuthCodeType] from its [delegate] and then verifies
  /// that the authorization code is valid. If the token is valid, a [Authorization]
  /// object is returned. Otherwise, an [AuthServerException] is thrown.
  Future<Authorization> verifyCode(String code) async {
    AuthCodeType ac = await delegate.authCodeForCode(this, code);
    if (ac == null || isAuthCodeExpired(ac)) {
      throw new AuthServerException(AuthRequestError.invalidGrant, null);
    }

    return new Authorization(ac.clientID, ac.resourceOwnerIdentifier, this);
  }

  /// Refreshes a valid [TokenType] instance.
  ///
  /// This method will refresh a [TokenType] given the [TokenType]'s [refreshToken] for a given client ID.
  /// This method coordinates with this instance's [delegate] to update the old token with a new access token and issue/expiration dates if successful.
  /// If not successful, it will throw an [AuthRequestError].
  Future<TokenType> refresh(
      String refreshToken, String clientID, String clientSecret) async {

    AuthClient client = await clientForID(clientID);
    if (client == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    if (refreshToken == null) {
      throw new AuthServerException(AuthRequestError.invalidRequest, client);
    }

    var t = await delegate.tokenForRefreshToken(this, refreshToken);
    if (t == null || t.clientID != clientID) {
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    if (client.hashedSecret !=
        generatePasswordHash(clientSecret, client.salt)) {
      throw new AuthServerException(AuthRequestError.invalidClient, client);
    }

    var diff = t.expirationDate.difference(t.issueDate);
    t.accessToken = randomStringOfLength(32);
    t.issueDate = new DateTime.now().toUtc();
    t.expirationDate =
        t.issueDate.add(new Duration(seconds: diff.inSeconds)).toUtc();

    return delegate.updateToken(this, t);
  }

  /// Authenticates a [ResourceOwner] for a given client ID.
  ///
  /// This method works with this instance's [delegate] to generate and store a new token if all credentials are correct.
  /// If credentials are not correct, it will throw the appropriate [AuthRequestError].
  ///
  /// [expirationInSeconds] is measured in seconds and defaults to one hour.
  Future<TokenType> authenticate(
      String username, String password, String clientID, String clientSecret,
      {int expirationInSeconds: 3600}) async {
    AuthClient client = await clientForID(clientID);
    if (client == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    if (username == null || password == null) {
      throw new AuthServerException(AuthRequestError.invalidRequest, client);
    }

    var isClientPublic = false;
    if (client.hashedSecret == null) {
      isClientPublic = true;

      if (!(clientSecret == null || clientSecret == "")) {
        throw new AuthServerException(AuthRequestError.invalidClient, client);
      }
    } else {
      isClientPublic = false;

      if (client.hashedSecret !=
          generatePasswordHash(clientSecret, client.salt)) {
        throw new AuthServerException(AuthRequestError.invalidClient, client);
      }
    }

    var authenticatable =
        await delegate.authenticatableForUsername(this, username);
    if (authenticatable == null) {
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    var dbSalt = authenticatable.salt;
    var dbPassword = authenticatable.hashedPassword;
    var hash = AuthServer.generatePasswordHash(password, dbSalt);
    if (hash != dbPassword) {
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    TokenType token = _generateToken(
        authenticatable.id, client.id, expirationInSeconds,
        allowRefresh: !isClientPublic);
    await delegate.storeToken(this, token);

    return token;
  }

  /// Creates a one-time use authorization code for a given client ID and user credentials.
  ///
  /// This methods works with this instance's [delegate] to generate and store the authorization code
  /// if the credentials are correct. If they are not correct, it will throw the
  /// appropriate [AuthRequestError].
  Future<AuthCodeType> createAuthCode(
      String username, String password, String clientID,
      {int expirationInSeconds: 600}) async {
    AuthClient client = await clientForID(clientID);
    if (client == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    if (username == null || password == null) {
      throw new AuthServerException(AuthRequestError.invalidRequest, client);
    }

    if (client.redirectURI == null) {
      throw new AuthServerException(AuthRequestError.unauthorizedClient, client);
    }

    var authenticatable =
        await delegate.authenticatableForUsername(this, username);
    if (authenticatable == null) {
      throw new AuthServerException(AuthRequestError.accessDenied, client);
    }

    var dbSalt = authenticatable.salt;
    var dbPassword = authenticatable.hashedPassword;
    var hash = AuthServer.generatePasswordHash(password, dbSalt);
    if (hash != dbPassword) {
      throw new AuthServerException(AuthRequestError.accessDenied, client);
    }

    AuthCodeType authCode =
        _generateAuthCode(authenticatable.id, client, expirationInSeconds);
    return await delegate.storeAuthCode(this, authCode);
  }

  /// Exchanges a valid authorization code for a pair of refresh and access tokens.
  ///
  /// If the authorization code has not expired, has not been used, matches the client ID,
  /// and the client secret is correct, it will return a valid pair of tokens. Otherwise,
  /// it will throw an appropriate [AuthRequestError].
  Future<TokenType> exchange(
      String authCodeString, String clientID, String clientSecret,
      {int expirationInSeconds: 3600}) async {
    AuthClient client = await clientForID(clientID);
    if (client == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    if (authCodeString == null) {
      throw new AuthServerException(AuthRequestError.invalidRequest, null);
    }

    if (client.hashedSecret !=
        generatePasswordHash(clientSecret, client.salt)) {
      throw new AuthServerException(AuthRequestError.invalidClient, client);
    }

    AuthCodeType authCode =
        await delegate.authCodeForCode(this, authCodeString);
    if (authCode == null) {
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    // check if valid still
    if (authCode.expirationDate.difference(new DateTime.now()).inSeconds <= 0) {
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    // check that client ids match
    if (authCode.clientID != client.id) {
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    // check to see if has already been used
    if (authCode.token != null) {
      await delegate.deleteTokenForRefreshToken(
          this, authCode.token.refreshToken);

      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    TokenType token = _generateToken(
        authCode.resourceOwnerIdentifier, client.id, expirationInSeconds);
    token = await delegate.storeToken(this, token);

    authCode.token = token;
    await delegate.updateAuthCode(this, authCode);

    return token;
  }

  // APIDocumentable overrides

  @override
  Map<String, APISecurityScheme> documentSecuritySchemes(
      PackagePathResolver resolver) {
    var secApp = new APISecurityScheme.oauth2()
      ..description = "OAuth 2.0 Application Flow"
      ..oauthFlow = APISecuritySchemeFlow.application;
    var secPassword = new APISecurityScheme.oauth2()
      ..description = "OAuth 2.0 Resource Owner Flow"
      ..oauthFlow = APISecuritySchemeFlow.password;
    var secAccess = new APISecurityScheme.oauth2()
      ..description = "OAuth 2.0 Access Code Flow"
      ..oauthFlow = APISecuritySchemeFlow.accessCode;

    return {
      "oauth2.application": secApp,
      "oauth2.password": secPassword,
      "oauth2.accessCode": secAccess
    };
  }

  // AuthValidator overrides

  @override
  Future<Authorization> fromBasicCredentials(
      String username, String password) async {
    var client = await clientForID(username);

    if (client == null) {
      return null;
    }

    if (client.hashedSecret !=
        AuthServer.generatePasswordHash(password, client.salt)) {
      return null;
    }

    return new Authorization(client.id, null, this);
  }

  @override
  Future<Authorization> fromBearerToken(
      String bearerToken, List<String> scopesRequired) async {
    try {
      return await verify(bearerToken);
    } on AuthServerException {
      return null;
    }
  }

  TokenType _generateToken(
      dynamic ownerID, String clientID, int expirationInSeconds,
      {bool allowRefresh: true}) {
    TokenType token = (reflectType(TokenType) as ClassMirror)
        .newInstance(new Symbol(""), []).reflectee as TokenType;
    token.accessToken = randomStringOfLength(32);
    token.issueDate = new DateTime.now().toUtc();
    token.expirationDate =
        token.issueDate.add(new Duration(seconds: expirationInSeconds)).toUtc();
    token.type = "bearer";
    token.resourceOwnerIdentifier = ownerID;
    token.clientID = clientID;

    if (allowRefresh) {
      token.refreshToken = randomStringOfLength(32);
    }

    return token;
  }

  AuthCodeType _generateAuthCode(
      dynamic ownerID, AuthClient client, int expirationInSeconds) {
    AuthCodeType authCode = (reflectType(AuthCodeType) as ClassMirror)
        .newInstance(new Symbol(""), []).reflectee as AuthCodeType;

    authCode.code = randomStringOfLength(32);
    authCode.clientID = client.id;
    authCode.resourceOwnerIdentifier = ownerID;
    authCode.issueDate = new DateTime.now().toUtc();
    authCode.expirationDate = authCode.issueDate
        .add(new Duration(seconds: expirationInSeconds))
        .toUtc();
    authCode.redirectURI = client.redirectURI;

    return authCode;
  }
}

class AuthServerException implements Exception {
  static Response responseForError(AuthRequestError error) {
    return new Response.badRequest(body: {"error" : errorStringFromRequestError(error)});
  }

  /// Returns a string suitable to be included in a query string or JSON response body
  /// to indicate the error during processing an OAuth 2.0 request.
  static String errorStringFromRequestError(AuthRequestError error) {
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

  AuthServerException(this.reason, this.client);

  AuthRequestError reason;
  AuthClient client;

  Response get directResponse {
    return responseForError(reason);
  }

  Response get redirectResponse {
    if (client?.redirectURI == null) {
      return directResponse;
    }

    var redirectURI = Uri.parse(client.redirectURI);
    Map<String, String> queryParameters = new Map.from(redirectURI.queryParameters);

    queryParameters["error"] = errorStringFromRequestError(reason);

    var responseURI = new Uri(
        scheme: redirectURI.scheme,
        userInfo: redirectURI.userInfo,
        host: redirectURI.host,
        port: redirectURI.port,
        path: redirectURI.path,
        queryParameters: queryParameters);

    return new Response(
        HttpStatus.MOVED_TEMPORARILY,
        {
          HttpHeaders.LOCATION: responseURI.toString(),
          HttpHeaders.CACHE_CONTROL: "no-store",
          HttpHeaders.PRAGMA: "no-cache"
        },
        null);
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
