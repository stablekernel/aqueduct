part of monadart;

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

abstract class Authenticatable extends Object {
  String username;
  String hashedPassword;
  String salt;
  dynamic id;
}

abstract class AuthenticationServerDelegate<ResourceOwner extends Authenticatable, TokenType extends Tokenizable> {
  Future<TokenType> tokenForAccessToken(String accessToken);
  Future<TokenType> tokenForRefreshToken(String refreshToken);
  Future<ResourceOwner> authenticatableForUsername(String username);
  Future<ResourceOwner> authenticatableForID(dynamic id);

  Future deleteTokenForAccessToken(String accessToken);

  Future storeToken(TokenType t);

  Future pruneTokensForResourceOwnerID(dynamic id);
}