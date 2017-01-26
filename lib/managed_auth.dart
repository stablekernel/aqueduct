import 'dart:async';

import 'package:aqueduct/aqueduct.dart';

class ManagedToken extends ManagedObject<_ManagedToken>
    implements _ManagedToken {
  ManagedToken() : super();
  ManagedToken.fromToken(AuthToken t) : super() {
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
      ..resourceOwner = tokenResourceOwner as dynamic
      ..client = (new ManagedClient()..id = t.clientID);
  }

  ManagedToken.fromCode(AuthCode code) : super() {
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
      ..client = (new ManagedClient()..id = code.clientID);
  }

  AuthToken asToken() {
    return new AuthToken()
      ..accessToken = accessToken
      ..refreshToken = refreshToken
      ..issueDate = issueDate
      ..expirationDate = expirationDate
      ..type = type
      ..resourceOwnerIdentifier = resourceOwner.id
      ..clientID = client.id;
  }

  AuthCode asAuthCode() {
    return new AuthCode()
      ..hasBeenExchanged = accessToken != null
      ..code = code
      ..resourceOwnerIdentifier = resourceOwner.id
      ..issueDate = issueDate
      ..expirationDate = expirationDate
      ..clientID = client.id;
  }
}

class _ManagedToken {
  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(indexed: true, unique: true, nullable: true)
  String code;

  @ManagedColumnAttributes(indexed: true, unique: true, nullable: true)
  String accessToken;

  @ManagedColumnAttributes(indexed: true, unique: true, nullable: true)
  String refreshToken;

  DateTime issueDate;

  @ManagedColumnAttributes(indexed: true)
  DateTime expirationDate;

  @ManagedRelationship.deferred(ManagedRelationshipDeleteRule.cascade,
      isRequired: true)
  ManagedAuthenticatable resourceOwner;

  @ManagedRelationship(#tokens,
      onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: true)
  ManagedClient client;

  @ManagedColumnAttributes(indexed: true, nullable: true)
  String type;

  static String tableName() => "_authtoken";
}

class ManagedClient extends ManagedObject<_ManagedClient>
    implements _ManagedClient {
  AuthClient asClient() {
    return new AuthClient.withRedirectURI(id, hashedSecret, salt, redirectURI);
  }
}

class _ManagedClient {
  @ManagedColumnAttributes(primaryKey: true)
  String id;

  @ManagedColumnAttributes(nullable: true)
  String hashedSecret;

  @ManagedColumnAttributes(nullable: true)
  String salt;

  @ManagedColumnAttributes(unique: true, nullable: true)
  String redirectURI;

  ManagedSet<ManagedToken> tokens;

  static String tableName() => "_authclient";
}

class ManagedAuthenticatable implements Authenticatable {
  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(unique: true, indexed: true)
  String username;

  @ManagedColumnAttributes(omitByDefault: true)
  String hashedPassword;

  @ManagedColumnAttributes(omitByDefault: true)
  String salt;

  ManagedSet<ManagedToken> tokens;
}

abstract class ManagedAuthResourceOwner
    implements ManagedAuthenticatable, ManagedObject {}

class ManagedAuthStorage<T extends ManagedAuthResourceOwner>
    implements AuthStorage {
  ManagedAuthStorage(this.context, {this.tokenLimit: 40});

  ManagedContext context;
  int tokenLimit;

  Future revokeAuthenticatableWithIdentifier(
      AuthServer server, dynamic identifier) async {
    var tokenQuery = new Query<ManagedToken>(context)
      ..where.resourceOwner = whereRelatedByValue(identifier);
    await tokenQuery.delete();
  }

  @override
  Future<AuthToken> fetchTokenByAccessToken(
      AuthServer server, String accessToken) async {
    var query = new Query<ManagedToken>(context)
      ..where.accessToken = accessToken;
    var token = await query.fetchOne();

    return token?.asToken();
  }

  @override
  Future<AuthToken> fetchTokenByRefreshToken(
      AuthServer server, String refreshToken) async {
    var query = new Query<ManagedToken>(context)
      ..where.refreshToken = refreshToken;
    var token = await query.fetchOne();

    return token?.asToken();
  }

  @override
  Future<T> fetchAuthenticatableByUsername(
      AuthServer server, String username) async {
    var query = new Query<T>(context)
      ..where.username = username
      ..propertiesToFetch = ["id", "hashedPassword", "salt"];

    return query.fetchOne();
  }

  @override
  Future revokeTokenIssuedFromCode(AuthServer server, AuthCode code) async {
    var query = new Query<ManagedToken>(context)..where.code = code.code;

    await query.delete();
  }

  @override
  Future storeToken(AuthServer server, AuthToken t,
      {AuthCode issuedFrom}) async {
    var storage = new ManagedToken.fromToken(t);
    var query = new Query<ManagedToken>(context)..values = storage;

    if (issuedFrom != null) {
      query.where.code = whereEqualTo(issuedFrom.code);
      query.values.code = issuedFrom.code;
      var outToken = await query.updateOne();
      if (outToken == null) {
        throw new AuthServerException(AuthRequestError.invalidGrant,
            new AuthClient(t.clientID, null, null));
      }
    } else {
      await query.insert();
    }

    await pruneTokens(t.resourceOwnerIdentifier);
  }

  @override
  Future refreshTokenWithAccessToken(
      AuthServer server,
      String oldAccessToken,
      String newAccessToken,
      DateTime newIssueDate,
      DateTime newExpirationDate) async {
    var query = new Query<ManagedToken>(context)
      ..where.accessToken = oldAccessToken
      ..values.accessToken = newAccessToken
      ..values.issueDate = newIssueDate
      ..values.expirationDate = newExpirationDate;

    await query.updateOne();
  }

  @override
  Future storeAuthCode(AuthServer server, AuthCode code) async {
    var storage = new ManagedToken.fromCode(code);
    var query = new Query<ManagedToken>(context)..values = storage;
    await query.insert();

    await pruneTokens(code.resourceOwnerIdentifier);
  }

  @override
  Future<AuthCode> fetchAuthCodeByCode(AuthServer server, String code) async {
    var query = new Query<ManagedToken>(context)..where.code = code;

    var storage = await query.fetchOne();
    return storage?.asAuthCode();
  }

  @override
  Future revokeAuthCodeWithCode(AuthServer server, String code) async {
    var query = new Query<ManagedToken>(context)..where.code = code;

    await query.delete();
  }

  @override
  Future<AuthClient> fetchClientByID(AuthServer server, String id) async {
    var query = new Query<ManagedClient>(context)..where.id = id;

    var storage = await query.fetchOne();

    return storage?.asClient();
  }

  @override
  Future revokeClientWithID(AuthServer server, String id) async {
    var query = new Query<ManagedClient>(context)..where.id = id;

    await query.delete();
  }

  Future pruneTokens(dynamic resourceOwnerIdentifier) async {
    var oldTokenQuery = new Query<ManagedToken>(context)
      ..where.resourceOwner = whereRelatedByValue(resourceOwnerIdentifier)
      ..sortDescriptors = [
        new QuerySortDescriptor("expirationDate", QuerySortOrder.descending)
      ]
      ..offset = tokenLimit
      ..fetchLimit = 1
      ..propertiesToFetch = ["expirationDate"];

    var results = await oldTokenQuery.fetch();
    if (results.length == 1) {
      var deleteQ = new Query<ManagedToken>()
        ..where.resourceOwner = whereRelatedByValue(resourceOwnerIdentifier)
        ..where.expirationDate =
            whereLessThanEqualTo(results.first.expirationDate);

      await deleteQ.delete();
    }
  }
}
