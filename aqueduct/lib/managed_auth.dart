/// Library for implementing OAuth 2.0 storage using [ManagedObject]s.
///
/// This library contains [ManagedObject] subclasses to represent OAuth 2.0 artifacts
/// and implements [AuthServerDelegate] for use by an [AuthServer]. Usage of this library involves two tasks.
/// First, an instance of [ManagedAuthDelegate] is provided to an [AuthServer] at startup:
///
///         var context = new ManagedContext(dataModel, store);
///         var storage = new ManagedAuthStorage<User>(context)
///         var authServer = new AuthServer(storage);
///
/// Then, a [ManagedObject] subclass that represents an OAuth 2.0 resource owner ust be declared. It must implement [ManagedAuthResourceOwner].
/// Its persistent type must implement [ManagedAuthenticatable]. For example, the follower `User` fulfills the requirement:
///
///         class User extends ManagedObject<_User> implements _User, ManagedAuthResourceOwner  {}
///         class _User extends ManagedAuthenticatable { ... }
///
/// This library must be visible from the application's library file - that is, for an application named
/// 'foo', this library must be imported in `foo/foo.dart`.
///
/// This library declares two [ManagedObject] subclasses, [ManagedAuthToken] and [ManagedAuthClient].
/// An application using this library must ensure that these two types have corresponding database tables.
/// The `aqueduct db` tool will create database tables for these types as long as they are visible
/// to the application's library file, as noted above.
library aqueduct.managed_auth;

import 'dart:async';

import 'package:aqueduct/aqueduct.dart';

/// Represent an OAuth 2.0 authorization token and authorization code.
///
/// Instances of this type are created by [ManagedAuthDelegate] to store
/// authorization tokens and codes on behalf of an [AuthServer]. There is no
/// need to use this class directly.
class ManagedAuthToken extends ManagedObject<_ManagedAuthToken>
    implements _ManagedAuthToken {

  /// Empty instance.
  ManagedAuthToken() : super();

  /// Instance from an [AuthToken].
  ManagedAuthToken.fromToken(AuthToken t) : super() {
    var tokenResourceOwner = this
        .entity
        .relationships["resourceOwner"]
        .destinationEntity
        .newInstance();
    tokenResourceOwner["id"] = t.resourceOwnerIdentifier;
    this
      ..accessToken = t.accessToken
      ..refreshToken = t.refreshToken
      ..issueDate = t.issueDate
      ..expirationDate = t.expirationDate
      ..type = t.type
      ..scope = t.scopes?.map((s) => s.toString())?.join(" ")
      ..resourceOwner = tokenResourceOwner as dynamic
      ..client = (new ManagedAuthClient()..id = t.clientID);
  }

  /// Instance from an [AuthCode].
  ManagedAuthToken.fromCode(AuthCode code) : super() {
    var tokenResourceOwner = this
        .entity
        .relationships["resourceOwner"]
        .destinationEntity
        .newInstance();
    tokenResourceOwner["id"] = code.resourceOwnerIdentifier;

    this
      ..code = code.code
      ..resourceOwner = tokenResourceOwner as dynamic
      ..issueDate = code.issueDate
      ..expirationDate = code.expirationDate
      ..scope = code.requestedScopes?.map((s) => s.toString())?.join(" ")
      ..client = (new ManagedAuthClient()..id = code.clientID);
  }

  /// As an [AuthToken].
  AuthToken asToken() {
    return new AuthToken()
      ..accessToken = accessToken
      ..refreshToken = refreshToken
      ..issueDate = issueDate
      ..expirationDate = expirationDate
      ..type = type
      ..resourceOwnerIdentifier = resourceOwner.id
      ..scopes = scope?.split(" ")?.map((s) => new AuthScope(s))?.toList()
      ..clientID = client.id;
  }

  /// As an [AuthCode].
  AuthCode asAuthCode() {
    return new AuthCode()
      ..hasBeenExchanged = accessToken != null
      ..code = code
      ..resourceOwnerIdentifier = resourceOwner.id
      ..issueDate = issueDate
      ..requestedScopes = scope?.split(" ")?.map((s) => new AuthScope(s))?.toList()
      ..expirationDate = expirationDate
      ..clientID = client.id;
  }
}

class _ManagedAuthToken {
  /// A primary key identifier.
  @primaryKey
  int id;

  /// The authorization code of this token.
  ///
  /// This value is non-null if this instance represents an authorization code
  /// that hasn't yet been exchanged for a token or if this instance represents
  /// a token that has been exchanged for this code. This value is null
  /// if this instance represents a token that was not created through
  /// the authorization code process.
  @Column(indexed: true, unique: true, nullable: true)
  String code;

  /// The access token of an authorization token.
  ///
  /// If this instance represents an authorization token, this value is its
  /// access token. This value is null if this instance represents an
  /// unexchanged authorization code.
  @Column(indexed: true, unique: true, nullable: true)
  String accessToken;

  /// The refresh token of an authorization token.
  ///
  /// If this token can be refreshed, this value is non-null.
  @Column(indexed: true, unique: true, nullable: true)
  String refreshToken;

  /// Scopes for this token, delimited by the space character.
  @Column(nullable: true)
  String scope;

  /// When this token was last issued or refreshed.
  DateTime issueDate;

  /// When this token will expire.
  @Column(indexed: true)
  DateTime expirationDate;

  /// The resource owner of this token.
  ///
  /// [ManagedAuthenticatable] must be implemented by some [ManagedObject] subclass in an application.
  /// That subclass will be the 'owner' of tokens. See [ManagedAuthenticatable] for more details.
  @Relate.deferred(DeleteRule.cascade,
      isRequired: true)
  ManagedAuthenticatable resourceOwner;

  /// The client this token was issued for.
  @Relate(#tokens,
      onDelete: DeleteRule.cascade, isRequired: true)
  ManagedAuthClient client;

  /// The value 'bearer'.
  @Column(indexed: true, nullable: true)
  String type;

  static String tableName() => "_authtoken";
}

/// Represent OAuth 2.0 clients.
///
/// A client has, at minimum, a valid [id]. A client with only an [id] is a 'public' client, per the
/// OAuth 2.0 definition. A client created with a [hashedSecret] and [salt] is a 'confidential' client.
/// Only confidential clients may have a [redirectURI]. Only clients with a [redirectURI] may use the authorization
/// code flow.
///
/// Use the `aqueduct auth` tool to add new clients to an application.
class ManagedAuthClient extends ManagedObject<_ManagedAuthClient>
    implements _ManagedAuthClient {
  /// As an [AuthClient].
  AuthClient asClient() {
    var scopes = allowedScope
        ?.split(" ")
        ?.map((s) => new AuthScope(s))
        ?.toList();

    return new AuthClient.withRedirectURI(id, hashedSecret, salt, redirectURI,
        allowedScopes: scopes);
  }
}

class _ManagedAuthClient {
  /// The client identifier of this client.
  ///
  /// An OAuth 2.0 client represents the client application that authorizes on behalf of the user
  /// with this server. For example 'com.company.mobile_apps'. This value is required.
  @Column(primaryKey: true)
  String id;

  /// The client secret, hashed with [salt], if this client is confidential.
  ///
  /// A confidential client requires its secret to be included when used. If this value is null,
  /// this client is a public client.
  @Column(nullable: true)
  String hashedSecret;

  /// The hashing salt for [hashedSecret].
  @Column(nullable: true)
  String salt;

  /// The redirect URI for the authorization code flow.
  ///
  /// This value must be a valid URI to allow the authorization code flow. A user agent
  /// is redirected to this URI with an authorization code that can be exchanged
  /// for a token. Only confidential clients may have a value.
  @Column(unique: true, nullable: true)
  String redirectURI;

  /// Scopes that this client allows.
  ///
  /// If null, this client does not support scopes and all tokens are valid for all routes.
  @Column(nullable: true)
  String allowedScope;

  /// Tokens that have been issued for this client.
  ManagedSet<ManagedAuthToken> tokens;

  static String tableName() => "_authclient";
}

/// REQUIRED: Represents an OAuth 2.0 Resource Owner database table.
///
/// An application using this library must declare a [ManagedObject] subclass
/// whose persistent type must *extend* this type. For example,
///
///         class User extends ManagedObject<_User> implements _User, ManagedAuthResourceOwner  {}
///         class _User extends ManagedAuthenticatable { ... }
///
/// This requires all resource owners to have a integer primary key, username
/// and hashed password. The [ManagedObject] subclass must implement [ManagedAuthResourceOwner].
class ManagedAuthenticatable implements Authenticatable {
  /// The primary key of a resource owner.
  @override
  @primaryKey
  int id;

  /// The username of a resource owner.
  @override
  @Column(unique: true, indexed: true)
  String username;

  /// The hashed password of a resource owner.
  @override
  @Column(omitByDefault: true)
  String hashedPassword;

  /// The salt for [hashedPassword].
  @override
  @Column(omitByDefault: true)
  String salt;

  /// The list of tokens issue for this resource owner.
  ManagedSet<ManagedAuthToken> tokens;
}

/// REQUIRED: An OAuth 2.0 Resource Owner as a [ManagedObject].
///
/// An application using this library must declare a [ManagedObject] subclass
/// that implements this type. This type will represent instances of a resource owner
/// in an application. For example,
///
///         class User extends ManagedObject<_User> implements _User, ManagedAuthResourceOwner  {}
///         class _User extends ManagedAuthenticatable { ... }
///
/// Note that this interface is made up of both [ManagedAuthenticatable] and [ManagedObject].
/// The type declaring this as an interface must extend [ManagedObject] and implement
/// a persistent type that extends [ManagedAuthenticatable]. Since all [ManagedObject] subclasses
/// extend their persistent type, this interface requirement is met.
abstract class ManagedAuthResourceOwner<T>
    implements ManagedAuthenticatable, ManagedObject<T> {}

/// [AuthServerDelegate] implementation for an [AuthServer] using [ManagedObject]s.
///
/// An instance of this class manages storage and retrieval of OAuth 2.0 tokens, clients and resource owners
/// using the [ManagedObject]s declared in this library.
///
/// The type argument must be the application-specific resource owner that implements [ManagedAuthResourceOwner].
///
/// Provide an instance of this type to an [AuthServer] at startup. For example, if the application has a type named `User` that fulfills
/// [ManagedAuthResourceOwner],
///
///         var context = new ManagedContext(dataModel, store);
///         var storage = new ManagedAuthStorage<User>(context)
///         var authServer = new AuthServer(storage);
///
class ManagedAuthDelegate<T extends ManagedAuthResourceOwner>
    extends AuthServerDelegate {

  /// Creates an instance of this type.
  ///
  /// [context]'s [ManagedDataModel] must contain [T], [ManagedAuthToken] and [ManagedAuthClient].
  ManagedAuthDelegate(this.context, {this.tokenLimit: 40});

  /// The [ManagedContext] this instance uses to store and retrieve values.
  final ManagedContext context;

  /// The number of tokens and authorization codes a user can have at a time.
  ///
  /// Once this limit is passed, older tokens and authorization codes are revoked automatically.
  final int tokenLimit;

  @override
  Future revokeAuthenticatableWithIdentifier(
      AuthServer server, dynamic identifier) {
    var tokenQuery = new Query<ManagedAuthToken>(context)
      ..where((o) => o.resourceOwner).identifiedBy(identifier);

    return tokenQuery.delete();
  }

  @override
  Future<AuthToken> fetchTokenByAccessToken(
      AuthServer server, String accessToken) async {
    var query = new Query<ManagedAuthToken>(context)
      ..where((o) => o.accessToken).equalTo(accessToken);
    var token = await query.fetchOne();

    return token?.asToken();
  }

  @override
  Future<AuthToken> fetchTokenByRefreshToken(
      AuthServer server, String refreshToken) async {
    var query = new Query<ManagedAuthToken>(context)
      ..where((o) => o.refreshToken).equalTo(refreshToken);
    var token = await query.fetchOne();

    return token?.asToken();
  }

  @override
  Future<T> fetchAuthenticatableByUsername(AuthServer server, String username) {
    var query = new Query<T>(context)
      ..where((o) => o.username).equalTo(username)
      ..returningProperties((t) => [t.id, t.hashedPassword, t.salt, t.username]);

    return query.fetchOne();
  }

  @override
  Future revokeTokenIssuedFromCode(AuthServer server, AuthCode code) {
    var query = new Query<ManagedAuthToken>(context)..where((o) => o.code).equalTo(code.code);

    return query.delete();
  }

  @override
  Future storeToken(AuthServer server, AuthToken t,
      {AuthCode issuedFrom}) async {
    var storage = new ManagedAuthToken.fromToken(t);
    var query = new Query<ManagedAuthToken>(context)..values = storage;

    if (issuedFrom != null) {
      query.where((o) => o.code).equalTo(issuedFrom.code);
      query.values.code = issuedFrom.code;
      var outToken = await query.updateOne();
      if (outToken == null) {
        throw new AuthServerException(AuthRequestError.invalidGrant,
            new AuthClient(t.clientID, null, null));
      }
    } else {
      await query.insert();
    }

    return pruneTokens(t.resourceOwnerIdentifier);
  }

  @override
  Future refreshTokenWithAccessToken(
      AuthServer server,
      String oldAccessToken,
      String newAccessToken,
      DateTime newIssueDate,
      DateTime newExpirationDate) {
    var query = new Query<ManagedAuthToken>(context)
      ..where((o) => o.accessToken).equalTo(oldAccessToken)
      ..values.accessToken = newAccessToken
      ..values.issueDate = newIssueDate
      ..values.expirationDate = newExpirationDate;

    return query.updateOne();
  }

  @override
  Future storeAuthCode(AuthServer server, AuthCode code) async {
    var storage = new ManagedAuthToken.fromCode(code);
    var query = new Query<ManagedAuthToken>(context)..values = storage;
    await query.insert();

    return pruneTokens(code.resourceOwnerIdentifier);
  }

  @override
  Future<AuthCode> fetchAuthCodeByCode(AuthServer server, String code) async {
    var query = new Query<ManagedAuthToken>(context)..where((o) => o.code).equalTo(code);

    var storage = await query.fetchOne();
    return storage?.asAuthCode();
  }

  @override
  Future revokeAuthCodeWithCode(AuthServer server, String code) {
    var query = new Query<ManagedAuthToken>(context)..where((o) => o.code).equalTo(code);

    return query.delete();
  }

  @override
  Future<AuthClient> fetchClientByID(AuthServer server, String id) async {
    var query = new Query<ManagedAuthClient>(context)..where((o) => o.id).equalTo(id);

    var storage = await query.fetchOne();

    return storage?.asClient();
  }

  @override
  Future revokeClientWithID(AuthServer server, String id) {
    var query = new Query<ManagedAuthClient>(context)..where((o) => o.id).equalTo(id);

    return query.delete();
  }

  Future pruneTokens(dynamic resourceOwnerIdentifier) async {
    var oldTokenQuery = new Query<ManagedAuthToken>(context)
      ..where((o) => o.resourceOwner).identifiedBy(resourceOwnerIdentifier)
      ..sortBy((t) => t.expirationDate, QuerySortOrder.descending)
      ..offset = tokenLimit
      ..fetchLimit = 1
      ..returningProperties((t) => [t.expirationDate]);

    var results = await oldTokenQuery.fetch();
    if (results.length == 1) {
      var deleteQ = new Query<ManagedAuthToken>(context)
        ..where((o) => o.resourceOwner).identifiedBy(resourceOwnerIdentifier)
        ..where((o) => o.expirationDate).lessThanEqualTo(results.first.expirationDate);

      return deleteQ.delete();
    }
  }
}
