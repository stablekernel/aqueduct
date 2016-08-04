part of aqueduct;

/// A storage-agnostic authenticating mechanism.
///
/// Instances of this type will work with a [AuthenticationServerDelegate] to faciliate authentication.
class AuthenticationServer<ResourceOwner extends Authenticatable, TokenType extends Tokenizable> extends Object with APIDocumentable {
  /// Creates a new instance of an [AuthenticationServer] with a [delegate].
  AuthenticationServer(this.delegate);

  /// The object responsible for carrying out the storage mechanisms of this [AuthenticationServer].
  ///
  /// An [AuthenticationServerDelegate] implementation is responsible for storing, fetching and deleting
  /// [TokenType]s and [ResourceOwners]. The [AuthenticationServer] will handle the logic of how
  /// these objects are used to verify authentication.
  AuthenticationServerDelegate<ResourceOwner, TokenType> delegate;
  Map<String, Client> _clientCache = {};

  /// Returns a new instance of [Authenticator] for use in a [RequestHandler] chain.
  ///
  /// These instances will be used in a [RequestHandler] chain to authenticate an incoming [Request]
  /// against this [AuthenticationServer]. The [strategy] indicates whether the [Request] is
  /// evaluated for client credentials in a Basic Authorization scheme or for a token in a Bearer Authorization
  /// scheme.
  Authenticator authenticator({AuthenticationStrategy strategy: AuthenticationStrategy.ResourceOwner}) {
    return new Authenticator(this, strategy);
  }

  /// Returns whether or not a token from this server has expired.
  bool isTokenExpired(TokenType t) {
    return t.expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
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
      throw new HTTPResponseException(401, "Expired token");
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
    TokenType token = (reflectType(TokenType) as ClassMirror).newInstance(new Symbol(""), []).reflectee;
    token.accessToken = randomStringOfLength(32);
    token.refreshToken = randomStringOfLength(32);
    token.issueDate = new DateTime.now().toUtc();
    token.expirationDate = token.issueDate.add(new Duration(seconds: expirationInSeconds)).toUtc();
    token.type = "bearer";
    token.resourceOwnerIdentifier = ownerID;
    token.clientID = clientID;

    return token;
  }

  /// Refreshes a valid [TokenType].
  ///
  /// This method will refresh a [TokenType] given the [TokenType]'s [refreshToken] for a given client ID if the client secret matches according
  /// to the [delegate]. It coordinates with the [delegate] to delete the old token and store the new one if successful. If not successful,
  /// it will throw the appropriate [HTTPResponseException].
  Future<TokenType> refresh(String refreshToken, String clientID, String clientSecret) async {
    Client client = await clientForID(clientID);
    if (client == null) {
      throw new HTTPResponseException(401, "Invalid client_id");
    }
    if (client.hashedSecret != generatePasswordHash(clientSecret, client.salt)) {
      throw new HTTPResponseException(401, "Invalid client_secret");
    }

    TokenType t = await delegate.tokenForRefreshToken(this, refreshToken);
    if (t == null || t.clientID != clientID) {
      throw new HTTPResponseException(401, "Invalid client_id for token");
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
      throw new HTTPResponseException(401, "Invalid client_id");
    }
    if (client.hashedSecret != generatePasswordHash(clientSecret, client.salt)) {
      throw new HTTPResponseException(401, "Invalid client_secret");
    }

    var authenticatable = await delegate.authenticatableForUsername(this, username);
    if (authenticatable == null) {
      throw new HTTPResponseException(400, "Invalid username");
    }

    var dbSalt = authenticatable.salt;
    var dbPassword = authenticatable.hashedPassword;
    var hash = AuthenticationServer.generatePasswordHash(password, dbSalt);
    if (hash != dbPassword) {
      throw new HTTPResponseException(401, "Invalid password");
    }

    TokenType token = generateToken(authenticatable.id, client.id, expirationInSeconds);
    await delegate.storeToken(this, token);

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

  /// A utility method to generate am password hash using the PBKDF2 scheme.
  static String generatePasswordHash(String password, String salt, {int hashRounds: 1000, int hashLength: 32}) {
    var generator = new PBKDF2(hash: sha256);
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
