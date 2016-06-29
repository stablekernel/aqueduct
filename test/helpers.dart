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
}

class AuthDelegate implements AuthenticationServerDelegate<TestUser, Token> {
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

  Future deleteTokenForAccessToken(AuthenticationServer server, String accessToken) async {
    var q = new Query<Token>();
    q.predicate = new Predicate("accessToken = @ac", {"ac" : accessToken});
    await q.delete();
  }

  Future storeToken(AuthenticationServer server, Token t) async {
    var tokenQ = new Query<Token>();
    tokenQ.values = t;
    await tokenQ.insert();
  }

  Future updateToken(AuthenticationServer server, Token t) async {
    var tokenQ = new Query<Token>();
    tokenQ.predicate = new Predicate("refreshToken = @refreshToken", {"refreshToken" : t.refreshToken});
    tokenQ.values = t;
    return tokenQ.updateOne();
  }

  Future<Client> clientForID(AuthenticationServer server, String id) async {
    var salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
    if (id == "com.stablekernel.app1") {
      return new Client("com.stablekernel.app1", AuthenticationServer.generatePasswordHash("kilimanjaro", salt), salt);
    }
    if (id == "com.stablekernel.app2") {
      return new Client("com.stablekernel.app2", AuthenticationServer.generatePasswordHash("fuji", salt), salt);
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