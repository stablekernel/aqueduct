import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
export 'context_helpers.dart';
import 'dart:io';

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

class TestToken implements AuthToken, AuthCode {
  TestToken();
  TestToken.from(dynamic t) {
    if (t is TestToken) {
      this
        ..issueDate = t.issueDate
        ..expirationDate = t.expirationDate
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
        ..clientID = t.clientID
        ..type = t.type
        ..accessToken = t.accessToken
        ..refreshToken = t.refreshToken
        ..code = t.code;
    } else if (t is AuthToken) {
      this
        ..issueDate = t.issueDate
        ..expirationDate = t.expirationDate
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
        ..clientID = t.clientID
        ..type = t.type
        ..accessToken = t.accessToken
        ..refreshToken = t.refreshToken;
    } else if (t is AuthCode) {
      this
        ..issueDate = t.issueDate
        ..expirationDate = t.expirationDate
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
        ..clientID = t.clientID
        ..code = t.code;
    }
  }
  String accessToken;
  String refreshToken;
  DateTime issueDate;
  DateTime expirationDate;
  String type;
  dynamic resourceOwnerIdentifier;
  String clientID;
  String code;
  bool get hasBeenExchanged => accessToken != null;
  void set hasBeenExchanged(bool s) {}

  bool get isExpired {
    return expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }

  Map<String, dynamic> asMap() {
    var map = {
      "access_token": accessToken,
      "token_type": type,
      "expires_in":
          expirationDate.difference(new DateTime.now().toUtc()).inSeconds,
    };

    if (refreshToken != null) {
      map["refresh_token"] = refreshToken;
    }

    return map;
  }
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
      "com.stablekernel.public":
          new AuthClient("com.stablekernel.public", null, salt),
      "com.stablekernel.redirect2": new AuthClient.withRedirectURI(
          "com.stablekernel.redirect2",
          AuthUtility.generatePasswordHash("gibraltar", salt),
          salt,
          "http://stablekernel.com/auth/redirect2")
    };
  }

  Map<String, AuthClient> clients;
  Map<int, TestUser> users = {};
  List<TestToken> tokens = [];

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

  @override
  Future revokeAuthenticatableWithIdentifier(
      AuthServer server, dynamic identifier) async {
    tokens.removeWhere((t) => t.resourceOwnerIdentifier == identifier);
  }

  @override
  Future<AuthToken> fetchTokenByAccessToken(
      AuthServer server, String accessToken) async {
    var existing = tokens.firstWhere((t) => t.accessToken == accessToken,
        orElse: () => null);
    if (existing == null) {
      return null;
    }
    return new TestToken.from(existing);
  }

  @override
  Future<AuthToken> fetchTokenByRefreshToken(
      AuthServer server, String refreshToken) async {
    var existing = tokens.firstWhere((t) => t.refreshToken == refreshToken,
        orElse: () => null);
    if (existing == null) {
      return null;
    }
    return new TestToken.from(existing);
  }

  @override
  Future<TestUser> fetchAuthenticatableByUsername(
      AuthServer server, String username) async {
    return users.values
        .firstWhere((t) => t.username == username, orElse: () => null);
  }

  @override
  Future revokeTokenIssuedFromCode(AuthServer server, AuthCode code) async {
    tokens.removeWhere((t) => t.code == code.code);
  }

  @override
  Future storeToken(AuthServer server, AuthToken t,
      {AuthCode issuedFrom}) async {
    if (issuedFrom != null) {
      var existingIssued = tokens.firstWhere(
          (token) => token.code == issuedFrom?.code,
          orElse: () => null);
      var replacement = new TestToken.from(t);
      replacement.code = issuedFrom.code;
      tokens.remove(existingIssued);
      tokens.add(replacement);
    } else {
      tokens.add(new TestToken.from(t));
    }
  }

  @override
  Future refreshTokenWithAccessToken(
      AuthServer server,
      String accessToken,
      String newAccessToken,
      DateTime newIssueDate,
      DateTime newExpirationDate) async {
    var existing = tokens.firstWhere((e) => e.accessToken == accessToken,
        orElse: () => null);
    if (existing != null) {
      var replacement = new TestToken.from(existing)
        ..expirationDate = newExpirationDate
        ..issueDate = newIssueDate
        ..accessToken = newAccessToken
        ..clientID = existing.clientID
        ..refreshToken = existing.refreshToken
        ..resourceOwnerIdentifier = existing.resourceOwnerIdentifier
        ..type = existing.type;

      tokens.remove(existing);
      tokens.add(replacement);
    }
  }

  @override
  Future storeAuthCode(AuthServer server, AuthCode code) async {
    tokens.add(new TestToken.from(code));
  }

  @override
  Future<AuthCode> fetchAuthCodeByCode(AuthServer server, String code) async {
    var existing = tokens.firstWhere((t) => t.code == code, orElse: () => null);
    if (existing == null) {
      return null;
    }
    return new TestToken.from(existing);
  }

  @override
  Future revokeAuthCodeWithCode(AuthServer server, String code) async {
    tokens.removeWhere((c) => c.code == code);
  }

  @override
  Future<AuthClient> fetchClientByID(AuthServer server, String id) async {
    return clients[id];
  }

  @override
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


Future<ProcessResult> runPubGet(Directory workingDirectory,
    {bool offline: true}) async {
  var args = ["get", "--no-packages-dir"];
  if (offline) {
    args.add("--offline");
  }

  var result = await Process
      .run("pub", args,
      workingDirectory: workingDirectory.absolute.path,
      runInShell: true)
      .timeout(new Duration(seconds: 20));

  if (result.exitCode != 0) {
    throw new Exception("${result.stderr}");
  }

  return result;
}

void createTestProject(Directory source, Directory dest) {
  Process.runSync("cp", ["-r", "${source.path}", "${dest.path}"]);
}
