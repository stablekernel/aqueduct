import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/query/mixin.dart';
export 'package:aqueduct/src/dev/context_helpers.dart';

void justLogEverything() {
  hierarchicalLoggingEnabled = true;
  Logger("")
    ..level = Level.ALL
    ..onRecord.listen((p) => print("$p ${p.object} ${p.stackTrace}"));
}

class PassthruController extends Controller {
  @override
  FutureOr<RequestOrResponse> handle(Request request) => request;
}

class TestUser extends ResourceOwner {
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
  int resourceOwnerIdentifier;
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
    return expirationDate.difference(DateTime.now().toUtc()).inSeconds <= 0;
  }

  @override
  Map<String, dynamic> asMap() {
    var map = {
      "access_token": accessToken,
      "token_type": type,
      "expires_in": expirationDate.difference(DateTime.now().toUtc()).inSeconds,
    };

    if (refreshToken != null) {
      map["refresh_token"] = refreshToken;
    }

    return map;
  }
}

class InMemoryAuthStorage extends AuthServerDelegate {
  InMemoryAuthStorage() {
    reset();
  }

  static const String defaultPassword = "foobaraxegrind21%";

  Map<String, AuthClient> clients;
  Map<int, TestUser> users = {};
  List<TestToken> tokens = [];
  List<AuthScope> allowedScopes;

  void createUsers(int count) {
    for (int i = 0; i < count; i++) {
      var salt = AuthUtility.generateRandomSalt();
      var u = TestUser()
        ..id = i + 1
        ..username = "bob+$i@stablekernel.com"
        ..salt = salt
        ..hashedPassword =
            AuthUtility.generatePasswordHash(defaultPassword, salt);

      users[i + 1] = u;
    }
  }

  void reset() {
    var salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
    clients = {
      "com.stablekernel.app1": AuthClient("com.stablekernel.app1",
          AuthUtility.generatePasswordHash("kilimanjaro", salt), salt),
      "com.stablekernel.app2": AuthClient("com.stablekernel.app2",
          AuthUtility.generatePasswordHash("fuji", salt), salt),
      "com.stablekernel.redirect": AuthClient.withRedirectURI(
          "com.stablekernel.redirect",
          AuthUtility.generatePasswordHash("mckinley", salt),
          salt,
          "http://stablekernel.com/auth/redirect"),
      "com.stablekernel.public":
          AuthClient("com.stablekernel.public", null, salt),
      "com.stablekernel.redirect2": AuthClient.withRedirectURI(
          "com.stablekernel.redirect2",
          AuthUtility.generatePasswordHash("gibraltar", salt),
          salt,
          "http://stablekernel.com/auth/redirect2"),
      "com.stablekernel.public.redirect": AuthClient.withRedirectURI(
          "com.stablekernel.public.redirect",
          null,
          salt,
          "http://stablekernel.com/auth/public-redirect"),
      "com.stablekernel.scoped": AuthClient.withRedirectURI(
          "com.stablekernel.scoped",
          AuthUtility.generatePasswordHash("kilimanjaro", salt),
          salt,
          "http://stablekernel.com/auth/scoped",
          allowedScopes: [AuthScope("user"), AuthScope("other_scope")]),
      "com.stablekernel.public.scoped": AuthClient.withRedirectURI(
          "com.stablekernel.public.scoped",
          null,
          salt,
          "http://stablekernel.com/auth/public-scoped",
          allowedScopes: [AuthScope("user"), AuthScope("other_scope")]),
    };
    users = {};
    tokens = [];
    allowedScopes = AuthScope.any;
  }

  @override
  void addClient(AuthServer server, AuthClient client) {
    clients[client.id] = client;
  }

  @override
  void removeTokens(AuthServer server, dynamic resourceOwnerID) {
    return tokens.removeWhere((t) => t.resourceOwnerIdentifier == resourceOwnerID);
  }

  @override
  FutureOr<AuthToken> getToken(AuthServer server,
      {String byAccessToken, String byRefreshToken}) {
    AuthToken existing;
    if (byAccessToken != null) {
      existing = tokens.firstWhere((t) => t.accessToken == byAccessToken,
          orElse: () => null);
    } else if (byRefreshToken != null) {
      existing = tokens.firstWhere((t) => t.refreshToken == byRefreshToken,
          orElse: () => null);
    } else {
      throw ArgumentError(
          "byAccessToken and byRefreshToken are mutually exclusive");
    }

    if (existing == null) {
      return null;
    }
    return TestToken.from(existing);
  }

  @override
  FutureOr<TestUser> getResourceOwner(AuthServer server, String username) {
    return users.values
        .firstWhere((t) => t.username == username, orElse: () => null);
  }

  @override
  void removeToken(AuthServer server, AuthCode grantedByCode) =>
      tokens.removeWhere((t) => t.code == grantedByCode.code);

  @override
  FutureOr addToken(AuthServer server, AuthToken token, {AuthCode issuedFrom}) {
    if (issuedFrom != null) {
      var existingIssued = tokens.firstWhere(
          (t) => t.code == issuedFrom?.code,
          orElse: () => null);
      var replacement = TestToken.from(token);
      replacement.code = issuedFrom.code;
      replacement.scopes = issuedFrom.requestedScopes;

      tokens.remove(existingIssued);
      tokens.add(replacement);
    } else {
      tokens.add(TestToken.from(token));
    }

    return null;
  }

  @override
  FutureOr updateToken(
      AuthServer server,
      String oldAccessToken,
      String newAccessToken,
      DateTime newIssueDate,
      DateTime newExpirationDate) {
    var existing = tokens.firstWhere((e) => e.accessToken == oldAccessToken,
        orElse: () => null);
    if (existing != null) {
      var replacement = TestToken.from(existing)
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

    return null;
  }

  @override
  void addCode(AuthServer server, AuthCode code) =>
      tokens.add(TestToken.from(code));

  @override
  FutureOr<AuthCode> getCode(AuthServer server, String code) {
    var existing = tokens.firstWhere((t) => t.code == code, orElse: () => null);
    if (existing == null) {
      return null;
    }
    return TestToken.from(existing);
  }

  @override
  void removeCode(AuthServer server, String code) =>
      tokens.removeWhere((c) => c.code == code);

  @override
  FutureOr<AuthClient> getClient(AuthServer server, String clientID) => clients[clientID];

  @override
  FutureOr removeClient(AuthServer server, String clientID) => clients.remove(clientID);

  @override
  List<AuthScope> getAllowedScopes(ResourceOwner owner) => allowedScopes;
}

class DefaultPersistentStore extends PersistentStore {
  @override
  Query<T> newQuery<T extends ManagedObject>(
      ManagedContext context, ManagedEntity entity, {T values}) {
    final q = _MockQuery<T>.withEntity(context, entity);
    if (values != null) {
      q.values = values;
    }
    return q;
  }

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
  Future<T> transaction<T>(ManagedContext transactionContext,
          Future<T> transactionBlock(ManagedContext transaction)) async =>
      throw Exception("Transaciton not supported on mock");

  @override
  List<String> createTable(SchemaTable table, {bool isTemporary = false}) => [];

  @override
  List<String> renameTable(SchemaTable table, String name) => [];

  @override
  List<String> deleteTable(SchemaTable table) => [];

  @override
  List<String> addTableUniqueColumnSet(SchemaTable table) => [];

  @override
  List<String> deleteTableUniqueColumnSet(SchemaTable table) => [];

  @override
  List<String> addColumn(SchemaTable table, SchemaColumn column,
          {String unencodedInitialValue}) =>
      [];

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
  Future<Schema> upgrade(Schema fromSchema, List<Migration> withMigrations,
      {bool temporary = false}) async {
    var out = fromSchema;
    for (var migration in withMigrations) {
      migration.database = SchemaBuilder(this, out);
      await migration.upgrade();
      await migration.seed();
      out = migration.database.schema;
    }
    return out;
  }
}

class _MockQuery<InstanceType extends ManagedObject> extends Object
    with QueryMixin<InstanceType>
    implements Query<InstanceType> {
  _MockQuery(this.context);

  _MockQuery.withEntity(this.context, ManagedEntity entity) {
    _entity = entity;
  }

  @override
  ManagedContext context;

  @override
  ManagedEntity get entity =>
      _entity ?? context.dataModel.entityForType(InstanceType);

  ManagedEntity _entity;

  @override
  Future<InstanceType> insert() async {
    throw Exception("insert() in _MockQuery");
  }

  @override
  Future<List<InstanceType>> update() async {
    throw Exception("update() in _MockQuery");
  }

  @override
  Future<InstanceType> updateOne() async {
    throw Exception("updateOne() in _MockQuery");
  }

  @override
  Future<int> delete() async {
    throw Exception("delete() in _MockQuery");
  }

  @override
  Future<List<InstanceType>> fetch() async {
    throw Exception("fetch() in _MockQuery");
  }

  @override
  Future<InstanceType> fetchOne() async {
    throw Exception("fetchOne() in _MockQuery");
  }

  @override
  QueryReduceOperation<InstanceType> get reduce {
    throw Exception("fold in _MockQuery");
  }
}
