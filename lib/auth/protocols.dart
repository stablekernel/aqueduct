part of aqueduct;

abstract class Tokenizable {
  String accessToken;
  String refreshToken;
  DateTime issueDate;
  DateTime expirationDate;
  String type;
  dynamic resourceOwnerIdentifier;
  String clientID;
}

class Permission {
  final String clientID;
  final dynamic resourceOwnerIdentifier;
  final AuthenticationServer grantingServer;

  const Permission(this.clientID, this.resourceOwnerIdentifier, this.grantingServer);
}

abstract class Authenticatable {
  String username;
  String hashedPassword;
  String salt;
  dynamic id;
}

abstract class AuthenticationServerDelegate<ResourceOwner extends Authenticatable, TokenType extends Tokenizable> {
  Future<TokenType> tokenForAccessToken(AuthenticationServer server, String accessToken);
  Future<TokenType> tokenForRefreshToken(AuthenticationServer server, String refreshToken);
  Future<ResourceOwner> authenticatableForUsername(AuthenticationServer server, String username);
  Future<ResourceOwner> authenticatableForID(AuthenticationServer server, dynamic id);

  Future<Client> clientForID(AuthenticationServer server, String id);
  Future deleteTokenForAccessToken(AuthenticationServer server, String accessToken);

  Future storeToken(AuthenticationServer server, TokenType t);
}
