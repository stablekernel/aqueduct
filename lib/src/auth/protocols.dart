import 'dart:async';
import 'auth.dart';

/// An interface for implementing an OAuth 2.0 resource owner.
///
/// In order for an [AuthServer] to authenticate a resource owner - like a User, Profile or Account in your application -
/// that resource owner class must implement this interface. See the library aqueduct/managed_auth for an implementation
/// of this interface. It is preferred to use aqueduct/managed_auth than trying to implement this interface.
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

  /// The unique identifier of this instance, typically the primary key of a database entity representing
  /// the authenticatable instance.
  dynamic get id;
}

/// An interface for implementing storage behavior for an [AuthServer].
///
/// This interface is responsible for persisting and retrieving information generated and requested by an [AuthServer].
/// For a concrete, tested implementation of this class, see `ManagedAuthStorage` in `package:aqueduct/managed_auth.dart`.
///
/// An [AuthServer] does not dictate how information is stored and therefore can't dictate how information is disposed of.
/// It is up to implementors of this class to discard of any information it no longer wants to keep.
abstract class AuthStorage {
  /// This method must revoke all [AuthToken] and [AuthCode]s for an [Authenticatable].
  ///
  /// [server] is the requesting [AuthServer]. [identifier] is the [Authenticatable.id].
  Future revokeAuthenticatableWithIdentifier(
      AuthServer server, dynamic identifier);

  /// Returns an [Authenticatable] for an [username].
  ///
  /// This method must return an instance of [Authenticatable] if one exists for [username]. Otherwise, it must return null.
  ///
  /// If overriding this method, every property declared by [Authenticatable] must be non-null in the return value.
  ///
  /// [server] is the [AuthServer] invoking this method.
  Future<Authenticatable> fetchAuthenticatableByUsername(
      AuthServer server, String username);

  /// Returns an [AuthClient] for a client ID.
  ///
  /// This method must return an instance of [AuthClient] if one exists for [clientID]. Otherwise, it must return null.
  /// [server] is the [AuthServer] requesting the [AuthClient].
  Future<AuthClient> fetchClientByID(AuthServer server, String clientID);

  /// Revokes an [AuthClient] for a client ID.
  ///
  /// This method must delete the [AuthClient] for [clientID]. Subsequent requests to this
  /// instance for [fetchClientByID] must return null after this method completes.
  /// [server] is the [AuthServer] requesting the [AuthClient].
  Future revokeClientWithID(AuthServer server, String clientID);

  /// Returns a [AuthToken] for an [accessToken].
  ///
  /// This method must return an instance of [AuthToken] if one exists for [accessToken]. Otherwise, it must return null.
  /// [server] is the [AuthServer] requesting the [AuthToken].
  Future<AuthToken> fetchTokenByAccessToken(
      AuthServer server, String accessToken);

  /// Returns a [AuthToken] for an [refreshToken].
  ///
  /// This method must return an instance of [AuthToken] if one exists for [refreshToken]. Otherwise, it must return null.
  /// [server] is the [AuthServer] requesting the [AuthToken].
  Future<AuthToken> fetchTokenByRefreshToken(
      AuthServer server, String refreshToken);

  /// Deletes a [AuthToken] by its issuing [AuthCode].
  ///
  /// The [server] will call this method when a request tries to exchange an already exchanged [AuthCode].
  /// This method must delete the [AuthToken] that was previously acquired by exchanging [authCode] - this means
  /// that the storage performed by this type must track the issuing [AuthCode] for an [AuthToken] if there was one.
  /// Any storage for [authCode] can also be removed as well.
  Future revokeTokenIssuedFromCode(AuthServer server, AuthCode authCode);

  /// Asks this instance to store a [AuthToken] for [server].
  ///
  /// This method must persist the token [t]. If [issuedFrom] is not null, it must associate
  /// the [issuedFrom] [AuthCode] with [t] in storage, such that [t] can be found again
  /// by [issuedFrom]'s [AuthCode.code], even if [t] has been refreshed later.
  Future storeToken(AuthServer server, AuthToken t, {AuthCode issuedFrom});

  /// Asks this instance to update an existing [AuthToken] for [server].
  ///
  /// This method must must update an existing [AuthToken], found by [oldAccessToken],
  /// with the values [newAccessToken], [newIssueDate] and [newExpirationDate].
  Future refreshTokenWithAccessToken(AuthServer server, String oldAccessToken,
      String newAccessToken, DateTime newIssueDate, DateTime newExpirationDate);

  /// Asks this instance to store a [AuthCode] for [server].
  ///
  /// The implementing class must persist the auth code [ac].
  Future storeAuthCode(AuthServer server, AuthCode ac);

  /// Asks this instance to retrieve an auth code from provided [code].
  ///
  /// This must return an instance of [AuthCode] if one exists for [code], and
  /// null otherwise.
  Future<AuthCode> fetchAuthCodeByCode(AuthServer server, String code);

  /// Asks this instance to delete an existing [AuthCode] for [server].
  ///
  /// The implementing class must delete the [AuthCode] for [code] from its persistent storage.
  Future revokeAuthCodeWithCode(AuthServer server, String code);

  /// Returns list of allowed scopes for a given [Authenticatable].
  ///
  /// Subclasses override this method to return a list of [AuthScope]s based on some attribute(s) of an [Authenticatable].
  /// That [Authenticatable] is then restricted to only those scopes, even if the authenticating client would allow other scopes
  /// or scopes with higher privileges.
  ///
  /// By default, this method returns [AuthScope.Any] - any [Authenticatable] being authenticated has full access to the scopes
  /// available to the authenticating client.
  ///
  /// When overriding this method, it is important to note that (by default) only the properties declared by [Authenticatable]
  /// will be valid for [authenticatable]. If [authenticatable] has properties that are application-specific (like a `role`),
  /// [fetchAuthenticatableByUsername] must also be overridden to ensure those values are fetched.
  List<AuthScope> allowedScopesForAuthenticatable(Authenticatable authenticatable) => AuthScope.Any;
}
