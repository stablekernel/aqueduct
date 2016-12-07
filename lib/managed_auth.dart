import 'dart:async';

import 'package:aqueduct/aqueduct.dart';

class ManagedToken extends ManagedObject<_ManagedToken> implements _ManagedToken {
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
  @managedPrimaryKey
  String accessToken;

  @ManagedColumnAttributes(indexed: true, nullable: true, unique: true)
  String refreshToken;

  DateTime expirationDate;

  @ManagedColumnAttributes(indexed: true)
  int resourceOwnerIdentifier;

  String scopeStorage;

  // Add Client
  // Type is unnecessary, but must set as bearer
}

class ManagedClient extends ManagedObject<_ManagedClient> implements _ManagedClient {}
class _ManagedClient {

}

class ManagedAuthStorage<T extends Authenticatable> implements AuthStorage {
  ManagedAuthStorage(this.context);

  ManagedContext context;

  Future<AuthToken> fetchTokenWithAccessToken(AuthServer server, String accessToken) async {

  }

  Future<AuthToken> fetchTokenWithRefreshToken(AuthServer server, String refreshToken) async {

  }

  Future<T> fetchResourceOwnerWithUsername(
      AuthServer server, String username) async {

  }

  Future revokeTokenWithAccessToken(AuthServer server, String accessToken) async {

  }

  Future<AuthToken> storeToken(AuthServer server, AuthToken t) async {

  }

  Future<AuthToken> updateTokenWithAccessToken(AuthServer server, String accessToken, AuthToken t) async {

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