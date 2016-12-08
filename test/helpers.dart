import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/utilities/token_generator.dart';
export 'context_helpers.dart';


justLogEverything() {
  hierarchicalLoggingEnabled = true;
  new Logger("")
    ..level = Level.ALL
    ..onRecord.listen((p) => print("${p} ${p.object} ${p.stackTrace}"));
}

class TestUser extends Authenticatable {
  int get uniqueIdentifier => id;
  int id;
}

class InMemoryAuthStorage implements AuthStorage {
  static const String DefaultPassword = "foobaraxegrind21%";

  InMemoryAuthStorage() {
    var salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";

    clients = {
      "com.stablekernel.app1": new AuthClient("com.stablekernel.app1",
          AuthUtility.generatePasswordHash("kilimanjaro", salt), salt),
      "com.stablekernel.app2": new AuthClient("com.stablekernel.app2",
          AuthUtility.generatePasswordHash("fuji", salt), salt),
      "com.stablekernel.redirect": new AuthClient.withRedirectURI(
          "com.stablekernel.redirect",
          AuthUtility.generatePasswordHash("mckinley", salt),
          salt,
          "http://stablekernel.com/auth/redirect"),
      "com.stablekernel.public": new AuthClient("com.stablekernel.public", null, salt),
      "com.stablekernel.redirect2": new AuthClient.withRedirectURI(
          "com.stablekernel.redirect2",
          AuthUtility.generatePasswordHash("gibraltar", salt),
          salt,
          "http://stablekernel.com/auth/redirect2")
    };
  }

  Map<String, AuthClient> clients;
  Map<int, TestUser> users = {};
  List<AuthToken> tokens = [];
  List<AuthCode> codes = [];

  AuthToken _copyToken(AuthToken t) {
    if (t == null) {
      return null;
    }
    return new AuthToken()
        ..uniqueIdentifier = t.uniqueIdentifier
        ..accessToken = t.accessToken
        ..refreshToken = t.refreshToken
        ..type = t.type
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
        ..clientID = t.clientID
        ..issueDate = t.issueDate
        ..expirationDate = t.expirationDate;
  }

  AuthCode _copyCode(AuthCode c) {
    if (c == null) {
      return null;
    }
    return new AuthCode()
        ..redirectURI = c.redirectURI
        ..code = c.code
        ..clientID = c.clientID
        ..resourceOwnerIdentifier = c.resourceOwnerIdentifier
        ..issueDate = c.issueDate
        ..expirationDate = c.expirationDate
        ..tokenIdentifier = c.tokenIdentifier;
  }

  void createUsers(int count) {
    for (int i = 0; i < count; i++) {
      var salt = AuthUtility.generateRandomSalt();
      var u = new TestUser()
        ..id = i + 1
        ..username = "bob+$i@stablekernel.com"
        ..salt = salt
        ..hashedPassword =
        AuthUtility.generatePasswordHash(DefaultPassword, salt);

      users[i + 1] = u;
    }
  }

  Future<AuthToken> fetchTokenWithAccessToken(AuthServer server, String accessToken) async {
    return _copyToken(tokens.firstWhere((t) => t.accessToken == accessToken,
        orElse: () => null));
  }

  Future<AuthToken> fetchTokenWithRefreshToken(AuthServer server, String refreshToken) async {
    return _copyToken(tokens.firstWhere((t) => t.refreshToken == refreshToken,
        orElse: () => null));
  }

  Future<TestUser> fetchResourceOwnerWithUsername(
      AuthServer server, String username) async {
    return users.values.firstWhere((t) => t.username == username,
        orElse: () => null);
  }

  Future revokeTokenWithIdentifier(AuthServer server, dynamic identifier) async {
    tokens.removeWhere((t) => t.uniqueIdentifier == identifier);
  }

  Future<dynamic> storeTokenAndReturnUniqueIdentifier(AuthServer server, AuthToken t) async {
    t.uniqueIdentifier = randomStringOfLength(32);
    tokens.add(t);
    return t.uniqueIdentifier;
  }

  Future updateTokenWithIdentifier(AuthServer server, dynamic identifier, AuthToken t) async {
    var existing = tokens.firstWhere((e) => e.uniqueIdentifier == identifier, orElse: () => null);
    if (existing != null) {
      var replacement = new AuthToken()
        ..uniqueIdentifier = t.uniqueIdentifier
        ..expirationDate = t.expirationDate
        ..issueDate = t.issueDate
        ..clientID = t.clientID
        ..accessToken = t.accessToken
        ..refreshToken = t.refreshToken
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
        ..type = t.type;

      tokens.remove(existing);
      tokens.add(replacement);
    }
  }

  Future storeAuthCode(AuthServer server, AuthCode code) async {
    codes.add(code);
  }

  Future<AuthCode> fetchAuthCodeWithCode(AuthServer server, String code) async {
    return _copyCode(codes.firstWhere((c) => c.code == code, orElse: () => null));
  }

  Future updateAuthCodeWithCode(AuthServer server, String code, AuthCode ac) async {
    var existing = codes.firstWhere((e) => e.code == code, orElse: () => null);

    existing?.issueDate = ac.issueDate;
    existing?.expirationDate = ac.expirationDate;
    existing?.redirectURI = ac.redirectURI;
    existing?.clientID = ac.clientID;
    existing?.code = ac.code;
    existing?.resourceOwnerIdentifier = ac.resourceOwnerIdentifier;
    existing?.tokenIdentifier = ac.tokenIdentifier;
  }

  Future revokeAuthCodeWithCode(AuthServer server, String code) async {
    codes.removeWhere((c) => c.code == code);
  }

  Future<AuthClient> fetchClientWithID(AuthServer server, String id) async {
    return clients[id];
  }

  Future revokeClientWithID(AuthServer server, String id) async {
    clients.remove(id);
  }
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
