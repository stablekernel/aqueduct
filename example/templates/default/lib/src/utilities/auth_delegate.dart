part of wildfire;

class WildfireAuthenticationDelegate implements AuthServerDelegate<User, Token, AuthCode> {
  Future<AuthClient> clientForID(AuthServer server, String id) async {
    var clientQ = new Query<ClientRecord>()
      ..matchOn.id = id;

    var clientRecord = await clientQ.fetchOne();
    if (clientRecord == null) {
      return null;
    }

    return new AuthClient(clientRecord.id, clientRecord.hashedPassword, clientRecord.salt);
  }

  Future deleteTokenForRefreshToken(AuthServer server, String refreshToken) async {
    var q = new Query<Token>()
      ..matchOn.refreshToken = refreshToken;

    await q.delete();
  }

  Future updateToken(AuthServer server, Token t) async {
    var tokenQ = new Query<Token>()
      ..matchOn.refreshToken = t.refreshToken
      ..values = t;

    return tokenQ.updateOne();
  }

  Future<Token> tokenForAccessToken(AuthServer server, String accessToken) {
    var tokenQ = new Query<Token>()
      ..matchOn.accessToken = accessToken;

    return tokenQ.fetchOne();
  }

  Future<Token> tokenForRefreshToken(AuthServer server, String refreshToken) {
    var tokenQ = new Query<Token>()
      ..matchOn.refreshToken = refreshToken;

    return tokenQ.fetchOne();
  }

  Future<User> authenticatableForUsername(AuthServer server, String username) async {
    var userQ = new Query<User>()
      ..matchOn.email = username
      ..resultProperties = ["email", "hashedPassword", "salt", "id"];

    return await userQ.fetchOne();
  }

  Future<User> authenticatableForID(AuthServer server, dynamic id) async {
    var userQ = new Query<User>()
      ..matchOn.id = id
      ..resultProperties = ["email", "hashedPassword", "salt", "id"];

    return await userQ.fetchOne();
  }

  Future deleteTokenForAccessToken(AuthServer server, String accessToken) async {
    var q = new Query<Token>()
      ..matchOn.accessToken = accessToken;

    await q.delete();
  }

  Future<Token> storeToken(AuthServer server, Token t) async {
    var tokenQ = new Query<Token>();
    tokenQ.values = t;

    var insertedToken = await tokenQ.insert();

    pruneResourceOwnerTokensAfterIssuingToken(t).catchError((e) {
      new Logger("aqueduct").severe("Failed to prune tokens $e");
    });

    return insertedToken;
  }

  Future<AuthCode> storeAuthCode(AuthServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.values = code;
    return authCodeQ.insert();
  }

  Future<AuthCode> authCodeForCode(AuthServer server, String code) async {
    var authCodeQ = new Query<AuthCode>()
      ..matchOn.code = code;

    return authCodeQ.fetchOne();
  }

  Future updateAuthCode(AuthServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>()
      ..matchOn.id = code.id
      ..values = code;

    return authCodeQ.updateOne();
  }

  Future deleteAuthCode(AuthServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>()
      ..matchOn.id = code.id;

    return authCodeQ.delete();
  }

  Future pruneResourceOwnerTokensAfterIssuingToken(Token t, {int count: 25}) async {
    var tokenQ = new Query<Token>()
      ..matchOn.owner = whereRelatedByValue(t.owner.id)
      ..matchOn.client = whereRelatedByValue(t.client.id)
      ..sortDescriptors = [new QuerySortDescriptor("issueDate", QuerySortOrder.descending)]
      ..offset = 24
      ..fetchLimit = 1
      ..resultProperties = ["issueDate"];

    var results = await tokenQ.fetch();
    if (results.length == 1) {
      var deleteQ = new Query<Token>()
        ..matchOn.owner = whereRelatedByValue(t.owner.id)
        ..matchOn.client = whereRelatedByValue(t.client.id)
        ..matchOn.issueDate = whereLessThan(results.first.issueDate);

      await deleteQ.delete();
    }
  }
}