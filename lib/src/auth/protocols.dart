import 'dart:async';
import 'package:meta/meta.dart';
import 'auth.dart';

/// An interface for implementing a [AuthServer.ResourceOwner].
///
/// In order for an [AuthServer] to authenticate a [AuthServer.ResourceOwner] - like a User, Profile or Account in your application -
/// that resource owner class must implement this interface. The concrete implementation of this class does not necessarily need to persist the required
/// properties with the same name. For example, it is possible to implement [Authenticatable.username] with an 'email' property:
///
///       class User extends ManagedObject<_User> implements _User, Authenticatable {
///         String get username => email;
///         void set username(String un) { email = un; }
///       }
///       class _User {
///          @managedPrimaryKey String email;
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
  dynamic get uniqueIdentifier;
}

/// An interface for implementing storage behavior for an [AuthServer].
///
/// This interface is responsible for persisting and retrieving information generated and requested by an [AuthServer].
/// The [ResourceOwner] often represents a user or an account in an application and must implement [Authenticatable]. The [TokenType]
/// is a concrete instance of [AuthToken] to represent a resource owner bearer token. The [AuthCodeType] represents an authorization code
/// used in the authorization code grant type.
abstract class AuthStorage {
  /// Returns a [ResourceOwner] for an [username].
  ///
  /// This method returns an instance of [ResourceOwner] if one exists for [username]. Otherwise, it returns null.
  /// [server] is the [AuthServer] requesting the [ResourceOwner].
  Future<Authenticatable> fetchResourceOwnerWithUsername(
      AuthServer server, String username);

  /// Returns an [AuthClient] for a client ID.
  ///
  /// This method returns an instance of [AuthClient] if one exists for [id]. Otherwise, it returns null.
  /// [server] is the [AuthServer] requesting the [AuthClient].
  Future<AuthClient> fetchClientWithID(AuthServer server, String clientID);

  /// Revokes an [AuthClient] for a client ID.
  ///
  /// This method must delete the [clientID]. Subsequent requests to this
  /// instance for [fetchClientWithID] must return null after this method completes.
  /// [server] is the [AuthServer] requesting the [AuthClient].
  Future revokeClientWithID(AuthServer server, String clientID);

  /// Returns a [TokenType] for an [accessToken].
  ///
  /// This method returns an instance of [TokenType] if one exists for [accessToken]. Otherwise, it returns null.
  /// [server] is the [AuthServer] requesting the [TokenType].
  Future<AuthToken> fetchTokenWithAccessToken(AuthServer server, String accessToken);

  /// Returns a [TokenType] for an [refreshToken].
  ///
  /// This method returns an instance of [TokenType] if one exists for [refreshToken]. Otherwise, it returns null.
  /// [server] is the [AuthServer] requesting the [TokenType].
  Future<AuthToken> fetchTokenWithRefreshToken(
      AuthServer server, String refreshToken);

  /// Deletes a [TokenType] for [refreshToken].
  ///
  /// If the [server] wishes to delete an authentication token, it will invoke this method. The implementing class must delete the matching token
  /// from its persistent storage. Note that the token is matched by its [AuthToken.refreshToken], not by its access token.
  /// If the matching [AuthToken] was issued from an [AuthCode], that corresponding [AuthCode] must be deleted as well.
  Future revokeTokenWithAccessToken(AuthServer server, String accessToken);

  /// Asks this instance to store a [TokenType] for [server].
  ///
  /// The implementing class must persist the token [t].
  Future<AuthToken> storeToken(AuthServer server, AuthToken t);

  /// Asks this instance to update an existing [TokenType] for [server].
  ///
  /// The implementing class must persist the token [t].
  Future<AuthToken> updateTokenWithAccessToken(AuthServer server, String accessToken, AuthToken t);

  /// Asks this instance to store a [AuthCodeType] for [server].
  ///
  /// The implementing class must persist the auth code [ac].
  Future<AuthCode> storeAuthCode(AuthServer server, AuthCode ac);

  /// Asks this instance to retrieve an auth code from provided code [code].
  ///
  /// This returns an instance of [AuthCodeType] if one exists for [code], and
  /// null otherwise.
  Future<AuthCode> fetchAuthCodeWithCode(AuthServer server, String code);

  /// Asks this instance to update an existing [AuthCodeType] for [server].
  ///
  /// The implementing class must persist the auth code [ac].
  Future updateAuthCodeWithCode(AuthServer server, String code, AuthCode ac);

  /// Asks this instance to delete an existing [AuthCodeType] for [server].
  ///
  /// The implementing class must delete that auth code from its persistent storage.
  Future revokeAuthCodeWithCode(AuthServer server, String code);
}
