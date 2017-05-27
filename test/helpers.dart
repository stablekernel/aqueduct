import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
export 'context_helpers.dart';

justLogEverything() {
  hierarchicalLoggingEnabled = true;
  new Logger("")
    ..level = Level.ALL
    ..onRecord.listen((p) => print("$p ${p.object} ${p.stackTrace}"));
}

class TestUser extends Authenticatable {
  int get uniqueIdentifier => id;
  @override
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
        ..scopes = t.scopes
        ..requestedScopes = t.requestedScopes
        ..code = t.code;
    } else if (t is AuthToken) {
      this
        ..issueDate = t.issueDate
        ..expirationDate = t.expirationDate
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
        ..clientID = t.clientID
        ..type = t.type
        ..accessToken = t.accessToken
        ..scopes = t.scopes
        ..refreshToken = t.refreshToken;
    } else if (t is AuthCode) {
      this
        ..issueDate = t.issueDate
        ..expirationDate = t.expirationDate
        ..resourceOwnerIdentifier = t.resourceOwnerIdentifier
        ..clientID = t.clientID
        ..requestedScopes = t.requestedScopes
        ..code = t.code;
    }
  }
  @override
  String accessToken;
  @override
  String refreshToken;
  @override
  DateTime issueDate;
  @override
  DateTime expirationDate;
  @override
  String type;
  @override
  dynamic resourceOwnerIdentifier;
  @override
  String clientID;
  @override
  String code;
  @override
  List<AuthScope> scopes;
  @override
  List<AuthScope> requestedScopes;
  @override
  bool get hasBeenExchanged => accessToken != null;
  @override
  set hasBeenExchanged(bool s) {}

  @override
  bool get isExpired {
    return expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }

  @override
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
          "http://stablekernel.com/auth/redirect2"),
      "com.stablekernel.scoped": new AuthClient.withRedirectURI(
          "com.stablekernel.scoped",
          AuthUtility.generatePasswordHash("kilimanjaro", salt),
          salt,
          "http://stablekernel.com/auth/scoped", allowedScopes: [
            new AuthScope("user"),
            new AuthScope("other_scope")
          ]),
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
      replacement.scopes = issuedFrom.requestedScopes;

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
  @override
  Future<dynamic> execute(String sql,
          {Map<String, dynamic> substitutionValues}) async =>
      null;
  @override
  Future<dynamic> executeQuery(String formatString, Map<String, dynamic> values,
          int timeoutInSeconds,
          {PersistentStoreQueryReturnType returnType}) async =>
      null;
  @override
  Future close() async {}

  @override
  List<String> createTable(SchemaTable t, {bool isTemporary: false}) => [];
  @override
  List<String> renameTable(SchemaTable table, String name) => [];
  @override
  List<String> deleteTable(SchemaTable table) => [];

  @override
  List<String> addColumn(SchemaTable table, SchemaColumn column, {String unencodedInitialValue}) => [];
  @override
  List<String> deleteColumn(SchemaTable table, SchemaColumn column) => [];
  @override
  List<String> renameColumn(
          SchemaTable table, SchemaColumn column, String name) =>
      [];
  @override
  List<String> alterColumnNullability(SchemaTable table, SchemaColumn column,
          String unencodedInitialValue) =>
      [];
  @override
  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column) =>
      [];
  @override
  List<String> alterColumnDefaultValue(
          SchemaTable table, SchemaColumn column) =>
      [];
  @override
  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column) =>
      [];
  @override
  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column) => [];
  @override
  List<String> renameIndex(
          SchemaTable table, SchemaColumn column, String newIndexName) =>
      [];
  @override
  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column) =>
      [];
  @override
  Future<int> get schemaVersion async => 0;
  @override
  Future upgrade(int versionNumber, List<String> commands,
          {bool temporary: false}) async =>
      null;
}
