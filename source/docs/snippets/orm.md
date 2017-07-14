# Aqueduct ORM Snippets

## Filter Query by Column/Property (WHERE clause)

```dart
var query = new Query<Employee>()
  ..where.title = whereEqualTo("Programmer");
var employees = await query.fetch();
```

## Fetching Only Some Columns/Properties

```dart
var query = new Query<Employee>()
  ..resultingProperties((e) => [e.id, e.name]);
var employees = await query.fetch();
```

## Sorting Rows/Objects

```dart
var query = new Query<Employee>()
  ..sortBy((e) => e.salary, QuerySortOrder.ascending);
var employees = await query.fetch();
```

## Fetching Only One Row/Object

```dart
var query = new Query<Employee>()
  ..where.id = whereEqualTo(1);
var employee = await query.fetchOne();
```

## Executing a Join (Has-One)

```dart
var query = new Query<Team>()
  ..join(object: (e) => e.league);
var teamsAndTheirLeague = await query.fetch();
```

## Executing a Join (Has-Many)

```dart
var query = new Query<Team>()
  ..join(set: (e) => e.players);
var teamsAndTheirPlayers = await query.fetch();
```

## Filtering Joined Rows/Objects

```dart
var query = new Query<Team>();

var subquery = query.join(set: (e) => e.players)
  ..where.yearsPlayed = whereLessThanOrEqualTo(1);

var teamsAndTheirRookiePlayers = await query.fetch();
```

## Filter Rows/Objects by Relationship Property

```dart
var query = new Query<Team>()
  ..where.players.haveAtLeastOneWhere.yearsPlayed = whereLessThanOrEqualTo(1);

var teamsWithRookies = await query.fetch();
```

## Updating a Row/Object

##

## Adding an Index to a Column

## Making a Column Unique
