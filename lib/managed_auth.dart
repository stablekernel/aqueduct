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
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
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
        ..resourceOwnerIdentifier = resourceOwnerIdentifier
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

  @ManagedColumnAttributes(indexed: true)
  int resourceOwnerIdentifier;

  @ManagedRelationship(#tokens,
      onDelete: ManagedRelationshipDeleteRule.cascade,
      isRequired: true)
  ManagedClient client;

  @ManagedRelationship(#token)
  ManagedAuthCode authCode;

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
        ..resourceOwnerIdentifier = code.resourceOwnerIdentifier
        ..issueDate = code.issueDate
        ..expirationDate = code.expirationDate
        ..client = (new ManagedClient()
          ..id = code.clientID
          ..redirectURI = code.redirectURI);

        // ..redirectURI
        //..token = (new ManagedToken()..)
  }

  AuthCode asAuthCode() {
    return new AuthCode()
      ..code = code
      ..resourceOwnerIdentifier = resourceOwnerIdentifier
      ..issueDate = issueDate
      ..expirationDate = expirationDate
      ..clientID = client.id;
  }
}

class _ManagedAuthCode {
  @ManagedColumnAttributes(primaryKey: true)
  String code;

  @ManagedColumnAttributes(indexed: true)
  int resourceOwnerIdentifier;
  DateTime issueDate;
  DateTime expirationDate;

  ManagedToken token;

  @ManagedRelationship(#authCodes, onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: true)
  ManagedClient client;

  // String requestedScopeStorage;
}

abstract class AuthenticatableManagedObject implements Authenticatable, ManagedObject {}

class ManagedAuthStorage<T extends AuthenticatableManagedObject> implements AuthStorage {
  ManagedAuthStorage(this.context);

  ManagedContext context;

  Future<AuthToken> fetchTokenWithAccessToken(AuthServer server, String accessToken) async {
    var query = new Query<ManagedToken>(context)
        ..matchOn.accessToken = accessToken;
    var token = await query.fetchOne();

    return token?.asToken();
  }

  Future<AuthToken> fetchTokenWithRefreshToken(AuthServer server, String refreshToken) async {
    var query = new Query<ManagedToken>(context)
      ..matchOn.refreshToken = refreshToken;
    var token = await query.fetchOne();

    return token?.asToken();
  }

  Future<T> fetchResourceOwnerWithUsername(
      AuthServer server, String username) async {
    var query = new Query<T>(context)
        ..matchOn.username = username;

    return query.fetchOne();
  }

  Future revokeTokenWithIdentifier(AuthServer server, dynamic identifier) async {
    var query = new Query<ManagedToken>(context)
      ..matchOn.id = identifier;

    await query.delete();
  }

  Future<dynamic> storeTokenAndReturnUniqueIdentifier(AuthServer server, AuthToken t) async {
    var storage = new ManagedToken.fromToken(t);
    var query = new Query<ManagedToken>(context)
      ..values = storage;
    var inserted = await query.insert();

    return inserted.id;
  }

  Future updateTokenWithIdentifier(AuthServer server, dynamic identifier, AuthToken t) async {
    var storage = new ManagedToken.fromToken(t);
    var query = new Query<ManagedToken>(context)
      ..matchOn.id = identifier
      ..values = storage;

    await query.updateOne();
  }

  Future storeAuthCode(AuthServer server, AuthCode code) async {
    var storage = new ManagedAuthCode.fromCode(code);
    var query = new Query<ManagedAuthCode>(context)
      ..values = storage;
    await query.insert();
  }

  Future<AuthCode> fetchAuthCodeWithCode(AuthServer server, String code) async {
    var query = new Query<ManagedAuthCode>(context)
        ..matchOn.code = code;

    var storage = await query.fetchOne();
    return storage?.asAuthCode();
  }

  Future associateAuthCodeWithTokenIdentifier(AuthServer server, String code, dynamic tokenIdentifier) async {
    var token = new ManagedToken()..id = tokenIdentifier;
    var query = new Query<ManagedAuthCode>(context)
      ..matchOn.code = code
      ..values.token = token;
    print("${query.valueMap}");

    await query.updateOne();
  }

  Future revokeAuthCodeWithCode(AuthServer server, String code) async {
    var query = new Query<ManagedAuthCode>(context)
      ..matchOn.code = code;

    await query.delete();
  }

  Future<AuthClient> fetchClientWithID(AuthServer server, String id) async {
    var query = new Query<ManagedClient>(context)
      ..matchOn.id = id;

    var storage = await query.fetchOne();

    return storage?.asClient();
  }

  Future revokeClientWithID(AuthServer server, String id) async {
    var query = new Query<ManagedClient>(context)
      ..matchOn.id = id;

    await query.delete();
  }
}