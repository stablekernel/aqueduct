part of wildfire;

class WildfireAuthenticationDelegate implements AuthenticationServerDelegate<User, Token> {
  Future<Client> clientForID(AuthenticationServer server, String id) async {
    var clientQ = new ClientRecordQuery()
      ..id = id;

    var clientRecord = await clientQ.fetchOne();
    if (clientRecord == null) {
      return null;
    }

    return new Client(clientRecord.id, clientRecord.hashedPassword, clientRecord.salt);
  }

  Future<Token> tokenForAccessToken(AuthenticationServer server, String accessToken) {
    var tokenQ = new TokenQuery()
      ..accessToken = accessToken;

    return tokenQ.fetchOne();
  }

  Future<Token> tokenForRefreshToken(AuthenticationServer server, String refreshToken) {
    var tokenQ = new TokenQuery()
      ..refreshToken = refreshToken;

    return tokenQ.fetchOne();
  }

  Future<User> authenticatableForUsername(AuthenticationServer server, String username) async {
    var userQ = new UserQuery()
      ..email = username
      ..resultProperties= ["email", "hashedPassword", "salt", "id"];

    return await userQ.fetchOne();
  }

  Future<User> authenticatableForID(AuthenticationServer server, int id) async {
    var userQ = new UserQuery()
      ..id = id
      ..resultProperties = ["email", "hashedPassword", "salt", "id"];

    return await userQ.fetchOne();
  }

  Future deleteTokenForAccessToken(AuthenticationServer server, String accessToken) async {
    var q = new TokenQuery()
      ..accessToken = accessToken;

    await q.delete();
  }

  Future storeToken(AuthenticationServer server, Token t) async {
    var tokenQ = new Query<Token>();
    tokenQ.values = t;

    await tokenQ.insert();

    pruneResourceOwnerTokensAfterIssuingToken(t).catchError((e) {
      new Logger("aqueduct").severe("Failed to prune tokens $e");
    });
  }

  Future pruneResourceOwnerTokensAfterIssuingToken(Token t, {int count: 25}) async {
    var tokenQ = new TokenQuery()
      ..owner = whereRelatedByValue(t.owner.id)
      ..client = whereRelatedByValue(t.client.id)
      ..sortDescriptors = [new SortDescriptor("issueDate", SortDescriptorOrder.descending)]
      ..offset = 24
      ..fetchLimit = 1
      ..resultProperties = ["issueDate"];

    var results = await tokenQ.fetch();
    if (results.length == 1) {
      var deleteQ = new TokenQuery()
        ..owner = whereRelatedByValue(t.owner.id)
        ..client = whereRelatedByValue(t.client.id)
        ..issueDate = whereLessThan(results.first.issueDate);

      await deleteQ.delete();
    }
  }
}