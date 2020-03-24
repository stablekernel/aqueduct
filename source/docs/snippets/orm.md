# Aqueduct ORM Snippets

## Filter Query by Column/Property (WHERE clause)

```dart
var query = new Query<Employee>(context)
  ..where((e) => e.title).equalTo("Programmer");
var employees = await query.fetch();
```

## Fetching Only Some Columns/Properties

```dart
var query = new Query<Employee>(context)
  ..resultingProperties((e) => [e.id, e.name]);
var employees = await query.fetch();
```

## Sorting Rows/Objects

```dart
var query = new Query<Employee>(context)
  ..sortBy((e) => e.salary, QuerySortOrder.ascending);
var employees = await query.fetch();
```

## Fetching Only One Row/Object

```dart
var query = new Query<Employee>(context)
  ..where((e) => e.id).equalTo(1);
var employee = await query.fetchOne();
```

## Executing a Join (Has-One)

```dart
var query = new Query<Team>(context)
  ..join(object: (e) => e.league);
var teamsAndTheirLeague = await query.fetch();
```

## Executing a Join (Has-Many)

```dart
var query = new Query<Team>(context)
  ..join(set: (e) => e.players);
var teamsAndTheirPlayers = await query.fetch();
```

## Filtering Joined Rows/Objects

```dart
var query = new Query<Team>(context);

var subquery = query.join(set: (e) => e.players)
  ..where((p) => p.yearsPlayed).lessThanOrEqualTo(1);

var teamsAndTheirRookiePlayers = await query.fetch();
```

## Filter Rows/Objects by Relationship Property

```dart
var query = new Query<Team>(context)
  ..where((t) => t.players.haveAtLeastOneWhere.yearsPlayed).lessThanOrEqualTo(1);

var teamsWithRookies = await query.fetch();
```

## Complex/Unsupported WHERE Clause (using 'OR')

```dart
var query = new Query<Team>(context)
  ..predicate = new QueryPredicate("name = @name1 OR name = @name2", {
      "name1": "Badgers",
      "name2": "Gophers"
    });

var badgerAndGopherTeams = await query.fetch();
```

## Updating a Row/Object

```dart
var query = new Query<Team>(context)
  ..where((t) => t.id).equalTo(10)
  ..values.name = "Badgers";

var team = await query.updateOne();
```

## Configure a Database Connection from Configuration File

```dart
class AppChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    context = contextWithConnectionInfo(options.configurationFilePath.database);
  }

  ManagedContext context;

  @override
  Controller get entryPoint {
    final router = new Router();
    ...
    return router;
  }

  ManagedContext contextWithConnectionInfo(
      DatabaseConnectionConfiguration connectionInfo) {
    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var psc = new PostgreSQLPersistentStore(
        connectionInfo.username,
        connectionInfo.password,
        connectionInfo.host,
        connectionInfo.port,
        connectionInfo.databaseName);

    return new ManagedContext(dataModel, psc);
  }
}

class MyAppConfiguration extends Configuration {
  MyAppConfiguration(String fileName) : super.fromFile(File(fileName));

  DatabaseConnectionConfiguration database;
}

```
