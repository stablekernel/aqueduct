import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:postgresql/postgresql.dart' as postgresql;

Future<List<TestUser>> createUsers(int count) async {
  var users = new List<TestUser>();
  for (int i = 0; i < count; i++) {
    var salt = AuthenticationServer.generateRandomSalt();
    var u = new TestUser()
      ..username = "bob+$i@stablekernel.com"
      ..salt = salt
      ..hashedPassword = AuthenticationServer.generatePasswordHash("foobaraxegrind21%", salt);

    var q = new Query<TestUser>()..values = u;
    var insertedUser = await q.insert();
    users.add(insertedUser);
  }
  return users;
}

class TestUser extends Model<_User> implements _User {}
class _User implements Authenticatable {
  @primaryKey
  int id;

  String username;
  String hashedPassword;
  String salt;
}

class Token extends Model<_Token> implements _Token {}
class _Token implements Tokenizable {
  @primaryKey
  int id;

  @Attributes(indexed: true)
  String accessToken;

  @Attributes(indexed: true)
  String refreshToken;

  DateTime issueDate;
  DateTime expirationDate;
  int resourceOwnerIdentifier;
  String type;
  String clientID;

  @Relationship.hasOne("token")
  AuthCode code;

}

class AuthCode extends Model<_AuthCode> implements _AuthCode {}
class _AuthCode implements Authorizer {
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

class AuthDelegate implements AuthenticationServerDelegate<TestUser, Token, AuthCode> {
  ModelContext context;

  AuthDelegate(this.context);

  Future<Token> tokenForAccessToken(AuthenticationServer server, String accessToken) {
    return _tokenForPredicate(new Predicate("accessToken = @accessToken", {"accessToken" : accessToken}));
  }

  Future<Token> tokenForRefreshToken(AuthenticationServer server, String refreshToken) {
    return _tokenForPredicate(new Predicate("refreshToken = @refreshToken", {"refreshToken" : refreshToken}));
  }

  Future<TestUser> authenticatableForUsername(AuthenticationServer server, String username) {
    var userQ = new Query<TestUser>();
    userQ.predicate = new Predicate("username = @username", {"username" : username});
    return userQ.fetchOne();
  }

  Future<TestUser> authenticatableForID(AuthenticationServer server, int id) {
    var userQ = new Query<TestUser>();
    userQ.predicate = new Predicate("username = @username", {"id" : id});
    return userQ.fetchOne();
  }

  Future deleteTokenForRefreshToken(AuthenticationServer server, String refreshToken) async {
    var q = new Query<Token>();
    q.predicate = new Predicate("refreshToken = @rf", {"rf" : refreshToken});
    await q.delete();
  }

  Future<Token> storeToken(AuthenticationServer server, Token t) async {
    var tokenQ = new Query<Token>();
    tokenQ.values = t;
    return await tokenQ.insert();
  }

  Future updateToken(AuthenticationServer server, Token t) async {
    var tokenQ = new Query<Token>();
    tokenQ.predicate = new Predicate("refreshToken = @refreshToken", {"refreshToken" : t.refreshToken});
    tokenQ.values = t;
    return tokenQ.updateOne();
  }

  Future<AuthCode> storeAuthCode(AuthenticationServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.values = code;
    return authCodeQ.insert();
  }

  Future<AuthCode> authCodeForCode(AuthenticationServer server, String code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.predicate = new Predicate("code = @code", {"code" : code});
    return authCodeQ.fetchOne();
  }

  Future updateAuthCode(AuthenticationServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.predicate = new Predicate("id = @id", {"id" : code.id});
    authCodeQ.values = code;
    return authCodeQ.updateOne();
  }

  Future deleteAuthCode(AuthenticationServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.predicate = new Predicate("id = @id", {"id" : code.id});
    return authCodeQ.delete();
  }

  Future<Client> clientForID(AuthenticationServer server, String id) async {
    var salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
    if (id == "com.stablekernel.app1") {
      return new Client("com.stablekernel.app1", AuthenticationServer.generatePasswordHash("kilimanjaro", salt), salt);
    }
    if (id == "com.stablekernel.app2") {
      return new Client("com.stablekernel.app2", AuthenticationServer.generatePasswordHash("fuji", salt), salt);
    }
    if (id == "com.stablekernel.app3") {
      return new Client.withRedirectURI("com.stablekernel.app3", AuthenticationServer.generatePasswordHash("mckinley", salt), salt, "http://stablekernel.com/auth/redirect");
    }

    return null;
  }

  Future<Token> _tokenForPredicate(Predicate p) async {
    var tokenQ = new Query<Token>();
    tokenQ.predicate = p;
    var result = await tokenQ.fetchOne();
    if (result == null) {
      throw new HTTPResponseException(401, "Invalid Token");
    }

    return result;
  }
}

Future<ModelContext> contextWithModels(List<Type> modelTypes) async {
  var persistentStore = new PostgreSQLPersistentStore(() async {
    var uri = "postgres://dart:dart@localhost:5432/dart_test";
    return await postgresql.connect(uri, timeZone: 'UTC');
  });

  var dataModel = new DataModel(modelTypes);
  var generator = new SchemaGenerator(dataModel);
  var json = generator.serialized;
  var pGenerator = new PostgreSQLSchemaGenerator(json, temporary: true);

  var context = new ModelContext(dataModel, persistentStore);
  ModelContext.defaultContext = context;

  for (var cmd in pGenerator.commandList.split(";\n")) {
    await persistentStore.execute(cmd);
  }

  return context;
}

String commandsForModelTypes(List<Type> modelTypes, {bool temporary: false}) {
  var dataModel = new DataModel(modelTypes);
  var generator = new SchemaGenerator(dataModel);
  var json = generator.serialized;
  var pGenerator = new PostgreSQLSchemaGenerator(json, temporary: temporary);

  return pGenerator.commandList;
}