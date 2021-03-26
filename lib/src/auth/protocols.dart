import 'dart:async';
import 'auth.dart';

/// The properties of an OAuth 2.0 Resource Owner.
///
/// Your application's 'user' type must implement the methods declared in this interface. [AuthServer] can
/// validate the credentials of a [ResourceOwner] to grant authorization codes and access tokens on behalf of that
/// owner.
abstract class ResourceOwner {
  /// The username of the resource owner.
  ///
  /// This value must be unique amongst all resource owners. It is often an email address. This value
  /// is used by authenticating users to identify their account.
  String username;

  /// The hashed password of this instance.
  String hashedPassword;

  /// The salt the [hashedPassword] was hashed with.
  String salt;

  /// A unique identifier of this resource owner.
  ///
  /// This unique identifier is used by [AuthServer] to associate authorization codes and access tokens with
  /// this resource owner.
  int get id;
}

/// The methods used by an [AuthServer] to store information and customize behavior related to authorization.
///
/// An [AuthServer] requires an instance of this type to manage storage of [ResourceOwner]s, [AuthToken], [AuthCode],
/// and [AuthClient]s. You may also customize the token format or add more granular authorization scope rules.
///
/// Prefer to use `ManagedAuthDelegate` from 'package:aqueduct/managed_auth.dart' instead of implementing this interface;
/// there are important details to consider and test when implementing this interface.
abstract class AuthServerDelegate {
  /// Must return a [ResourceOwner] for a [username].
  ///
  /// This method must return an instance of [ResourceOwner] if one exists for [username]. Otherwise, it must return null.
  ///
  /// Every property declared by [ResourceOwner] must be non-null in the return value.
  ///
  /// [server] is the [AuthServer] invoking this method.
  FutureOr<ResourceOwner> getResourceOwner(AuthServer server, String username);

  /// Must store [client].
  ///
  /// [client] must be returned by [getClient] after this method has been invoked, and until (if ever)
  /// [removeClient] is invoked.
  FutureOr addClient(AuthServer server, AuthClient client);

  /// Must return [AuthClient] for a client ID.
  ///
  /// This method must return an instance of [AuthClient] if one exists for [clientID]. Otherwise, it must return null.
  /// [server] is the [AuthServer] requesting the [AuthClient].
  FutureOr<AuthClient> getClient(AuthServer server, String clientID);

  /// Removes an [AuthClient] for a client ID.
  ///
  /// This method must delete the [AuthClient] for [clientID]. Subsequent requests to this
  /// instance for [getClient] must return null after this method completes. If there is no
  /// matching [clientID], this method may choose whether to throw an exception or fail silently.
  ///
  /// [server] is the [AuthServer] requesting the [AuthClient].
  FutureOr removeClient(AuthServer server, String clientID);

  /// Returns a [AuthToken] searching by its access token or refresh token.
  ///
  /// Exactly one of [byAccessToken] and [byRefreshToken] may be non-null, if not, this method must throw an error.
  ///
  /// If [byAccessToken] is not-null and there exists a matching [AuthToken.accessToken], return that token.
  /// If [byRefreshToken] is not-null and there exists a matching [AuthToken.refreshToken], return that token.
  ///
  /// If no match is found, return null.
  ///
  /// [server] is the [AuthServer] requesting the [AuthToken].
  FutureOr<AuthToken> getToken(AuthServer server,
      {String byAccessToken, String byRefreshToken});

  /// This method must delete all [AuthToken] and [AuthCode]s for a [ResourceOwner].
  ///
  /// [server] is the requesting [AuthServer]. [resourceOwnerID] is the [ResourceOwner.id].
  FutureOr removeTokens(AuthServer server, int resourceOwnerID);

  /// Must delete a [AuthToken] granted by [grantedByCode].
  ///
  /// If an [AuthToken] has been granted by exchanging [AuthCode], that token must be revoked
  /// and can no longer be used to authorize access to a resource. [grantedByCode] should
  /// also be removed.
  ///
  /// This method is invoked when attempting to exchange an authorization code that has already granted a token.
  FutureOr removeToken(AuthServer server, AuthCode grantedByCode);

  /// Must store [token].
  ///
  /// [token] must be stored such that it is accessible from [getToken], and until it is either
  /// revoked via [removeToken] or [removeTokens], or until it has expired and can reasonably
  /// be believed to no longer be in use.
  ///
  /// You may alter [token] prior to storing it. This may include replacing [AuthToken.accessToken] with another token
  /// format. The default token format will be a random 32 character string.
  ///
  /// If this token was granted through an authorization code, [issuedFrom] is that code. Otherwise, [issuedFrom]
  /// is null.
  FutureOr addToken(AuthServer server, AuthToken token, {AuthCode issuedFrom});

  /// Must update [AuthToken] with [newAccessToken, [newIssueDate, [newExpirationDate].
  ///
  /// This method must must update an existing [AuthToken], found by [oldAccessToken],
  /// with the values [newAccessToken], [newIssueDate] and [newExpirationDate].
  ///
  /// You may alter the token in addition to the provided values, and you may override the provided values.
  /// [newAccessToken] defaults to a random 32 character string.
  FutureOr updateToken(AuthServer server, String oldAccessToken,
      String newAccessToken, DateTime newIssueDate, DateTime newExpirationDate);

  /// Must store [code].
  ///
  /// [code] must be accessible until its expiration date.
  FutureOr addCode(AuthServer server, AuthCode code);

  /// Must return [AuthCode] for its identifiying [code].
  ///
  /// This must return an instance of [AuthCode] where [AuthCode.code] matches [code].
  /// Return null if no matching code.
  FutureOr<AuthCode> getCode(AuthServer server, String code);

  /// Must remove [AuthCode] identified by [code].
  ///
  /// The [AuthCode.code] matching [code] must be deleted and no longer accessible.
  FutureOr removeCode(AuthServer server, String code);

  /// Returns list of allowed scopes for a given [ResourceOwner].
  ///
  /// Subclasses override this method to return a list of [AuthScope]s based on some attribute(s) of an [ResourceOwner].
  /// That [ResourceOwner] is then restricted to only those scopes, even if the authenticating client would allow other scopes
  /// or scopes with higher privileges.
  ///
  /// By default, this method returns [AuthScope.any] - any [ResourceOwner] being authenticated has full access to the scopes
  /// available to the authenticating client.
  ///
  /// When overriding this method, it is important to note that (by default) only the properties declared by [ResourceOwner]
  /// will be valid for [owner]. If [owner] has properties that are application-specific (like a `role`),
  /// [getResourceOwner] must also be overridden to ensure those values are fetched.
  List<AuthScope> getAllowedScopes(ResourceOwner owner) => AuthScope.any;
}
