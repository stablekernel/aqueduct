part of wildfire;

class AuthCode extends Model<_AuthCode> implements _AuthCode {}
class _AuthCode implements TokenExchangable<Token> {
  @primaryKey
  int id;

  @Attributes(indexed: true)
  String code;

  @Attributes(nullable: true)
  String redirectURI;

  String clientID;
  int resourceOwnerIdentifier;
  DateTime issueDate;
  DateTime expirationDate;

  @Relationship.belongsTo("code", required: false, deleteRule: RelationshipDeleteRule.cascade)
  Token token;
}


class TokenQuery extends ModelQuery<Token> implements _Token {}
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
  @Attributes(primaryKey: true)
  String accessToken;

  @Attributes(indexed: true)
  String refreshToken;

  @Relationship.belongsTo("tokens", deleteRule: RelationshipDeleteRule.cascade)
  ClientRecord client;

  @Relationship.belongsTo("tokens", deleteRule: RelationshipDeleteRule.cascade)
  User owner;

  @Relationship.hasMany("token")
  AuthCode code;

  DateTime issueDate;
  DateTime expirationDate;
  String type;
}

class ClientRecordQuery extends ModelQuery<ClientRecord> implements _Client {}
class ClientRecord extends Model<_Client> implements _Client {}
class _Client {
  @Attributes(primaryKey: true)
  String id;

  @Relationship.hasMany("client")
  List<Token> tokens;

  String hashedPassword;
  String salt;
}
