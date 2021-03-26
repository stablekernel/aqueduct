/// Library for implementing OAuth 2.0 storage using [ManagedObject]s.
///
/// This library contains [ManagedObject] subclasses to represent OAuth 2.0 artifacts
/// and implements [AuthServerDelegate] for use by an [AuthServer]. Usage of this library involves two tasks.
/// First, an instance of [ManagedAuthDelegate] is provided to an [AuthServer] at startup:
///
///         var context = ManagedContext(dataModel, store);
///         var storage = ManagedAuthStorage<User>(context)
///         var authServer = AuthServer(storage);
///
/// Then, a [ManagedObject] subclass that represents an OAuth 2.0 resource owner ust be declared. It must implement [ManagedAuthResourceOwner].
/// Its table definition must implement [ResourceOwnerTableDefinition]. For example, the follower `User` fulfills the requirement:
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
    final tokenResourceOwner =
        entity.relationships["resourceOwner"].destinationEntity.instanceOf();
    tokenResourceOwner["id"] = t.resourceOwnerIdentifier;
    this
      ..accessToken = t.accessToken
      ..refreshToken = t.refreshToken
      ..issueDate = t.issueDate
      ..expirationDate = t.expirationDate
      ..type = t.type
      ..scope = t.scopes?.map((s) => s.toString())?.join(" ")
      ..resourceOwner = tokenResourceOwner as ResourceOwnerTableDefinition
      ..client = (ManagedAuthClient()..id = t.clientID);
  }

  /// Instance from an [AuthCode].
  ManagedAuthToken.fromCode(AuthCode code) : super() {
    final tokenResourceOwner =
        entity.relationships["resourceOwner"].destinationEntity.instanceOf();
    tokenResourceOwner["id"] = code.resourceOwnerIdentifier;

    this
      ..code = code.code
      ..resourceOwner = tokenResourceOwner as ResourceOwnerTableDefinition
      ..issueDate = code.issueDate
      ..expirationDate = code.expirationDate
      ..scope = code.requestedScopes?.map((s) => s.toString())?.join(" ")
      ..client = (ManagedAuthClient()..id = code.clientID);
  }

  /// As an [AuthToken].
  AuthToken asToken() {
    return AuthToken()
      ..accessToken = accessToken
      ..refreshToken = refreshToken
      ..issueDate = issueDate
      ..expirationDate = expirationDate
      ..type = type
      ..resourceOwnerIdentifier = resourceOwner.id
      ..scopes = scope?.split(" ")?.map((s) => AuthScope(s))?.toList()
      ..clientID = client.id;
  }

  /// As an [AuthCode].
  AuthCode asAuthCode() {
    return AuthCode()
      ..hasBeenExchanged = accessToken != null
      ..code = code
      ..resourceOwnerIdentifier = resourceOwner.id
      ..issueDate = issueDate
      ..requestedScopes = scope?.split(" ")?.map((s) => AuthScope(s))?.toList()
      ..expirationDate = expirationDate
      ..clientID = client.id;
  }
}

@Table(name: "_authtoken")
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
  /// [ResourceOwnerTableDefinition] must be implemented by some [ManagedObject] subclass in an application.
  /// That subclass will be the 'owner' of tokens. See [ResourceOwnerTableDefinition] for more details.
  @Relate.deferred(DeleteRule.cascade, isRequired: true)
  ResourceOwnerTableDefinition resourceOwner;

  /// The client this token was issued for.
  @Relate(Symbol('tokens'), onDelete: DeleteRule.cascade, isRequired: true)
  ManagedAuthClient client;

  /// The value 'bearer'.
  @Column(indexed: true, nullable: true)
  String type;
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
  /// Default constructor.
  ManagedAuthClient();

  /// Create from an [AuthClient].
  ManagedAuthClient.fromClient(AuthClient client) {
    id = client.id;
    hashedSecret = client.hashedSecret;
    salt = client.salt;
    redirectURI = client.redirectURI;
    allowedScope = client.allowedScopes?.map((s) => s.toString())?.join(" ");
  }

  /// As an [AuthClient].
  AuthClient asClient() {
    final scopes = allowedScope?.split(" ")?.map((s) => AuthScope(s))?.toList();

    return AuthClient.withRedirectURI(id, hashedSecret, salt, redirectURI,
        allowedScopes: scopes);
  }
}

@Table(name: "_authclient")
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
  @Column(nullable: true)
  String redirectURI;

  /// Scopes that this client allows.
  ///
  /// If null, this client does not support scopes and all tokens are valid for all routes.
  @Column(nullable: true)
  String allowedScope;

  /// Tokens that have been issued for this client.
  ManagedSet<ManagedAuthToken> tokens;
}

/// REQUIRED: Represents an OAuth 2.0 Resource Owner database table.
///
/// An application using this library must declare a [ManagedObject] subclass
/// whose table definition must *extend* this type. For example,
///
///         class User extends ManagedObject<_User> implements _User, ManagedAuthResourceOwner  {}
///         class _User extends ManagedAuthenticatable { ... }
///
/// This requires all resource owners to have a integer primary key, username
/// and hashed password. The [ManagedObject] subclass must implement [ManagedAuthResourceOwner].
class ResourceOwnerTableDefinition implements ResourceOwner {
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
/// Note that this interface is made up of both [ResourceOwnerTableDefinition] and [ManagedObject].
/// The type declaring this as an interface must extend [ManagedObject] and implement
/// a table definition that extends [ResourceOwnerTableDefinition]. Since all [ManagedObject] subclasses
/// extend their table definition, this interface requirement is met.
abstract class ManagedAuthResourceOwner<T>
    implements ResourceOwnerTableDefinition, ManagedObject<T> {}

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
///         var context = ManagedContext(dataModel, store);
///         var storage = ManagedAuthStorage<User>(context)
///         var authServer = AuthServer(storage);
///
class ManagedAuthDelegate<T extends ManagedAuthResourceOwner>
    extends AuthServerDelegate {
  /// Creates an instance of this type.
  ///
  /// [context]'s [ManagedDataModel] must contain [T], [ManagedAuthToken] and [ManagedAuthClient].
  ManagedAuthDelegate(this.context, {this.tokenLimit = 40});

  /// The [ManagedContext] this instance uses to store and retrieve values.
  final ManagedContext context;

  /// The number of tokens and authorization codes a user can have at a time.
  ///
  /// Once this limit is passed, older tokens and authorization codes are revoked automatically.
  final int tokenLimit;

  @override
  Future removeTokens(AuthServer server, int resourceOwnerID) {
    final tokenQuery = Query<ManagedAuthToken>(context)
      ..where((o) => o.resourceOwner).identifiedBy(resourceOwnerID);

    return tokenQuery.delete();
  }

  @override
  Future<AuthToken> getToken(AuthServer server,
      {String byAccessToken, String byRefreshToken}) async {
    if (byAccessToken != null && byRefreshToken != null) {
      throw ArgumentError(
          "Exactly one of 'byAccessToken' or 'byRefreshToken' must be non-null.");
    }

    final query = Query<ManagedAuthToken>(context);
    if (byAccessToken != null) {
      query.where((o) => o.accessToken).equalTo(byAccessToken);
    } else if (byRefreshToken != null) {
      query.where((o) => o.refreshToken).equalTo(byRefreshToken);
    } else {
      throw ArgumentError(
          "Exactly one of 'byAccessToken' or 'byRefreshToken' must be non-null.");
    }

    final token = await query.fetchOne();

    return token?.asToken();
  }

  @override
  Future<T> getResourceOwner(AuthServer server, String username) {
    final query = Query<T>(context)
      ..where((o) => o.username).equalTo(username)
      ..returningProperties(
          (t) => [t.id, t.hashedPassword, t.salt, t.username]);

    return query.fetchOne();
  }

  @override
  Future removeToken(AuthServer server, AuthCode grantedByCode) {
    final query = Query<ManagedAuthToken>(context)
      ..where((o) => o.code).equalTo(grantedByCode.code);

    return query.delete();
  }

  @override
  Future addToken(AuthServer server, AuthToken token,
      {AuthCode issuedFrom}) async {
    final storage = ManagedAuthToken.fromToken(token);
    final query = Query<ManagedAuthToken>(context)..values = storage;

    if (issuedFrom != null) {
      query.where((o) => o.code).equalTo(issuedFrom.code);
      query.values.code = issuedFrom.code;

      final outToken = await query.updateOne();
      if (outToken == null) {
        throw AuthServerException(AuthRequestError.invalidGrant,
            AuthClient(token.clientID, null, null));
      }
    } else {
      await query.insert();
    }

    return pruneTokens(token.resourceOwnerIdentifier);
  }

  @override
  Future updateToken(
      AuthServer server,
      String oldAccessToken,
      String newAccessToken,
      DateTime newIssueDate,
      DateTime newExpirationDate) {
    final query = Query<ManagedAuthToken>(context)
      ..where((o) => o.accessToken).equalTo(oldAccessToken)
      ..values.accessToken = newAccessToken
      ..values.issueDate = newIssueDate
      ..values.expirationDate = newExpirationDate;

    return query.updateOne();
  }

  @override
  Future addCode(AuthServer server, AuthCode code) async {
    final storage = ManagedAuthToken.fromCode(code);
    final query = Query<ManagedAuthToken>(context)..values = storage;

    await query.insert();

    return pruneTokens(code.resourceOwnerIdentifier);
  }

  @override
  Future<AuthCode> getCode(AuthServer server, String code) async {
    final query = Query<ManagedAuthToken>(context)
      ..where((o) => o.code).equalTo(code);

    final storage = await query.fetchOne();
    return storage?.asAuthCode();
  }

  @override
  Future removeCode(AuthServer server, String code) {
    final query = Query<ManagedAuthToken>(context)
      ..where((o) => o.code).equalTo(code);

    return query.delete();
  }

  @override
  Future addClient(AuthServer server, AuthClient client) async {
    final storage = ManagedAuthClient.fromClient(client);
    final query = Query<ManagedAuthClient>(context)..values = storage;
    return query.insert();
  }

  @override
  Future<AuthClient> getClient(AuthServer server, String clientID) async {
    final query = Query<ManagedAuthClient>(context)
      ..where((o) => o.id).equalTo(clientID);

    final storage = await query.fetchOne();

    return storage?.asClient();
  }

  @override
  Future removeClient(AuthServer server, String clientID) {
    final query = Query<ManagedAuthClient>(context)
      ..where((o) => o.id).equalTo(clientID);

    return query.delete();
  }

  /// Deletes expired tokens for [resourceOwnerIdentifier].
  ///
  /// If the resource owner identified by [resourceOwnerIdentifier] has expired
  /// tokens and they have reached their token issuance limit, this method
  /// will delete tokens until they are in compliance with that limit.
  ///
  /// There is rarely a need to invoke this method directly, as it is invoked each
  /// time a new token is issued.
  Future pruneTokens(dynamic resourceOwnerIdentifier) async {
    final oldTokenQuery = Query<ManagedAuthToken>(context)
      ..where((o) => o.resourceOwner).identifiedBy(resourceOwnerIdentifier)
      ..sortBy((t) => t.expirationDate, QuerySortOrder.descending)
      ..offset = tokenLimit
      ..fetchLimit = 1
      ..returningProperties((t) => [t.expirationDate]);

    final results = await oldTokenQuery.fetch();
    if (results.length == 1) {
      final deleteQ = Query<ManagedAuthToken>(context)
        ..where((o) => o.resourceOwner).identifiedBy(resourceOwnerIdentifier)
        ..where((o) => o.expirationDate)
            .lessThanEqualTo(results.first.expirationDate);

      return deleteQ.delete();
    }
  }
}
