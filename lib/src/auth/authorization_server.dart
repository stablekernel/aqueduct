import 'dart:async';

import '../http/documentable.dart';
import '../utilities/token_generator.dart';
import 'auth.dart';

/// A storage-agnostic OAuth 2.0 authorization 'server'.
///
/// Instances of this type will carry out authentication and authorization tasks. This class shouldn't be subclassed.
///
/// Instances of this type don't store data - like an issued token - but instead, rely on their [storage] property.
/// This property implements the [AuthStorage] interface, which allows the developer to define how information used
/// during authorization is stored and fetched. However, it is rare that you would implement your own storage
/// mechanism and it is better to use the [AuthStorage] implementation included in 'package:aqueduct/managed_auth.dart'.
/// Example:
///
///         import 'package:aqueduct/aqueduct.dart';
///         import 'package:aqueduct/managed_auth.dart';
///
///         var storage = new ManagedAuthStorage<User>();
///         var server = new AuthServer(storage);
///
///         class User extends ManagedObject<_User> implements _User {}
///         class _User extends Authenticatable {}
class AuthServer extends Object with APIDocumentable implements AuthValidator {
  static const String TokenTypeBearer = "bearer";

  /// Creates a new instance of an [AuthServer] with a [storage].
  AuthServer(this.storage);

  /// The object responsible for carrying out the storage mechanisms of this instance.
  ///
  /// This instance is responsible for storing, fetching and deleting instances of
  /// [AuthToken], [AuthCode] and [AuthClient] by implementing the [AuthStorage] interface.
  ///
  /// It is preferable to use the implementation of [AuthStorage] from 'package:aqueduct/managed_auth.dart'. See
  /// [AuthServer] for more details.
  AuthStorage storage;

  Map<String, AuthClient> _clientCache = {};

  /// Returns a [AuthClient] record for its [clientID].
  ///
  /// A server keeps a cache of known [AuthClient]s. If a client does not exist in the cache,
  /// it will ask its [storage] via [AuthStorage.fetchClientByID].
  Future<AuthClient> clientForID(String clientID) async {
    AuthClient client = _clientCache[clientID] ??
        (await storage.fetchClientByID(this, clientID));

    _clientCache[clientID] = client;

    return client;
  }

  /// Revokes a [AuthClient] record.
  ///
  /// Removes cached occurrences of [AuthClient] for [clientID].
  /// Asks [storage] to remove an [AuthClient] by its ID via [AuthStorage.revokeClientWithID].
  Future revokeClientID(String clientID) async {
    if (clientID == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    await storage.revokeClientWithID(this, clientID);

    _clientCache.remove(clientID);
  }

  /// Revokes access for an [Authenticatable].
  ///
  /// This method will ask its [storage] to revoke all tokens and authorization codes
  /// for a specific [Authenticatable] via [AuthStorage.revokeAuthenticatableWithIdentifier].
  Future revokeAuthenticatableAccessForIdentifier(dynamic identifier) async {
    if (identifier == null) {
      return null;
    }

    return storage.revokeAuthenticatableWithIdentifier(this, identifier);
  }

  /// Authenticates a username and password of an [Authenticatable] and returns an [AuthToken] upon success.
  ///
  /// This method works with this instance's [storage] to generate and store a new token if all credentials are correct.
  /// If credentials are not correct, it will throw the appropriate [AuthRequestError].
  ///
  /// After [expiration], this token will no longer be valid.
  Future<AuthToken> authenticate(
      String username, String password, String clientID, String clientSecret,
      {Duration expiration: const Duration(hours: 1)}) async {
    if (clientID == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    AuthClient client = await clientForID(clientID);
    if (client == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    if (username == null || password == null) {
      throw new AuthServerException(AuthRequestError.invalidRequest, client);
    }

    if (client.isPublic) {
      if (!(clientSecret == null || clientSecret == "")) {
        throw new AuthServerException(AuthRequestError.invalidClient, client);
      }
    } else {
      if (clientSecret == null) {
        throw new AuthServerException(AuthRequestError.invalidClient, client);
      }

      if (client.hashedSecret !=
          AuthUtility.generatePasswordHash(clientSecret, client.salt)) {
        throw new AuthServerException(AuthRequestError.invalidClient, client);
      }
    }

    var authenticatable =
        await storage.fetchAuthenticatableByUsername(this, username);
    if (authenticatable == null) {
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    var dbSalt = authenticatable.salt;
    var dbPassword = authenticatable.hashedPassword;
    var hash = AuthUtility.generatePasswordHash(password, dbSalt);
    if (hash != dbPassword) {
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    AuthToken token = _generateToken(
        authenticatable.id, client.id, expiration.inSeconds,
        allowRefresh: !client.isPublic);
    await storage.storeToken(this, token);

    return token;
  }

  /// Returns a [Authorization] for [accessToken].
  ///
  /// This method obtains an [AuthToken] for [accessToken] from [storage] and then verifies that the token is valid.
  /// If the token is valid, an [Authorization] object is returned. Otherwise, an [AuthServerException]
  /// with [AuthRequestError.invalidToken] is thrown.
  Future<Authorization> verify(String accessToken) async {
    if (accessToken == null) {
      throw new AuthServerException(AuthRequestError.invalidToken, null);
    }

    AuthToken t = await storage.fetchTokenByAccessToken(this, accessToken);
    if (t == null || t.isExpired) {
      throw new AuthServerException(AuthRequestError.invalidToken, null);
    }

    return new Authorization(t.clientID, t.resourceOwnerIdentifier, this);
  }

  /// Refreshes a valid [AuthToken] instance.
  ///
  /// This method will refresh a [AuthToken] given the [AuthToken]'s [refreshToken] for a given client ID.
  /// This method coordinates with this instance's [storage] to update the old token with a new access token and issue/expiration dates if successful.
  /// If not successful, it will throw an [AuthRequestError].
  Future<AuthToken> refresh(
      String refreshToken, String clientID, String clientSecret) async {
    if (clientID == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    AuthClient client = await clientForID(clientID);
    if (client == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    if (refreshToken == null) {
      throw new AuthServerException(AuthRequestError.invalidRequest, client);
    }

    var t = await storage.fetchTokenByRefreshToken(this, refreshToken);
    if (t == null || t.clientID != clientID) {
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    if (clientSecret == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, client);
    }

    if (client.hashedSecret !=
        AuthUtility.generatePasswordHash(clientSecret, client.salt)) {
      throw new AuthServerException(AuthRequestError.invalidClient, client);
    }

    var diff = t.expirationDate.difference(t.issueDate);
    var now = new DateTime.now().toUtc();
    var newToken = new AuthToken()
      ..accessToken = randomStringOfLength(32)
      ..issueDate = now
      ..expirationDate = now.add(new Duration(seconds: diff.inSeconds)).toUtc()
      ..refreshToken = t.refreshToken
      ..type = t.type
      ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
      ..clientID = t.clientID;

    await storage.refreshTokenWithAccessToken(this, t.accessToken,
        newToken.accessToken, newToken.issueDate, newToken.expirationDate);

    return newToken;
  }

  /// Creates a one-time use authorization code for a given client ID and user credentials.
  ///
  /// This methods works with this instance's [storage] to generate and store the authorization code
  /// if the credentials are correct. If they are not correct, it will throw the
  /// appropriate [AuthRequestError].
  Future<AuthCode> authenticateForCode(
      String username, String password, String clientID,
      {int expirationInSeconds: 600}) async {
    if (clientID == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    AuthClient client = await clientForID(clientID);
    if (client == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    if (username == null || password == null) {
      throw new AuthServerException(AuthRequestError.invalidRequest, client);
    }

    if (client.redirectURI == null) {
      throw new AuthServerException(
          AuthRequestError.unauthorizedClient, client);
    }

    var authenticatable =
        await storage.fetchAuthenticatableByUsername(this, username);
    if (authenticatable == null) {
      throw new AuthServerException(AuthRequestError.accessDenied, client);
    }

    var dbSalt = authenticatable.salt;
    var dbPassword = authenticatable.hashedPassword;
    var hash = AuthUtility.generatePasswordHash(password, dbSalt);
    if (hash != dbPassword) {
      throw new AuthServerException(AuthRequestError.accessDenied, client);
    }

    AuthCode authCode =
        _generateAuthCode(authenticatable.id, client, expirationInSeconds);
    await storage.storeAuthCode(this, authCode);
    return authCode;
  }

  /// Exchanges a valid authorization code for an [AuthToken].
  ///
  /// If the authorization code has not expired, has not been used, matches the client ID,
  /// and the client secret is correct, it will return a valid [AuthToken]. Otherwise,
  /// it will throw an appropriate [AuthRequestError].
  Future<AuthToken> exchange(
      String authCodeString, String clientID, String clientSecret,
      {int expirationInSeconds: 3600}) async {
    if (clientID == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    AuthClient client = await clientForID(clientID);
    if (client == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, null);
    }

    if (authCodeString == null) {
      throw new AuthServerException(AuthRequestError.invalidRequest, null);
    }

    if (clientSecret == null) {
      throw new AuthServerException(AuthRequestError.invalidClient, client);
    }

    if (client.hashedSecret !=
        AuthUtility.generatePasswordHash(clientSecret, client.salt)) {
      throw new AuthServerException(AuthRequestError.invalidClient, client);
    }

    AuthCode authCode = await storage.fetchAuthCodeByCode(this, authCodeString);
    if (authCode == null) {
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    // check if valid still
    if (authCode.isExpired) {
      await storage.revokeAuthCodeWithCode(this, authCode.code);
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    // check that client ids match
    if (authCode.clientID != client.id) {
      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }

    // check to see if has already been used
    if (authCode.hasBeenExchanged) {
      await storage.revokeTokenIssuedFromCode(this, authCode);

      throw new AuthServerException(AuthRequestError.invalidGrant, client);
    }
    AuthToken token = _generateToken(
        authCode.resourceOwnerIdentifier, client.id, expirationInSeconds);
    await storage.storeToken(this, token, issuedFrom: authCode);

    return token;
  }

  //////
  // APIDocumentable overrides
  //////

  static const String _SecuritySchemeClientAuth = "basic.clientAuth";
  static const String _SecuritySchemePassword = "oauth2.password";
  static const String _SecuritySchemeAuthorizationCode = "oauth2.accessCode";

  @override
  Map<String, APISecurityScheme> documentSecuritySchemes(
      PackagePathResolver resolver) {
    var secPassword =
        new APISecurityScheme.oauth2(APISecuritySchemeFlow.password)
          ..description = "OAuth 2.0 Resource Owner Flow";
    var secAccess =
        new APISecurityScheme.oauth2(APISecuritySchemeFlow.authorizationCode)
          ..description = "OAuth 2.0 Authorization Code Flow";
    var basicAccess = new APISecurityScheme.basic()
      ..description = "Client Authentication";

    return {
      _SecuritySchemeClientAuth: basicAccess,
      _SecuritySchemePassword: secPassword,
      _SecuritySchemeAuthorizationCode: secAccess
    };
  }

  /////
  // AuthValidator overrides
  /////

  @override
  Future<Authorization> fromBasicCredentials(
      AuthBasicCredentials credentials) async {
    var username = credentials.username;
    var password = credentials.password;

    var client = await clientForID(username);

    if (client == null) {
      return null;
    }

    if (client.hashedSecret == null) {
      if (password == "") {
        return new Authorization(client.id, null, this);
      }

      return null;
    }

    if (client.hashedSecret !=
        AuthUtility.generatePasswordHash(password, client.salt)) {
      return null;
    }

    return new Authorization(client.id, null, this, credentials: credentials);
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

  @override
  List<APISecurityRequirement> requirementsForStrategy(AuthStrategy strategy) {
    if (strategy == AuthStrategy.basic) {
      return [new APISecurityRequirement()..name = _SecuritySchemeClientAuth];
    } else if (strategy == AuthStrategy.bearer) {
      return [
        new APISecurityRequirement()..name = _SecuritySchemeAuthorizationCode,
        new APISecurityRequirement()..name = _SecuritySchemePassword
      ];
    }

    return [];
  }

  AuthToken _generateToken(
      dynamic ownerID, String clientID, int expirationInSeconds,
      {bool allowRefresh: true}) {
    var now = new DateTime.now().toUtc();
    AuthToken token = new AuthToken()
      ..accessToken = randomStringOfLength(32)
      ..issueDate = now
      ..expirationDate = now.add(new Duration(seconds: expirationInSeconds))
      ..type = TokenTypeBearer
      ..resourceOwnerIdentifier = ownerID
      ..clientID = clientID;

    if (allowRefresh) {
      token.refreshToken = randomStringOfLength(32);
    }

    return token;
  }

  AuthCode _generateAuthCode(
      dynamic ownerID, AuthClient client, int expirationInSeconds) {
    var now = new DateTime.now().toUtc();
    return new AuthCode()
      ..code = randomStringOfLength(32)
      ..clientID = client.id
      ..resourceOwnerIdentifier = ownerID
      ..issueDate = now
      ..expirationDate = now.add(new Duration(seconds: expirationInSeconds));
  }
}
