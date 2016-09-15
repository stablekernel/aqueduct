part of wildfire;

class AuthCode extends Model<_AuthCode> implements _AuthCode {}
class _AuthCode implements TokenExchangable<Token> {
  @primaryKey
  int id;

  @AttributeHint(indexed: true)
  String code;

  @AttributeHint(nullable: true)
  String redirectURI;

  String clientID;
  int resourceOwnerIdentifier;
  DateTime issueDate;
  DateTime expirationDate;

  @RelationshipInverse(#code, isRequired: false, onDelete: RelationshipDeleteRule.cascade)
  Token token;
}

class Token extends Model<_Token> implements _Token, Tokenizable<int> {
  String get clientID => client.id;
  void set clientID(cid) {
    client = new ClientRecord()..id = cid;
  }

  int get resourceOwnerIdentifier => owner.id;
  void set resourceOwnerIdentifier(roid) {
    owner = new User()..id = roid;
  }
}
class _Token {
  @AttributeHint(primaryKey: true)
  String accessToken;

  @AttributeHint(indexed: true)
  String refreshToken;

  @RelationshipInverse(#tokens, onDelete: RelationshipDeleteRule.cascade)
  ClientRecord client;

  @RelationshipInverse(#tokens, onDelete: RelationshipDeleteRule.cascade)
  User owner;

  AuthCode code;

  DateTime issueDate;
  DateTime expirationDate;
  String type;
}

class ClientRecord extends Model<_Client> implements _Client {}
class _Client {
  @AttributeHint(primaryKey: true)
  String id;

  OrderedSet<Token> tokens;

  String hashedPassword;
  String salt;
}
