import 'dart:async';

import 'package:aqueduct/aqueduct.dart';

class ManagedToken extends ManagedObject<_ManagedToken> implements _ManagedToken {
  ManagedToken() : super();
  ManagedToken.fromToken(AuthToken t) : super() {
    this
        ..accessToken = t.accessToken
        ..refreshToken = t.refreshToken
        ..issueDate = t.issueDate
        ..expirationDate = t.expirationDate
        ..resourceOwner = (new ManagedAuthenticatable()..id = t.resourceOwnerIdentifier)
        ..client = (new ManagedClient()..id = t.clientID);
//        ..scopes = t.scope;
  }

  AuthToken asToken() {
    return new AuthToken()
        ..uniqueIdentifier = id
        ..accessToken = accessToken
        ..refreshToken = refreshToken
        ..issueDate = issueDate
        ..expirationDate = expirationDate
        ..type = type
        ..resourceOwnerIdentifier = resourceOwner.id
        ..clientID = client.id;
        //..scope = scopes;
  }

  String get type => "bearer";
//  List<AuthScope> get scopes {
//    return scopeStorage
//        ?.split(" ")
//        ?.map((each) => new AuthScope(each))
//        ?.toList() ?? [];
//  }
//
//  void set scopes(List<AuthScope> s) {
//    scopeStorage = s
//        ?.map((scope) => scope.toString())
//        ?.join(" ") ?? "";
//  }
}
class _ManagedToken {
  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(indexed: true, unique: true)
  String accessToken;

  @ManagedColumnAttributes(indexed: true, nullable: true, unique: true)
  String refreshToken;

  DateTime issueDate;

  @ManagedColumnAttributes(indexed: true)
  DateTime expirationDate;

  @managedPartialObject
  @ManagedRelationship(#tokens, onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: true)
  ManagedAuthenticatable resourceOwner;

  @ManagedRelationship(#tokens,
      onDelete: ManagedRelationshipDeleteRule.cascade,
      isRequired: true)
  ManagedClient client;

  ManagedAuthCode issuingAuthCode;

//  String scopeStorage;
}

class ManagedClient extends ManagedObject<_ManagedClient> implements _ManagedClient {
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
  ManagedSet<ManagedAuthCode> authCodes;
}

class ManagedAuthCode extends ManagedObject<_ManagedAuthCode> implements _ManagedAuthCode {
  ManagedAuthCode() : super();
  ManagedAuthCode.fromCode(AuthCode code) : super() {
    this
        ..code = code.code
        ..resourceOwner = (new ManagedAuthenticatable()..id = code.resourceOwnerIdentifier)
        ..issueDate = code.issueDate
        ..expirationDate = code.expirationDate
        ..client = (new ManagedClient()
          ..id = code.clientID
          ..redirectURI = code.redirectURI);
  }

  AuthCode asAuthCode() {
    return new AuthCode()
      ..tokenIdentifier = token?.id
      ..code = code
      ..resourceOwnerIdentifier = resourceOwner.id
      ..issueDate = issueDate
      ..expirationDate = expirationDate
      ..clientID = client.id;
  }
}

class _ManagedAuthCode {
  @ManagedColumnAttributes(primaryKey: true)
  String code;

  @managedPartialObject
  @ManagedRelationship(#authorizationCodes, onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: true)
  ManagedAuthenticatable resourceOwner;

  DateTime issueDate;

  @ManagedColumnAttributes(indexed: true)
  DateTime expirationDate;

  @ManagedRelationship(#issuingAuthCode, onDelete: ManagedRelationshipDeleteRule.cascade)
  ManagedToken token;

  @ManagedRelationship(#authCodes, onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: true)
  ManagedClient client;

  // String requestedScopeStorage;
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

  ManagedSet<ManagedAuthCode> authorizationCodes;
  ManagedSet<ManagedToken> tokens;
}

abstract class ManagedAuthResourceOwnerType implements ManagedAuthenticatable, ManagedObject {}

class ManagedAuthStorage<T extends ManagedAuthResourceOwnerType> implements AuthStorage {
  ManagedAuthStorage(this.context, {this.codeLimit: 10, this.tokenLimit: 40});

  ManagedContext context;
  int tokenLimit;
  int codeLimit;

  Future revokeAuthenticatableAccessForIdentifier(AuthServer server, dynamic identifier) async {
    var tokenQuery = new Query<ManagedToken>()
      ..matchOn.resourceOwner = whereRelatedByValue(identifier);
    await tokenQuery.delete();

    var codeQuery = new Query<ManagedAuthCode>()
      ..matchOn.resourceOwner = whereRelatedByValue(identifier);
    await codeQuery.delete();
  }

  @override
  Future<AuthToken> fetchTokenWithAccessToken(AuthServer server, String accessToken) async {
    var query = new Query<ManagedToken>(context)
        ..matchOn.accessToken = accessToken;
    var token = await query.fetchOne();

    return token?.asToken();
  }

  @override
  Future<AuthToken> fetchTokenWithRefreshToken(AuthServer server, String refreshToken) async {
    var query = new Query<ManagedToken>(context)
      ..matchOn.refreshToken = refreshToken;
    var token = await query.fetchOne();

    return token?.asToken();
  }

  @override
  Future<T> fetchResourceOwnerWithUsername(
      AuthServer server, String username) async {
    var query = new Query<T>(context)
        ..matchOn.username = username
        ..resultProperties = ["id", "hashedPassword", "salt"];

    return query.fetchOne();
  }

  @override
  Future revokeTokenWithIdentifier(AuthServer server, dynamic identifier) async {
    var query = new Query<ManagedToken>(context)
      ..matchOn.id = identifier;

    await query.delete();
  }

  @override
  Future<dynamic> storeTokenAndReturnUniqueIdentifier(AuthServer server, AuthToken t) async {
    var storage = new ManagedToken.fromToken(t);
    var query = new Query<ManagedToken>(context)
      ..values = storage;
    var inserted = await query.insert();

    var oldTokenQuery = new Query<ManagedToken>()
      ..matchOn.resourceOwner = whereRelatedByValue(t.resourceOwnerIdentifier)
      ..sortDescriptors = [
        new QuerySortDescriptor("expirationDate", QuerySortOrder.descending)
      ]
      ..offset = tokenLimit
      ..fetchLimit = 1
      ..resultProperties = ["expirationDate"];


    var results = await oldTokenQuery.fetch();
    if (results.length == 1) {
      var deleteQ = new Query<ManagedToken>()
        ..matchOn.resourceOwner = whereRelatedByValue(t.resourceOwnerIdentifier)
        ..matchOn.expirationDate = whereLessThanEqualTo(results.first.expirationDate);

      await deleteQ.delete();
    }

    return inserted.id;
  }

  @override
  Future refreshTokenWithIdentifier(AuthServer server, dynamic identifier, String newAccessToken, DateTime newIssueDate, DateTime newExpirationDate) async {
    var query = new Query<ManagedToken>(context)
      ..matchOn.id = identifier
      ..values.accessToken = newAccessToken
      ..values.issueDate = newIssueDate
      ..values.expirationDate = newExpirationDate;

    await query.updateOne();
  }

  @override
  Future storeAuthCode(AuthServer server, AuthCode code) async {
    var storage = new ManagedAuthCode.fromCode(code);
    var query = new Query<ManagedAuthCode>(context)
      ..values = storage;
    await query.insert();

    var oldCodeQuery = new Query<ManagedAuthCode>()
      ..matchOn.resourceOwner = whereRelatedByValue(code.resourceOwnerIdentifier)
      ..sortDescriptors = [
        new QuerySortDescriptor("expirationDate", QuerySortOrder.descending)
      ]
      ..offset = codeLimit
      ..fetchLimit = 1
      ..resultProperties = ["expirationDate"];


    var results = await oldCodeQuery.fetch();
    if (results.length == 1) {
      var deleteQ = new Query<ManagedAuthCode>()
        ..matchOn.resourceOwner = whereRelatedByValue(code.resourceOwnerIdentifier)
        ..matchOn.expirationDate = whereLessThanEqualTo(results.first.expirationDate);

      await deleteQ.delete();
    }
  }

  @override
  Future<AuthCode> fetchAuthCodeWithCode(AuthServer server, String code) async {
    var query = new Query<ManagedAuthCode>(context)
        ..matchOn.code = code;

    var storage = await query.fetchOne();
    return storage?.asAuthCode();
  }

  @override
  Future associateAuthCodeWithTokenIdentifier(AuthServer server, String code, dynamic tokenIdentifier) async {
    var query = new Query<ManagedAuthCode>(context)
      ..matchOn.code = code
      ..values.token = (new ManagedToken()..id = tokenIdentifier)
      ..resultProperties = [];

    await query.updateOne();
  }

  @override
  Future revokeAuthCodeWithCode(AuthServer server, String code) async {
    var query = new Query<ManagedAuthCode>(context)
      ..matchOn.code = code;

    await query.delete();
  }

  @override
  Future<AuthClient> fetchClientWithID(AuthServer server, String id) async {
    var query = new Query<ManagedClient>(context)
      ..matchOn.id = id;

    var storage = await query.fetchOne();

    return storage?.asClient();
  }

  @override
  Future revokeClientWithID(AuthServer server, String id) async {
    var query = new Query<ManagedClient>(context)
      ..matchOn.id = id;

    await query.delete();
  }
}