part of monadart;

class Authenticator extends RequestHandler {
  static const String StrategyResourceOwner = "StrategyResourceOwner";
  static const String StrategyClient = "StrategyClient";
  static const String StrategyOptionalResourceOwner = "StrategyOptionalResourceOwner";

  static const String PermissionKey = "PermissionKey";
  AuthenticationServer server;
  List<String> strategies;

  Authenticator(this.server, this.strategies);

  @override
  Future<RequestHandlerResult> processRequest(ResourceRequest req) async {
    var errorResponse = null;
    for (var strategy in strategies) {
      if (strategy == Authenticator.StrategyResourceOwner) {
        var result = processResourceOwnerRequest(req);
        if (result is ResourceRequest) {
          return result;
        }

        errorResponse = result;
      } else if (strategy == Authenticator.StrategyClient) {
        var result = processClientRequest(req);
        if (result is ResourceRequest) {
          return result;
        }

        errorResponse = result;
      } else if (strategy == Authenticator.StrategyOptionalResourceOwner) {
        var result = processOptionalResourceOwne(req);
        if (result is ResourceRequest) {
          return result;
        }
        errorResponse = result;
      }
    }

    if (errorResponse == null) {
      errorResponse = new Response.serverError();
    }

    return errorResponse;
  }

  Future<RequestHandlerResult> processResourceOwnerRequest(ResourceRequest req) async {
    var parser = new AuthorizationBearerParser(req.innerRequest.headers[HttpHeaders.AUTHORIZATION]?.first);
    if(parser.errorResponse != null) {
      return parser.errorResponse;
    }

    try {
      var permission = await server.verify(parser.bearerToken);
      req.context[PermissionKey] = permission;
      return req;
    } catch (e) {
      return new Response(e.suggestedHTTPStatusCode, null, {"error" : e.message});
    }
  }

  Future<RequestHandlerResult> processClientRequest(ResourceRequest req) async {
    var parser = new AuthorizationBasicParser(req.innerRequest.headers[HttpHeaders.AUTHORIZATION]?.first);
    if (parser.errorResponse != null) {
      return parser.errorResponse;
    }

    var client = await server.delegate.clientForID(parser.username);
    if (client == null) {
      return new Response.unauthorized();
    }

    if (client.hashedSecret != AuthenticationServer.generatePasswordHash(parser.password, client.salt)) {
      return new Response.unauthorized();
    }

    var perm = new Permission(client.id, null, server);
    req.context[PermissionKey] = perm;

    return req;
  }

  Future<RequestHandlerResult> processOptionalResourceOwne(ResourceRequest req) async {
    var authHeader = req.innerRequest.headers[HttpHeaders.AUTHORIZATION]?.first;
    if (authHeader == null) {
      return req;
    }

    return processResourceOwnerRequest(req);
  }
}

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

  Future<Permission> verify(String accessToken) async {
    TokenType t = await delegate.tokenForAccessToken(accessToken);
    if (isTokenExpired(t)) {
      throw new AuthenticationServerException("Expired token", 401);
    }

    var permission = new Permission(t.clientID, t.resourceOwnerIdentifier, this);

    return permission;
  }

  Future<ResourceOwner> resourceOwnerForAccessToken(String accessToken) async {
    var p = await verify(accessToken);

    return await delegate.authenticatableForID(p.resourceOwnerIdentifier);
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
    Client client = await delegate.clientForID(clientID);
    if (client == null) {
      throw new AuthenticationServerException("Invalid client_id", 401);
    }
    if (client.hashedSecret != generatePasswordHash(clientSecret, client.salt)) {
      throw new AuthenticationServerException("Invalid client_secret", 401);
    }

    TokenType t = await delegate.tokenForRefreshToken(refreshToken);
    if(t.clientID != clientID) {
      throw new AuthenticationServerException("Invalid client_id for token", 401);
    }

    await delegate.deleteTokenForAccessToken(t.accessToken);

    var diff = t.expirationDate.difference(t.issueDate);
    var newToken = generateToken(t.resourceOwnerIdentifier, t.clientID, diff.inSeconds);
    await delegate.storeToken(newToken);

    return newToken;
  }

  Future<TokenType> authenticate(String username, String password, String clientID, String clientSecret, {int expirationInSeconds: 3600}) async {
    Client client = await delegate.clientForID(clientID);
    if (client == null) {
      throw new AuthenticationServerException("Invalid client_id", 401);
    }
    if (client.hashedSecret != generatePasswordHash(clientSecret, client.salt)) {
      throw new AuthenticationServerException("Invalid client_secret", 401);
    }

    var authenticatable = await delegate.authenticatableForUsername(username);
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

    await delegate.storeToken(token);

    await delegate.pruneTokensForResourceOwnerID(authenticatable.id);

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