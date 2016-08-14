part of wildfire;

class TokenQuery extends ModelQuery<Token> implements _Token {}
class Token extends Model<_Token> implements _Token, Tokenizable {
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
