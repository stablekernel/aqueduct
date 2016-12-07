import 'dart:async';

import 'package:aqueduct/aqueduct.dart';

class ManagedToken extends ManagedObject<_ManagedToken> implements _ManagedToken {
  ManagedToken.fromToken(AuthToken t) : super() {
    this
        ..accessToken = t.accessToken
        ..refreshToken = t.refreshToken
        ..issueDate = t.issueDate
        ..expirationDate = t.expirationDate
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
        ..client = (new ManagedClient()..id = t.clientID)
        ..scopes = t.scope;
  }

  AuthToken asToken() {
    return new AuthToken()
        ..accessToken = accessToken
        ..refreshToken = refreshToken
        ..issueDate = issueDate
        ..expirationDate = expirationDate
        ..type = type
        ..resourceOwnerIdentifier = resourceOwnerIdentifier
        ..clientID = client.id
        ..scope = scopes;
  }

  String get type => "bearer";
  List<AuthScope> get scopes {
    return scopeStorage
        ?.split(" ")
        ?.map((each) => new AuthScope(each))
        ?.toList();
  }

  void set scopes(List<AuthScope> s) {
    scopeStorage = s
        .map((scope) => scope.toString())
        .join(" ");
  }
}
class _ManagedToken {
  @ManagedColumnAttributes(primaryKey: true)
  String accessToken;

  @ManagedColumnAttributes(indexed: true, nullable: true, unique: true)
  String refreshToken;

  DateTime issueDate;
  DateTime expirationDate;

  @ManagedColumnAttributes(indexed: true)
  int resourceOwnerIdentifier;

  @ManagedRelationship(#tokens,
      onDelete: ManagedRelationshipDeleteRule.cascade,
      isRequired: true)
  ManagedClient client;

  @ManagedRelationship(#token)
  ManagedAuthCode authCode;

  String scopeStorage;
}

class ManagedClient extends ManagedObject<_ManagedClient> implements _ManagedClient {}
class _ManagedClient {
  @ManagedColumnAttributes(primaryKey: true)
  String id;

  String hashedSecret;
  String salt;

  String redirectURI;

  ManagedSet<ManagedToken> tokens;
}

class ManagedAuthCode extends ManagedObject<_ManagedAuthCode> implements _ManagedAuthCode {}
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
    var query = new Query<ManagedToken>()
        ..matchOn.accessToken = accessToken;
    var token = await query.fetchOne();

    return token?.asToken();
  }

  Future<AuthToken> fetchTokenWithRefreshToken(AuthServer server, String refreshToken) async {
    var query = new Query<ManagedToken>()
      ..matchOn.refreshToken = refreshToken;
    var token = await query.fetchOne();

    return token?.asToken();
  }

  Future<T> fetchResourceOwnerWithUsername(
      AuthServer server, String username) async {
    var query = new Query<T>()
        ..matchOn.username = username;

    return query.fetchOne();
  }

  Future revokeTokenWithAccessToken(AuthServer server, String accessToken) async {
    var query = new Query<ManagedToken>()
      ..matchOn.accessToken = accessToken;

    return query.delete();
  }

  Future storeToken(AuthServer server, AuthToken t) async {
    var storage = new ManagedToken.fromToken(t);
    var query = new Query<ManagedToken>()
      ..values = storage;
    await query.insert();
  }

  Future<AuthToken> updateTokenWithAccessToken(AuthServer server, String accessToken, AuthToken t) async {
    var storage = new ManagedToken.fromToken(t);
    var query = new Query<ManagedToken>()
      ..matchOn
      ..values = storage;
    await query.insert();
  }

  Future<AuthCode> storeAuthCode(AuthServer server, AuthCode code) async {

  }

  Future<AuthCode> fetchAuthCodeWithCode(AuthServer server, String code) async {

  }

  Future updateAuthCodeWithCode(AuthServer server, String code, AuthCode ac) async {

  }

  Future revokeAuthCodeWithCode(AuthServer server, String code) async {

  }

  Future<AuthClient> fetchClientWithID(AuthServer server, String id) async {

  }

  Future revokeClientWithID(AuthServer server, String id) async {

  }
}