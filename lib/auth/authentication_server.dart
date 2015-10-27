part of monadart;


class AuthenticationServer<ResourceOwner extends Authenticatable, TokenType extends Tokenizable> {
  AuthenticationServerDelegate<ResourceOwner, TokenType> delegate;

  AuthenticationServer(this.delegate) {
  }

  Authenticator authenticator({List<String> strategies: const [Authenticator.StrategyResourceOwner]}) {
    return new Authenticator(this, strategies);
  }

  bool isTokenExpired(TokenType t) {
    return t.expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }

  Future<Client> clientForID(String id) async {
    return delegate.clientForID(this, id);
  }

  Future<Permission> verify(String accessToken) async {
    TokenType t = await delegate.tokenForAccessToken(this, accessToken);
    if (isTokenExpired(t)) {
      throw new AuthenticationServerException("Expired token", 401);
    }

    var permission = new Permission(t.clientID, t.resourceOwnerIdentifier, this);

    return permission;
  }

  Future<ResourceOwner> resourceOwnerForAccessToken(String accessToken) async {
    var p = await verify(accessToken);

    return await delegate.authenticatableForID(this, p.resourceOwnerIdentifier);
  }

  TokenType generateToken(dynamic ownerID, String clientID, int expirationInSeconds) {
    TokenType token = (reflectType(TokenType) as ClassMirror).newInstance(new Symbol(""), []).reflectee;
    token.accessToken = randomStringOfLength(256);
    token.refreshToken = randomStringOfLength(256);
    token.issueDate = new DateTime.now().toUtc();
    token.expirationDate = token.issueDate.add(new Duration(seconds: expirationInSeconds)).toUtc();
    token.type = "bearer";
    token.resourceOwnerIdentifier = ownerID;
    token.clientID = clientID;

    return token;
  }

  Future<TokenType> refresh(String refreshToken, String clientID, String clientSecret) async {
    Client client = await delegate.clientForID(this, clientID);
    if (client == null) {
      throw new AuthenticationServerException("Invalid client_id", 401);
    }
    if (client.hashedSecret != generatePasswordHash(clientSecret, client.salt)) {
      throw new AuthenticationServerException("Invalid client_secret", 401);
    }

    TokenType t = await delegate.tokenForRefreshToken(this, refreshToken);
    if(t.clientID != clientID) {
      throw new AuthenticationServerException("Invalid client_id for token", 401);
    }

    await delegate.deleteTokenForAccessToken(this, t.accessToken);

    var diff = t.expirationDate.difference(t.issueDate);
    var newToken = generateToken(t.resourceOwnerIdentifier, t.clientID, diff.inSeconds);
    await delegate.storeToken(this, newToken);

    return newToken;
  }

  Future<TokenType> authenticate(String username, String password, String clientID, String clientSecret, {int expirationInSeconds: 3600}) async {
    Client client = await delegate.clientForID(this, clientID);
    if (client == null) {
      throw new AuthenticationServerException("Invalid client_id", 401);
    }
    if (client.hashedSecret != generatePasswordHash(clientSecret, client.salt)) {
      throw new AuthenticationServerException("Invalid client_secret", 401);
    }

    var authenticatable = await delegate.authenticatableForUsername(this, username);
    if (authenticatable == null) {
      throw new AuthenticationServerException("Invalid username", 400);
    }

    var dbSalt = authenticatable.salt;
    var dbPassword = authenticatable.hashedPassword;

    var hash = AuthenticationServer.generatePasswordHash(password, dbSalt);
    if (hash != dbPassword) {
      throw new AuthenticationServerException("Invalid password", 401);
    }

    TokenType token = generateToken(authenticatable.id, client.id, expirationInSeconds);

    await delegate.storeToken(this, token);

    await delegate.pruneTokensForResourceOwnerID(this, authenticatable.id);

    return token;
  }

  static String generatePasswordHash(String password, String salt, {int hashRounds: 1000, int hashLength: 32}) {
    var generator = new PBKDF2(hash: new SHA256());
    var key = generator.generateKey(password, salt, hashRounds, hashLength);

    return CryptoUtils.bytesToBase64(key);
  }

  static String generateRandomSalt({int hashLength: 32}) {
    var random = new Random(new DateTime.now().millisecondsSinceEpoch);
    List<int> salt = [];
    for (var i = 0; i < hashLength; i++) {
      salt.add(random.nextInt(256));
    }

    return CryptoUtils.bytesToBase64(salt);
  }
}

class AuthenticationServerException implements Exception {
  String message;
  int suggestedHTTPStatusCode;

  AuthenticationServerException(this.message, this.suggestedHTTPStatusCode);
}