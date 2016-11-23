

/// Represents a Client ID and secret pair.
class AuthClient {
  /// Creates an instance of [AuthClient].
  AuthClient(this.id, this.hashedSecret, this.salt);

  // Creates an instance of [Client] that uses the authorization code grant flow.
  AuthClient.withRedirectURI(
      this.id, this.hashedSecret, this.salt, this.redirectURI);

  /// The ID of the client.
  String id;

  /// The hashed secret of the client.
  String hashedSecret;

  /// The salt the hashed secret was hashed with.
  String salt;

  /// The redirection URI for authorization codes and/or tokens.
  String redirectURI;
}
