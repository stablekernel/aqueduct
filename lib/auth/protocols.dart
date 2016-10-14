part of aqueduct;

/// An interface to represent [AuthenticationServer.TokenType].
///
/// In order to use authentication tokens, an [AuthenticationServer] requires
/// that its [AuthenticationServer.TokenType] implement this interface. You will likely use
/// this interface to define a [Model] that represents the concrete implementation of a authentication
/// token in your application. All of these properties are expected to be persisted.
abstract class Tokenizable<ResourceIdentifierType> {
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
  ResourceIdentifierType resourceOwnerIdentifier;

  /// The clientID this token was issued under.
  String clientID;
}

/// An interface for implementing [AuthenticationServer.AuthCodeType].
///
/// In order to use authorization codes, an [AuthenticationServer] requires
/// that its [AuthenticationServer.AuthCodeType] implement this interface. You will likely use
/// this interface to define a [Model] that represents a concrete implementation
/// of a authorization code in your application. All of these properties are expected to be persisted.
abstract class TokenExchangable<TokenType extends Tokenizable> {
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
  TokenType token;
}

/// Authorization information to be attached to a [Request].
///
/// When a [Request] passes through an [Authenticator] and is validated,
/// the [Authenticator] attaches an instance of [Permission] to its [Request.permission].
/// Subsequent [RequestController]s are able to use this information to determine access scope.
class Permission {
  /// Creates an instance of a [Permission].
  Permission(this.clientID, this.resourceOwnerIdentifier, this.grantingServer);

  /// The client ID the permission was granted under.
  final String clientID;

  /// The identifier for the owner of the resource.
  ///
  /// If a [Request] has a Bearer token, this will be the primary key value of the [Model]
  /// for which the Bearer token was associated with. If the [Request] was signed with
  /// a Client ID and secret, this value will be [null].
  final dynamic resourceOwnerIdentifier;

  /// The [AuthenticationServer] that granted this permission.
  final AuthenticationServer grantingServer;
}

/// An interface for implementing a [AuthenticationServer.ResourceOwner].
///
/// In order for an [AuthenticationServer] to authenticate a [AuthenticationServer.ResourceOwner] - like a User, Profile or Account in your application -
/// that resource owner class must implement this interface. The concrete implementation of this class does not necessarily need to persist the required
/// properties with the same name. For example, it is possible to implement [Authenticatable.username] with an 'email' property:
///
///       class User extends Model<_User> implements _User, Authenticatable {
///         String get username => email;
///         void set username(String un) { email = un; }
///       }
///       class _User {
///          @primaryKey String email;
///       }
abstract class Authenticatable {
  /// The username of the authenticatable resource.
  ///
  /// This value is often an email address. The storage of an [Authenticatable] need not define a [username] property,
  /// and so the implementation may simply proxy property to the underlying identifying attribute - like email.
  String username;

  /// The hashed password of this instance.
  String hashedPassword;

  /// The salt the [hashedPassword] was hashed with.
  String salt;

  /// The unique identifier of this instance, typically the primary key of the concrete subclass.
  dynamic id;
}

/// An interface for implementing storage behavior for an [AuthenticationServer].
///
/// This interface is responsible for persisting and retrieving information generated and requested by an [AuthenticationServer].
/// The [ResourceOwner] often represents a user or an account in an application and must implement [Authenticatable]. The [TokenType]
/// is a concrete instance of [Tokenizable] to represent a resource owner bearer token. The [AuthCodeType] represents an authorization code
/// used in the authorization code grant type.
abstract class AuthenticationServerDelegate<ResourceOwner extends Authenticatable, TokenType extends Tokenizable, AuthCodeType extends TokenExchangable<TokenType>> {
  /// Returns a [TokenType] for an [accessToken].
  ///
  /// This method returns an instance of [TokenType] if one exists for [accessToken]. Otherwise, it returns null.
  /// [server] is the [AuthenticationServer] requesting the [TokenType].
  Future<TokenType> tokenForAccessToken(AuthenticationServer server, String accessToken);

  /// Returns a [TokenType] for an [refreshToken].
  ///
  /// This method returns an instance of [TokenType] if one exists for [refreshToken]. Otherwise, it returns null.
  /// [server] is the [AuthenticationServer] requesting the [TokenType].
  Future<TokenType> tokenForRefreshToken(AuthenticationServer server, String refreshToken);

  /// Returns a [ResourceOwner] for an [username].
  ///
  /// This method returns an instance of [ResourceOwner] if one exists for [username]. Otherwise, it returns null.
  /// [server] is the [AuthenticationServer] requesting the [ResourceOwner].
  Future<ResourceOwner> authenticatableForUsername(AuthenticationServer server, String username);

  /// Returns a [ResourceOwner] for an [username].
  ///
  /// This method returns an instance of [ResourceOwner] if one exists for [id]. Otherwise, it returns null.
  /// [server] is the [AuthenticationServer] requesting the [ResourceOwner].
  Future<ResourceOwner> authenticatableForID(AuthenticationServer server, dynamic id);

  /// Returns a [Client] for a client id.
  ///
  /// This method returns an instance of [Client] if one exists for [id]. Otherwise, it returns null.
  /// [server] is the [AuthenticationServer] requesting the [Client].
  Future<Client> clientForID(AuthenticationServer server, String id);

  /// Deletes a [TokenType] for [refreshToken].
  ///
  /// If the [server] wishes to delete an authentication token, it will invoke this method. The implementing class must delete the matching token
  /// from its persistent storage. Note that the token is matched by its [Tokenizable.refreshToken], not by its access token.
  /// If the matching [Tokenizable] was issued from an [TokenExchangable], that corresponding [TokenExchangable] must be deleted as well.
  Future deleteTokenForRefreshToken(AuthenticationServer server, String refreshToken);

  /// Asks this instance to store a [TokenType] for [server].
  ///
  /// The implementing class must persist the token [t].
  Future<TokenType> storeToken(AuthenticationServer server, TokenType t);

  /// Asks this instance to update an existing [TokenType] for [server].
  ///
  /// The implementing class must persist the token [t].
  Future updateToken(AuthenticationServer server, TokenType t);

  /// Asks this instance to store a [AuthCodeType] for [server].
  ///
  /// The implementing class must persist the auth code [ac].
  Future<AuthCodeType> storeAuthCode(AuthenticationServer server, AuthCodeType ac);

  /// Asks this instance to retrieve an auth code from provided code [code].
  ///
  /// This returns an instance of [AuthCodeType] if one exists for [code], and
  /// null otherwise.
  Future<AuthCodeType> authCodeForCode(AuthenticationServer server, String code);

  /// Asks this instance to update an existing [AuthCodeType] for [server].
  ///
  /// The implementing class must persist the auth code [ac].
  Future updateAuthCode(AuthenticationServer server, AuthCodeType ac);

  /// Asks this instance to delete an existing [AuthCodeType] for [server].
  ///
  /// The implementing class must delete that auth code from its persistent storage.
  Future deleteAuthCode(AuthenticationServer server, AuthCodeType ac);
}
