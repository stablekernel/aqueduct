import 'auth.dart';

/// Represents a Client ID and secret pair.
class AuthClient {
  /// Creates an instance of [AuthClient].
  AuthClient(this.id, this.hashedSecret, this.salt);

  // Creates an instance of [Client] that uses the authorization code grant flow.
  AuthClient.withRedirectURI(
      this.id, this.hashedSecret, this.salt, this.redirectURI);

  /// The ID of the client.
  String id;

  /// The hashed secret of the client.
  String hashedSecret;

  /// The salt the hashed secret was hashed with.
  String salt;

  /// The redirection URI for authorization codes and/or tokens.
  String redirectURI;

  String toString() {
    return "AuthClient $id ${hashedSecret == null ? "public" : "confidental"} $redirectURI";
  }
}


/// An interface to represent [AuthServer.TokenType].
///
/// In order to use authentication tokens, an [AuthServer] requires
/// that its [AuthServer.TokenType] implement this interface. You will likely use
/// this interface to define a [ManagedObject] that represents the concrete implementation of a authentication
/// token in your application. All of these properties are expected to be persisted.
class AuthToken {
  /// The value to be passed as a Bearer Authorization header.
  String accessToken;

  /// The value to be passed for refreshing an expired (or not yet expired) token.
  String refreshToken;

  /// The timestamp this token was issued on.
  DateTime issueDate;

  /// When this token expires.
  DateTime expirationDate;

  /// The type of token, currently only 'bearer' is valid.
  String type;

  /// The identifier of the resource owner.
  ///
  /// Tokens are owned by a resource owner, typically a User, Profile or Account
  /// in an application. This value is the primary key or identifying value of those
  /// instances.
  dynamic resourceOwnerIdentifier;

  /// The clientID this token was issued under.
  String clientID;

  bool get isExpired {
    return expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }
}

/// An interface for implementing [AuthServer.AuthCodeType].
///
/// In order to use authorization codes, an [AuthServer] requires
/// that its [AuthServer.AuthCodeType] implement this interface. You will likely use
/// this interface to define a [ManagedObject] that represents a concrete implementation
/// of a authorization code in your application. All of these properties are expected to be persisted.
class AuthCode {
  /// This is the URI that the response object will redirect to with the
  /// authorization code in the query.
  String redirectURI;

  /// The actual one-time code used to exchange for tokens.
  String code;

  /// The clientID the authorization code was issued under.
  String clientID;

  /// The identifier of the resource owner.
  ///
  /// Authorization codes are owned by a resource owner, typically a User, Profile or Account
  /// in an application. This value is the primary key or identifying value of those
  /// instances.
  dynamic resourceOwnerIdentifier;

  /// The timestamp this authorization code was issued on.
  DateTime issueDate;

  /// When this authorization code expires, recommended for 10 minutes after issue date.
  DateTime expirationDate;

  /// The token vended for this authorization code
  AuthToken token;

  bool get isExpired {
    return expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }
}

/// Authorization information to be attached to a [Request].
///
/// When a [Request] passes through an [Authorizer] and is validated,
/// the [Authorizer] attaches an instance of [Authorization] to its [Request.authorization].
/// Subsequent [RequestController]s are able to use this information to determine access scope.
class Authorization {
  /// Creates an instance of a [Authorization].
  Authorization(
      this.clientID, this.resourceOwnerIdentifier, this.validator);

  /// The client ID the permission was granted under.
  final String clientID;

  /// The identifier for the owner of the resource.
  ///
  /// If a [Request] has a Bearer token, this will be the primary key value of the [ManagedObject]
  /// for which the Bearer token was associated with. If the [Request] was signed with
  /// a Client ID and secret, this value will be [null].
  final dynamic resourceOwnerIdentifier;

  /// The [AuthValidator] that granted this permission.
  final AuthValidator validator;
}