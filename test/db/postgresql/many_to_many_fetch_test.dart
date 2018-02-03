import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../model_graph.dart';
import '../../helpers.dart';

/*
  many to many should just be an extension of tests in belongs_to_fetch, tiered_where, has_many and has_one tests
  so primary goal of these tests is to make sure there are no edge cases in many to many queries
 */

void main() {
  ManagedContext ctx;
  setUpAll(() async {
    ctx = await contextWithModels([
      RootObject,
      RootJoinObject,
      OtherRootObject,
      ChildObject,
      GrandChildObject,
      Team,
      Game
    ]);
    var _ = await populateModelGraph(ctx);
    await populateGameSchedule();
  });

  tearDownAll(() async {
    await ctx.persistentStore.close();
  });

  group("Explicit joins", () {
    test("Can join across many to many relationship, from one side", () async {
      var q = new Query<RootObject>()
        ..sortBy((r) => r.rid, QuerySortOrder.ascending);

      q.join(set: (r) => r.join)..join(object: (r) => r.other);
      var results = await q.fetch();
      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            fullObjectMap(RootObject, 1, and: {
              "join": [
                {
                  "id": 1,
                  "root": {"rid": 1},
                  "other": fullObjectMap(OtherRootObject, 1)
                },
                {
                  "id": 2,
                  "root": {"rid": 1},
                  "other": fullObjectMap(OtherRootObject, 2)
                },
              ]
            }),
            fullObjectMap(RootObject, 2, and: {
              "join": [
                {
                  "id": 3,
                  "root": {"rid": 2},
                  "other": fullObjectMap(OtherRootObject, 3)
                },
              ]
            }),
            fullObjectMap(RootObject, 3, and: {"join": []}),
            fullObjectMap(RootObject, 4, and: {"join": []}),
            fullObjectMap(RootObject, 5, and: {"join": []}),
          ]));
    });

    test("Can join across many to many relationship, from other side",
        () async {
      var q = new Query<OtherRootObject>()
        ..sortBy((o) => o.id, QuerySortOrder.ascending);

      q.join(set: (r) => r.join)..join(object: (r) => r.root);
      var results = await q.fetch();
      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            fullObjectMap(OtherRootObject, 1, and: {
              "join": [
                {
                  "id": 1,
                  "root": fullObjectMap(RootObject, 1),
                  "other": {"id": 1},
                }
              ]
            }),
            fullObjectMap(OtherRootObject, 2, and: {
              "join": [
                {
                  "id": 2,
                  "root": fullObjectMap(RootObject, 1),
                  "other": {"id": 2},
                },
              ]
            }),
            fullObjectMap(OtherRootObject, 3, and: {
              "join": [
                {
                  "id": 3,
                  "root": fullObjectMap(RootObject, 2),
                  "other": {"id": 3},
                }
              ]
            }),
          ]));
    });

    test("Can join from join table", () async {
      var q = new Query<RootJoinObject>()
        ..sortBy((r) => r.id, QuerySortOrder.ascending)
        ..join(object: (r) => r.other)
        ..join(object: (r) => r.root);

      var results = await q.fetch();
      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            {"id": 1, "other": fullObjectMap(OtherRootObject, 1), "root": fullObjectMap(RootObject, 1)},
            {"id": 2, "other": fullObjectMap(OtherRootObject, 2), "root": fullObjectMap(RootObject, 1)},
            {"id": 3, "other": fullObjectMap(OtherRootObject, 3), "root": fullObjectMap(RootObject, 2)},
          ]));
    });
  });

  group("Implicit joins", () {
    test("Can use implicit matcher across many to many table", () async {
      var q = new Query<RootObject>()
        ..sortBy((r) => r.rid, QuerySortOrder.ascending)
        ..where.join.haveAtLeastOneWhere.other.value1 = whereLessThan(4);

      var results = await q.fetch();
      expect(results.map((r) => r.asMap()).toList(),
          equals([fullObjectMap(RootObject, 1), fullObjectMap(RootObject, 2)]));

      q.where.join.haveAtLeastOneWhere.other.value1 = whereEqualTo(3);
      results = await q.fetch();
      expect(
          results.map((r) => r.asMap()).toList(), equals([fullObjectMap(RootObject, 2)]));
    });

    test("Can use implicit join with join table to one side", () async {
      var q = new Query<RootJoinObject>()..where.root.value1 = whereEqualTo(1);
      var results = await q.fetch();
      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            {
              "id": 1,
              "other": {"id": 1},
              "root": {"rid": 1}
            },
            {
              "id": 2,
              "other": {"id": 2},
              "root": {"rid": 1}
            },
          ]));
    });

    test("Can use implicit join with join table to both sides", () async {
      var q = new Query<RootJoinObject>()
        ..where.root.value1 = whereEqualTo(1)
        ..where.other.value1 = whereEqualTo(1);
      var results = await q.fetch();
      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            {
              "id": 1,
              "other": {"id": 1},
              "root": {"rid": 1}
            },
          ]));

      q = new Query<RootJoinObject>()
        ..where.root.value1 = whereEqualTo(1)
        ..where.other.value1 = whereEqualTo(2);
      results = await q.fetch();
      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            {
              "id": 2,
              "other": {"id": 2},
              "root": {"rid": 1}
            },
          ]));

      q = new Query<RootJoinObject>()
        ..where.root.value1 = whereEqualTo(2)
        ..where.other.value1 = whereEqualTo(2);
      results = await q.fetch();
      expect(results.map((r) => r.asMap()).toList(), equals([]));
    });
  });

  group("Self joins - standard", () {
    test("Can join by one relationship", () async {
      var q = new Query<Team>()..sortBy((t) => t.id, QuerySortOrder.ascending);

      q.join(set: (t) => t.awayGames)..join(object: (g) => g.homeTeam);

      var results = await q.fetch();
      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            {"id": 1, "name": "Wisconsin", "awayGames": []},
            {
              "id": 2,
              "name": "Minnesota",
              "awayGames": [
                {
                  "id": 1,
                  "homeScore": 45,
                  "awayScore": 0,
                  "homeTeam": {"id": 1, "name": "Wisconsin"},
                  "awayTeam": {"id": 2}
                }
              ]
            },
            {
              "id": 3,
              "name": "Iowa",
              "awayGames": [
                {
                  "id": 2,
                  "homeScore": 35,
                  "awayScore": 3,
                  "homeTeam": {"id": 1, "name": "Wisconsin"},
                  "awayTeam": {"id": 3}
                },
                {
                  "id": 3,
                  "homeScore": 0,
                  "awayScore": 3,
                  "homeTeam": {"id": 2, "name": "Minnesota"},
                  "awayTeam": {"id": 3}
                }
              ]
            },
          ]));
    });

    test("Can join by other relationship", () async {
      var q = new Query<Team>()..sortBy((t) => t.id, QuerySortOrder.ascending);

      q.join(set: (t) => t.homeGames)..join(object: (g) => g.awayTeam);
      var results = await q.fetch();

      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            {
              "id": 1,
              "name": "Wisconsin",
              "homeGames": [
                {
                  "id": 1,
                  "homeScore": 45,
                  "awayScore": 0,
                  "homeTeam": {"id": 1},
                  "awayTeam": {"id": 2, "name": "Minnesota"}
                },
                {
                  "id": 2,
                  "homeScore": 35,
                  "awayScore": 3,
                  "homeTeam": {"id": 1},
                  "awayTeam": {"id": 3, "name": "Iowa"}
                },
              ]
            },
            {
              "id": 2,
              "name": "Minnesota",
              "homeGames": [
                {
                  "id": 3,
                  "homeScore": 0,
                  "awayScore": 3,
                  "homeTeam": {"id": 2},
                  "awayTeam": {"id": 3, "name": "Iowa"}
                }
              ]
            },
            {"id": 3, "name": "Iowa", "homeGames": []},
          ]));
    });

    test("Can join from join table", () async {
      var q = new Query<Game>()
        ..join(object: (g) => g.awayTeam)
        ..join(object: (g) => g.homeTeam)
        ..sortBy((g) => g.id, QuerySortOrder.ascending);
      var results = await q.fetch();

      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            {
              "id": 1,
              "homeScore": 45,
              "awayScore": 0,
              "homeTeam": {"id": 1, "name": "Wisconsin"},
              "awayTeam": {"id": 2, "name": "Minnesota"}
            },
            {
              "id": 2,
              "homeScore": 35,
              "awayScore": 3,
              "homeTeam": {"id": 1, "name": "Wisconsin"},
              "awayTeam": {"id": 3, "name": "Iowa"}
            },
            {
              "id": 3,
              "homeScore": 0,
              "awayScore": 3,
              "homeTeam": {"id": 2, "name": "Minnesota"},
              "awayTeam": {"id": 3, "name": "Iowa"}
            },
          ]));
    });

    test(
        "Attempt to join many to many relationship on the same property throws an exception before executing",
        () async {
      try {
        var q = new Query<Team>();

        q.join(set: (t) => t.homeGames)..join(object: (g) => g.homeTeam);
        expect(true, false);
      } on StateError catch (e) {
        expect(e.toString(), contains("Invalid query construction"));
      }
    });
  });

  group("Self joins - implicit", () {
    test("Can implicit join through join table", () async {
      // 'Teams that have played at Minnesota'
      var q = new Query<Team>()
        ..sortBy((t) => t.id, QuerySortOrder.ascending)
        ..where.awayGames.haveAtLeastOneWhere.homeTeam.name =
            whereContains("Minn");
      var results = await q.fetch();
      expect(
          results.map((t) => t.asMap()).toList(),
          equals([
            {"id": 3, "name": "Iowa"}
          ]));

      // 'Teams that have played at Iowa'
      q = new Query<Team>()
        ..sortBy((t) => t.id, QuerySortOrder.ascending)
        ..where.awayGames.haveAtLeastOneWhere.homeTeam.name =
            whereContains("Iowa");
      results = await q.fetch();
      expect(results.map((t) => t.asMap()).toList(), equals([]));
    });

    test("Can implicit join from join table - one side", () async {
      // 'Games where Iowa was away'
      var q = new Query<Game>()..where.awayTeam.name = whereContains("Iowa");
      var results = await q.fetch();
      expect(
          results.map((g) => g.asMap()).toList(),
          equals([
            {
              "id": 2,
              "homeScore": 35,
              "awayScore": 3,
              "awayTeam": {"id": 3},
              "homeTeam": {"id": 1}
            },
            {
              "id": 3,
              "homeScore": 0,
              "awayScore": 3,
              "awayTeam": {"id": 3},
              "homeTeam": {"id": 2}
            }
          ]));
    });

    test("Can implicit join from join table - both sides", () async {
      // 'Games where Iowa played Wisconsin at home'
      var q = new Query<Game>()
        ..where.homeTeam.name = whereContains("Wisco")
        ..where.awayTeam.name = whereContains("Iowa");
      var results = await q.fetch();
      expect(
          results.map((g) => g.asMap()).toList(),
          equals([
            {
              "id": 2,
              "homeScore": 35,
              "awayScore": 3,
              "awayTeam": {"id": 3},
              "homeTeam": {"id": 1}
            }
          ]));
    });

    test(
        "Attempt to implicitly join many to many relationships on the same property throws an exception when executing",
        () async {
      try {
        var q = new Query<Team>();
        q.join(set: (t) => t.awayGames)
          ..where.awayTeam.name = whereContains("Minn");
        await q.fetch();

        expect(true, false);
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("query would join on the same table and foreign key twice"));
      }
    });
  });

  group("Self joins - standard + filter", () {
    test("Can filter returned nested objects by their values", () async {
      // 'All teams and the games they've played at Minnesota'
      var q = new Query<Team>();
      q.join(set: (t) => t.awayGames)
        ..where.homeTeam.name = whereContains("Minn");
      var results = await q.fetch();

      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            {"id": 1, "name": "Wisconsin", "awayGames": []},
            {"id": 2, "name": "Minnesota", "awayGames": []},
            {
              "id": 3,
              "name": "Iowa",
              "awayGames": [
                {
                  "id": 3,
                  "homeScore": 0,
                  "awayScore": 3,
                  "awayTeam": {"id": 3},
                  "homeTeam": {"id": 2}
                }
              ]
            },
          ]));
    });
  });
}

class Game extends ManagedObject<_Game> implements _Game {}

class _Game {
  @primaryKey
  int id;

  int homeScore;
  int awayScore;

  @Relate(#homeGames)
  Team homeTeam;

  @Relate(#awayGames)
  Team awayTeam;
}

class Team extends ManagedObject<_Team> implements _Team {}

class _Team {
  @primaryKey
  int id;

  String name;

  ManagedSet<Game> homeGames;
  ManagedSet<Game> awayGames;
}

Future populateGameSchedule() async {
  var teams = [
    new Team()..name = "Wisconsin",
    new Team()..name = "Minnesota",
    new Team()..name = "Iowa",
  ];

  for (var t in teams) {
    var q = new Query<Team>()..values = t;
    t.id = (await q.insert()).id;
  }

  var games = [
    new Game()
      ..homeTeam = teams[0]
      ..awayTeam = teams[1]
      ..homeScore = 45
      ..awayScore = 0,
    new Game()
      ..homeTeam = teams[0]
      ..awayTeam = teams[2]
      ..homeScore = 35
      ..awayScore = 3,
    new Game()
      ..homeTeam = teams[1]
      ..awayTeam = teams[2]
      ..homeScore = 0
      ..awayScore = 3,
  ];

  for (var g in games) {
    var q = new Query<Game>()..values = g;
    await q.insert();
  }
}
