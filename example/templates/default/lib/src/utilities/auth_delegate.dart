part of wildfire;

class WildfireAuthenticationDelegate implements AuthenticationServerDelegate<User, Token, AuthCode> {
  Future<Client> clientForID(AuthenticationServer server, String id) async {
    var clientQ = new Query<ClientRecord>()
      ..id = id;

    var clientRecord = await clientQ.fetchOne();
    if (clientRecord == null) {
      return null;
    }

    return new Client(clientRecord.id, clientRecord.hashedPassword, clientRecord.salt);
  }

  Future deleteTokenForRefreshToken(AuthenticationServer server, String refreshToken) async {
    var q = new Query<Token>();
    q.predicate = new Predicate("refreshToken = @rf", {"rf" : refreshToken});
    await q.delete();
  }

  Future updateToken(AuthenticationServer server, Token t) async {
    var tokenQ = new Query<Token>();
    tokenQ.predicate = new Predicate("refreshToken = @refreshToken", {"refreshToken" : t.refreshToken});
    tokenQ.values = t;
    return tokenQ.updateOne();
  }

  Future<Token> tokenForAccessToken(AuthenticationServer server, String accessToken) {
    var tokenQ = new Query<Token>()
      ..accessToken = accessToken;

    return tokenQ.fetchOne();
  }

  Future<Token> tokenForRefreshToken(AuthenticationServer server, String refreshToken) {
    var tokenQ = new Query<Token>()
      ..refreshToken = refreshToken;

    return tokenQ.fetchOne();
  }

  Future<User> authenticatableForUsername(AuthenticationServer server, String username) async {
    var userQ = new Query<User>()
      ..email = username
      ..resultProperties= ["email", "hashedPassword", "salt", "id"];

    return await userQ.fetchOne();
  }

  Future<User> authenticatableForID(AuthenticationServer server, dynamic id) async {
    var userQ = new Query<User>()
      ..id = id
      ..resultProperties = ["email", "hashedPassword", "salt", "id"];

    return await userQ.fetchOne();
  }

  Future deleteTokenForAccessToken(AuthenticationServer server, String accessToken) async {
    var q = new Query<Token>()
      ..accessToken = accessToken;

    await q.delete();
  }

  Future<Token> storeToken(AuthenticationServer server, Token t) async {
    var tokenQ = new Query<Token>();
    tokenQ.values = t;

    var insertedToken = await tokenQ.insert();

    pruneResourceOwnerTokensAfterIssuingToken(t).catchError((e) {
      new Logger("aqueduct").severe("Failed to prune tokens $e");
    });

    return insertedToken;
  }

  Future<AuthCode> storeAuthCode(AuthenticationServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.values = code;
    return authCodeQ.insert();
  }

  Future<AuthCode> authCodeForCode(AuthenticationServer server, String code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.predicate = new Predicate("code = @code", {"code" : code});
    return authCodeQ.fetchOne();
  }

  Future updateAuthCode(AuthenticationServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.predicate = new Predicate("id = @id", {"id" : code.id});
    authCodeQ.values = code;
    return authCodeQ.updateOne();
  }

  Future deleteAuthCode(AuthenticationServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.predicate = new Predicate("id = @id", {"id" : code.id});
    return authCodeQ.delete();
  }

  Future pruneResourceOwnerTokensAfterIssuingToken(Token t, {int count: 25}) async {
    var tokenQ = new Query<Token>()
      ..owner = whereRelatedByValue(t.owner.id)
      ..client = whereRelatedByValue(t.client.id)
      ..sortDescriptors = [new SortDescriptor("issueDate", SortDescriptorOrder.descending)]
      ..offset = 24
      ..fetchLimit = 1
      ..resultProperties = ["issueDate"];

    var results = await tokenQ.fetch();
    if (results.length == 1) {
      var deleteQ = new Query<Token>()
        ..owner = whereRelatedByValue(t.owner.id)
        ..client = whereRelatedByValue(t.client.id)
        ..issueDate = whereLessThan(results.first.issueDate);

      await deleteQ.delete();
    }
  }
}