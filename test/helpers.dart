import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:postgres/postgres.dart';

Future<List<TestUser>> createUsers(int count) async {
  var users = new List<TestUser>();
  for (int i = 0; i < count; i++) {
    var salt = AuthServer.generateRandomSalt();
    var u = new TestUser()
      ..username = "bob+$i@stablekernel.com"
      ..salt = salt
      ..hashedPassword =
          AuthServer.generatePasswordHash("foobaraxegrind21%", salt);

    var q = new Query<TestUser>()..values = u;
    var insertedUser = await q.insert();
    users.add(insertedUser);
  }
  return users;
}

class TestUser extends ManagedObject<_User> implements _User {}

class _User implements Authenticatable {
  @managedPrimaryKey
  int id;

  String username;
  String hashedPassword;
  String salt;
}

class Token extends ManagedObject<_Token> implements _Token {}

class _Token implements AuthTokenizable<int> {
  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(indexed: true)
  String accessToken;

  @ManagedColumnAttributes(indexed: true, nullable: true)
  String refreshToken;

  DateTime issueDate;
  DateTime expirationDate;
  int resourceOwnerIdentifier;
  String type;
  String clientID;

  AuthCode code;
}

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

class AuthDelegate implements AuthServerDelegate<TestUser, Token, AuthCode> {
  ManagedContext context;

  AuthDelegate(this.context);

  Future<Token> tokenForAccessToken(AuthServer server, String accessToken) {
    return _tokenForPredicate(new QueryPredicate(
        "accessToken = @accessToken", {"accessToken": accessToken}));
  }

  Future<Token> tokenForRefreshToken(AuthServer server, String refreshToken) {
    return _tokenForPredicate(new QueryPredicate(
        "refreshToken = @refreshToken", {"refreshToken": refreshToken}));
  }

  Future<TestUser> authenticatableForUsername(
      AuthServer server, String username) {
    var userQ = new Query<TestUser>();
    userQ.predicate =
        new QueryPredicate("username = @username", {"username": username});
    return userQ.fetchOne();
  }

  Future<TestUser> authenticatableForID(AuthServer server, dynamic id) {
    var userQ = new Query<TestUser>();
    userQ.predicate = new QueryPredicate("username = @username", {"id": id});
    return userQ.fetchOne();
  }

  Future deleteTokenForRefreshToken(
      AuthServer server, String refreshToken) async {
    var q = new Query<Token>();
    q.predicate =
        new QueryPredicate("refreshToken = @rf", {"rf": refreshToken});
    await q.delete();
  }

  Future<Token> storeToken(AuthServer server, Token t) async {
    var tokenQ = new Query<Token>();
    tokenQ.values = t;
    return await tokenQ.insert();
  }

  Future updateToken(AuthServer server, Token t) async {
    var tokenQ = new Query<Token>();
    tokenQ.predicate = new QueryPredicate(
        "refreshToken = @refreshToken", {"refreshToken": t.refreshToken});
    tokenQ.values = t;

    return tokenQ.updateOne();
  }

  Future<AuthCode> storeAuthCode(AuthServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.values = code;
    return authCodeQ.insert();
  }

  Future<AuthCode> authCodeForCode(AuthServer server, String code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.predicate = new QueryPredicate("code = @code", {"code": code});
    return authCodeQ.fetchOne();
  }

  Future updateAuthCode(AuthServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.predicate = new QueryPredicate("id = @id", {"id": code.id});
    authCodeQ.values = code;
    return authCodeQ.updateOne();
  }

  Future deleteAuthCode(AuthServer server, AuthCode code) async {
    var authCodeQ = new Query<AuthCode>();
    authCodeQ.predicate = new QueryPredicate("id = @id", {"id": code.id});

    return authCodeQ.delete();
  }

  Future<AuthClient> clientForID(AuthServer server, String id) async {
    var salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
    if (id == "com.stablekernel.app1") {
      return new AuthClient("com.stablekernel.app1",
          AuthServer.generatePasswordHash("kilimanjaro", salt), salt);
    }
    if (id == "com.stablekernel.app2") {
      return new AuthClient("com.stablekernel.app2",
          AuthServer.generatePasswordHash("fuji", salt), salt);
    }
    if (id == "com.stablekernel.app3") {
      return new AuthClient.withRedirectURI(
          "com.stablekernel.app3",
          AuthServer.generatePasswordHash("mckinley", salt),
          salt,
          "http://stablekernel.com/auth/redirect");
    }
    if (id == "com.stablekernel.public") {
      return new AuthClient("com.stablekernel.public", null, salt);
    }

    return null;
  }

  Future<Token> _tokenForPredicate(QueryPredicate p) async {
    var tokenQ = new Query<Token>();
    tokenQ.predicate = p;
    var result = await tokenQ.fetchOne();
    if (result == null) {
      throw new HTTPResponseException(401, "Invalid Token");
    }

    return result;
  }
}

Future<ManagedContext> contextWithModels(List<Type> instanceTypes) async {
  var persistentStore = new PostgreSQLPersistentStore(() async {
    var conn = new PostgreSQLConnection("localhost", 5432, "dart_test",
        username: "dart", password: "dart");
    await conn.open();
    return conn;
  });

  var dataModel = new ManagedDataModel(instanceTypes);
  var commands = commandsFromDataModel(dataModel, temporary: true);
  var context = new ManagedContext(dataModel, persistentStore);
  ManagedContext.defaultContext = context;

  for (var cmd in commands) {
    await persistentStore.execute(cmd);
  }

  return context;
}

List<String> commandsFromDataModel(ManagedDataModel dataModel,
    {bool temporary: false}) {
  var targetSchema = new Schema.fromDataModel(dataModel);
  var builder = new SchemaBuilder.toSchema(
      new PostgreSQLPersistentStore(() => null), targetSchema,
      isTemporary: temporary);
  return builder.commands;
}

List<String> commandsForModelInstanceTypes(List<Type> instanceTypes,
    {bool temporary: false}) {
  var dataModel = new ManagedDataModel(instanceTypes);
  return commandsFromDataModel(dataModel, temporary: temporary);
}

class DefaultPersistentStore extends PersistentStore {
  Future<dynamic> execute(String sql,
          {Map<String, dynamic> substitutionValues}) async =>
      null;
  Future close() async {}
  Future<List<PersistentColumnMapping>> executeInsertQuery(
          PersistentStoreQuery q) async =>
      null;
  Future<List<List<PersistentColumnMapping>>> executeFetchQuery(
          PersistentStoreQuery q) async =>
      null;
  Future<int> executeDeleteQuery(PersistentStoreQuery q) async => null;
  Future<List<List<PersistentColumnMapping>>> executeUpdateQuery(
          PersistentStoreQuery q) async =>
      null;

  QueryPredicate comparisonPredicate(ManagedPropertyDescription desc,
          MatcherOperator operator, dynamic value) =>
      null;
  QueryPredicate containsPredicate(
          ManagedPropertyDescription desc, Iterable<dynamic> values) =>
      null;
  QueryPredicate nullPredicate(ManagedPropertyDescription desc, bool isNull) =>
      null;
  QueryPredicate rangePredicate(ManagedPropertyDescription desc,
          dynamic lhsValue, dynamic rhsValue, bool insideRange) =>
      null;
  QueryPredicate stringPredicate(ManagedPropertyDescription desc,
          StringMatcherOperator operator, dynamic value) =>
      null;

  List<String> createTable(SchemaTable t, {bool isTemporary: false}) => [];
  List<String> renameTable(SchemaTable table, String name) => [];
  List<String> deleteTable(SchemaTable table) => [];

  List<String> addColumn(SchemaTable table, SchemaColumn column) => [];
  List<String> deleteColumn(SchemaTable table, SchemaColumn column) => [];
  List<String> renameColumn(
          SchemaTable table, SchemaColumn column, String name) =>
      [];
  List<String> alterColumnNullability(SchemaTable table, SchemaColumn column,
          String unencodedInitialValue) =>
      [];
  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column) =>
      [];
  List<String> alterColumnDefaultValue(
          SchemaTable table, SchemaColumn column) =>
      [];
  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column) =>
      [];

  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column) => [];
  List<String> renameIndex(
          SchemaTable table, SchemaColumn column, String newIndexName) =>
      [];
  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column) =>
      [];

  Future<int> get schemaVersion async => 0;
  Future upgrade(int versionNumber, List<String> commands,
          {bool temporary: false}) async =>
      null;
}
