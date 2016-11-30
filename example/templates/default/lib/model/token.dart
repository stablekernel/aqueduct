import '../wildfire.dart';

class AuthCode extends ManagedObject<_AuthCode> implements _AuthCode {}

class _AuthCode implements AuthTokenExchangable<Token> {
  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(indexed: true)
  String code;

  @ManagedColumnAttributes(nullable: true)
  String redirectURI;

  String clientID;
  int resourceOwnerIdentifier;
  DateTime issueDate;
  DateTime expirationDate;

  @ManagedRelationship(#code,
      isRequired: false, onDelete: ManagedRelationshipDeleteRule.cascade)
  Token token;
}

class Token extends ManagedObject<_Token>
    implements _Token, AuthTokenizable<int> {
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
  @ManagedColumnAttributes(primaryKey: true)
  String accessToken;

  @ManagedColumnAttributes(indexed: true, nullable: true)
  String refreshToken;

  @ManagedRelationship(#tokens, onDelete: ManagedRelationshipDeleteRule.cascade)
  ClientRecord client;

  @ManagedRelationship(#tokens, onDelete: ManagedRelationshipDeleteRule.cascade)
  User owner;

  AuthCode code;

  DateTime issueDate;
  DateTime expirationDate;
  String type;
}

class ClientRecord extends ManagedObject<_Client> implements _Client {}

class _Client {
  @ManagedColumnAttributes(primaryKey: true)
  String id;

  ManagedSet<Token> tokens;

  String hashedPassword;
  String salt;
}
