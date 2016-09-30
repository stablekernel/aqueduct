part of aqueduct;

/// A storage-agnostic authenticating mechanism.
///
/// Instances of this type will work with a [AuthenticationServerDelegate] to faciliate authentication.
class AuthenticationServer<ResourceOwner extends Authenticatable, TokenType extends Tokenizable, AuthCodeType extends TokenExchangable<TokenType>> extends Object with APIDocumentable {
  /// Creates a new instance of an [AuthenticationServer] with a [delegate].
  AuthenticationServer(this.delegate);

  /// The object responsible for carrying out the storage mechanisms of this [AuthenticationServer].
  ///
  /// An [AuthenticationServerDelegate] implementation is responsible for storing, fetching and deleting
  /// [TokenType]s and [ResourceOwners]. The [AuthenticationServer] will handle the logic of how
  /// these objects are used to verify authentication.
  AuthenticationServerDelegate<ResourceOwner, TokenType, AuthCodeType> delegate;
  Map<String, Client> _clientCache = {};

  /// Returns a new instance of [Authenticator] for use in a [RequestController] chain.
  ///
  /// These instances will be used in a [RequestController] chain to authenticate an incoming [Request]
  /// against this [AuthenticationServer]. The [strategy] indicates whether the [Request] is
  /// evaluated for client credentials in a Basic Authorization scheme or for a token in a Bearer Authorization
  /// scheme.
  Authenticator newAuthenticator({AuthenticationStrategy strategy: AuthenticationStrategy.ResourceOwner}) {
    return new Authenticator(this, strategy);
  }

  /// Returns whether or not a token from this server has expired.
  bool isTokenExpired(TokenType t) {
    return t.expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }

  bool isAuthCodeExpired(AuthCodeType ac) {
    return ac.expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }

  /// Returns a [Client] record for an [id].
  ///
  /// A server keeps a cache of known [Client]s. If a client does not exist in the cache,
  /// it will ask its [delegate] via [clientForID].
  Future<Client> clientForID(String id) async {
    Client client = _clientCache[id] ?? (await delegate.clientForID(this, id));

    _clientCache[id] = client;

    return client;
  }

  /// Revokes a [Client] record.
  ///
  /// NYI. Currently, just removes a [Client] from the cache.
  void revokeClient(String clientID) {
    _clientCache.remove(clientID);

    // TODO: Call delegate method to revoke client from persistent storage.
  }

  /// Returns a [Permission] for the specified [accessToken].
  ///
  /// This method obtains a [TokenType] from the [delegate] and then verifies if that token is valid.
  /// If the token is valid, a [Permission] object is returned. Otherwise, an [HTTPResponseException]
  /// with status code 401 is returned.
  Future<Permission> verify(String accessToken) async {
    TokenType t = await delegate.tokenForAccessToken(this, accessToken);
    if (t == null || isTokenExpired(t)) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Expired token");
    }

    var permission = new Permission(t.clientID, t.resourceOwnerIdentifier, this);

    return permission;
  }

  /// Returns a [ResourceOwner] for the specified [accessToken].
  ///
  /// This method will verify that the access token is valid, and return the [ResourceOwner]
  /// for that token.
  Future<ResourceOwner> resourceOwnerForAccessToken(String accessToken) async {
    var p = await verify(accessToken);

    return await delegate.authenticatableForID(this, p.resourceOwnerIdentifier);
  }

  /// Instantiates a [TokenType] given the arguments.
  ///
  /// This method creates an instance of a [TokenType] given an [ownerID], [clientID] and [expirationInSeconds].
  /// The token is not stored in this method.
  TokenType generateToken(dynamic ownerID, String clientID, int expirationInSeconds) {
    TokenType token = (reflectType(TokenType) as ClassMirror).newInstance(new Symbol(""), []).reflectee as TokenType;
    token.accessToken = randomStringOfLength(32);
    token.refreshToken = randomStringOfLength(32);
    token.issueDate = new DateTime.now().toUtc();
    token.expirationDate = token.issueDate.add(new Duration(seconds: expirationInSeconds)).toUtc();
    token.type = "bearer";
    token.resourceOwnerIdentifier = ownerID;
    token.clientID = clientID;

    return token;
  }

  /// Returns a [Permission] for the specified [code].
  ///
  /// This method obtains a [AuthCodeType] from the [delegate] and then verifies
  /// if that authorization code is valid. If the token is valid, a [Permission]
  /// object is returned. Otherwise, an [HTTPResponseException] with status code 401 is returned.
  Future<Permission> verifyCode(String code) async {
    AuthCodeType ac = await delegate.authCodeForCode(this, code);
    if (ac == null || isAuthCodeExpired(ac)) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Expired authorization code");
    }

    return new Permission(ac.clientID, ac.resourceOwnerIdentifier, this);
  }

  /// Instantiates a [AuthCodeType] given the arguments.
  ///
  /// This method creates an instance of [AuthCodeType] given an [ownerId], [client], and [expirationInSeconds].
  /// The authorization code is not stored in this method.
  AuthCodeType generateAuthCode(dynamic ownerID, Client client, int expirationInSeconds) {
    AuthCodeType authCode = (reflectType(AuthCodeType) as ClassMirror).newInstance(new Symbol(""), []).reflectee as AuthCodeType;

    authCode.code = randomStringOfLength(32);
    authCode.clientID = client.id;
    authCode.resourceOwnerIdentifier = ownerID;
    authCode.issueDate = new DateTime.now().toUtc();
    authCode.expirationDate = authCode.issueDate.add(new Duration(seconds: expirationInSeconds)).toUtc();
    authCode.redirectURI = client.redirectURI;

    return authCode;
  }

  /// Refreshes a valid [TokenType].
  ///
  /// This method will refresh a [TokenType] given the [TokenType]'s [refreshToken] for a given client ID if the client secret matches according
  /// to the [delegate]. It coordinates with the [delegate] to delete the old token and store the new one if successful. If not successful,
  /// it will throw the appropriate [HTTPResponseException].
  Future<TokenType> refresh(String refreshToken, String clientID, String clientSecret) async {
    Client client = await clientForID(clientID);
    if (client == null) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid client_id");
    }
    if (client.hashedSecret != generatePasswordHash(clientSecret, client.salt)) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid client_secret");
    }

    TokenType t = await delegate.tokenForRefreshToken(this, refreshToken);
    if (t == null || t.clientID != clientID) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid client_id for token");
    }

    var diff = t.expirationDate.difference(t.issueDate);
    t.accessToken = randomStringOfLength(32);
    t.issueDate = new DateTime.now().toUtc();
    t.expirationDate = t.issueDate.add(new Duration(seconds: diff.inSeconds)).toUtc();

    return delegate.updateToken(this, t);
  }

  /// Authenticates a resource owner for a given client ID.
  ///
  /// This method works with the [delegate] to generate and store a new token if all credentials are correct.
  /// If credentials are not correct, it will throw the appropriate [HTTPResponseException].
  Future<TokenType> authenticate(String username, String password, String clientID, String clientSecret, {int expirationInSeconds: 3600}) async {
    Client client = await clientForID(clientID);
    if (client == null) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid client_id");
    }
    if (client.hashedSecret != generatePasswordHash(clientSecret, client.salt)) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid client_secret");
    }

    var authenticatable = await delegate.authenticatableForUsername(this, username);
    if (authenticatable == null) {
      throw new HTTPResponseException(HttpStatus.BAD_REQUEST, "Invalid username");
    }

    var dbSalt = authenticatable.salt;
    var dbPassword = authenticatable.hashedPassword;
    var hash = AuthenticationServer.generatePasswordHash(password, dbSalt);
    if (hash != dbPassword) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid password");
    }

    TokenType token = generateToken(authenticatable.id, client.id, expirationInSeconds);
    await delegate.storeToken(this, token);

    return token;
  }

  /// Creates a one-time use authorization code for a given client ID and user credentials.
  ///
  /// This methods works with the [delegate] to generate and store the authorization code
  /// if the credentials are correct. If they are not correct, it will throw the
  /// appropriate [HTTPResponseException].
  Future<AuthCodeType> createAuthCode(String username, String password, String clientID, {int expirationInSeconds: 600}) async {
    Client client = await clientForID(clientID);
    if (client == null) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid client_id");
    }

    if (client.redirectURI == null) {
      throw new HTTPResponseException(HttpStatus.INTERNAL_SERVER_ERROR, "Client does not have a redirect URI");
    }

    var authenticatable = await delegate.authenticatableForUsername(this, username);
    if (authenticatable == null) {
      throw new HTTPResponseException(HttpStatus.BAD_REQUEST, "Invalid username");
    }

    var dbSalt = authenticatable.salt;
    var dbPassword = authenticatable.hashedPassword;
    var hash = AuthenticationServer.generatePasswordHash(password, dbSalt);
    if (hash != dbPassword) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid password");
    }

    AuthCodeType authCode = generateAuthCode(authenticatable.id, client, expirationInSeconds);
    return await delegate.storeAuthCode(this, authCode);
  }

  /// Exchanges a valid authorization code for a pair of refresh and access tokens.
  ///
  /// If the authorization code has not expired, has not been used, matches the client ID,
  /// and the client secret is correct, it will return a valid pair of tokens. Otherwise,
  /// it will throw an appropriate [HTTPResponseException].
  Future<TokenType> exchange(String authCodeString, String clientID, String clientSecret, {int expirationInSeconds: 3600}) async {
    Client client = await clientForID(clientID);
    if (client == null) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid client_id");
    }
    if (client.hashedSecret != generatePasswordHash(clientSecret, client.salt)) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid client_secret");
    }

    AuthCodeType authCode = await delegate.authCodeForCode(this, authCodeString);
    if (authCode == null) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid code");
    }

    // check if valid still
    if (authCode.expirationDate.difference(new DateTime.now()).inSeconds <= 0) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Authorization code has expired");
    }

    // check that client ids match
    if (authCode.clientID != client.id) {
      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Invalid client_id for authorization code");
    }

    // check to see if has already been used
    if (authCode.token != null) {
      await delegate.deleteTokenForRefreshToken(this, authCode.token.refreshToken);

      throw new HTTPResponseException(HttpStatus.UNAUTHORIZED, "Authorization code has already been used");
    }

    TokenType token = generateToken(authCode.resourceOwnerIdentifier, client.id, expirationInSeconds);
    token = await delegate.storeToken(this, token);

    authCode.token = token;
    await delegate.updateAuthCode(this, authCode);

    return token;
  }


  @override
  Map<String, APISecurityScheme> documentSecuritySchemes(PackagePathResolver resolver) {
    var secApp = new APISecurityScheme.oauth2()
      ..description = "OAuth 2.0 Application Flow"
      ..oauthFlow = APISecuritySchemeFlow.application;
    var secPassword = new APISecurityScheme.oauth2()
      ..description = "OAuth 2.0 Resource Owner Flow"
      ..oauthFlow = APISecuritySchemeFlow.password;

    return {
      "oauth2.application" : secApp,
      "oauth2.password" : secPassword
    };
  }

  /// A utility method to generate a password hash using the PBKDF2 scheme.
  static String generatePasswordHash(String password, String salt, {int hashRounds: 1000, int hashLength: 32}) {
    var generator = new PBKDF2(hashFunction: sha256);
    var key = generator.generateKey(password, salt, hashRounds, hashLength);

    return new Base64Encoder().convert(key);
  }

  /// A utility method to generate a random base64 salt.
  static String generateRandomSalt({int hashLength: 32}) {
    var random = new Random(new DateTime.now().millisecondsSinceEpoch);
    List<int> salt = [];
    for (var i = 0; i < hashLength; i++) {
      salt.add(random.nextInt(256));
    }

    return new Base64Encoder().convert(salt);
  }
}
