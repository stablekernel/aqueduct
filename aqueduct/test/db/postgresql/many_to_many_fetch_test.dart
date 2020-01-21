import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';
import 'package:aqueduct/src/dev/model_graph.dart';

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
    await populateGameSchedule(ctx);
  });

  tearDownAll(() async {
    await ctx.close();
  });

  group("Explicit joins", () {
    test("Can join across many to many relationship, from one side", () async {
      var q = Query<RootObject>(ctx)
        ..sortBy((r) => r.rid, QuerySortOrder.ascending);

      q.join(set: (r) => r.join).join(object: (r) => r.other);
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
      var q = Query<OtherRootObject>(ctx)
        ..sortBy((o) => o.id, QuerySortOrder.ascending);

      q.join(set: (r) => r.join).join(object: (r) => r.root);
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
      var q = Query<RootJoinObject>(ctx)
        ..sortBy((r) => r.id, QuerySortOrder.ascending)
        ..join(object: (r) => r.other)
        ..join(object: (r) => r.root);

      var results = await q.fetch();
      expect(
          results.map((r) => r.asMap()).toList(),
          equals([
            {
              "id": 1,
              "other": fullObjectMap(OtherRootObject, 1),
              "root": fullObjectMap(RootObject, 1)
            },
            {
              "id": 2,
              "other": fullObjectMap(OtherRootObject, 2),
              "root": fullObjectMap(RootObject, 1)
            },
            {
              "id": 3,
              "other": fullObjectMap(OtherRootObject, 3),
              "root": fullObjectMap(RootObject, 2)
            },
          ]));
    });
  });

  group("Implicit joins", () {
    test("Can use implicit matcher across many to many table", () async {
      var q = Query<RootObject>(ctx)
        ..sortBy((r) => r.rid, QuerySortOrder.ascending);
      //..where((o) => o.join.haveAtLeastOneWhere.other.value1).lessThan(4);

      var results = await q.fetch();
      expect(results.map((r) => r.asMap()).toList(),
          equals([fullObjectMap(RootObject, 1), fullObjectMap(RootObject, 2)]));

      // q.where((o) => o.join.haveAtLeastOneWhere.other.value1).equalTo(3);
      results = await q.fetch();
      expect(results.map((r) => r.asMap()).toList(),
          equals([fullObjectMap(RootObject, 2)]));
    }, skip: "#481");

    test("Can use implicit join with join table to one side", () async {
      var q = Query<RootJoinObject>(ctx)
        ..where((o) => o.root.value1).equalTo(1);
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
      var q = Query<RootJoinObject>(ctx)
        ..where((o) => o.root.value1).equalTo(1)
        ..where((o) => o.other.value1).equalTo(1);
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

      q = Query<RootJoinObject>(ctx)
        ..where((o) => o.root.value1).equalTo(1)
        ..where((o) => o.other.value1).equalTo(2);
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

      q = Query<RootJoinObject>(ctx)
        ..where((o) => o.root.value1).equalTo(2)
        ..where((o) => o.other.value1).equalTo(2);
      results = await q.fetch();
      expect(results.map((r) => r.asMap()).toList(), equals([]));
    });
  });

  group("Self joins - standard", () {
    test("Can join by one relationship", () async {
      var q = Query<Team>(ctx)..sortBy((t) => t.id, QuerySortOrder.ascending);

      q.join(set: (t) => t.awayGames).join(object: (g) => g.homeTeam);

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
      var q = Query<Team>(ctx)..sortBy((t) => t.id, QuerySortOrder.ascending);

      q.join(set: (t) => t.homeGames).join(object: (g) => g.awayTeam);
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
      var q = Query<Game>(ctx)
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
        var q = Query<Team>(ctx);

        q.join(set: (t) => t.homeGames).join(object: (g) => g.homeTeam);
        expect(true, false);
      } on StateError catch (e) {
        expect(e.toString(), contains("Invalid query construction"));
      }
    });
  });

  group("Self joins - implicit", () {
    test("Can implicit join through join table", () async {
      // 'Teams that have played at Minnesota'
      var q = Query<Team>(ctx)..sortBy((t) => t.id, QuerySortOrder.ascending);
//        ..where((o) => o.awayGames.haveAtLeastOneWhere.homeTeam.name)
//            .contains("Minn");
      var results = await q.fetch();
      expect(
          results.map((t) => t.asMap()).toList(),
          equals([
            {"id": 3, "name": "Iowa"}
          ]));

      // 'Teams that have played at Iowa'
      q = Query<Team>(ctx)..sortBy((t) => t.id, QuerySortOrder.ascending);
//        ..where((o) => o.awayGames.haveAtLeastOneWhere.homeTeam.name)
//            .contains("Iowa");
      results = await q.fetch();
      expect(results.map((t) => t.asMap()).toList(), equals([]));
    }, skip: "#481");

    test("Can implicit join from join table - one side", () async {
      // 'Games where Iowa was away'
      var q = Query<Game>(ctx)..where((o) => o.awayTeam.name).contains("Iowa");
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
      var q = Query<Game>(ctx)
        ..where((o) => o.homeTeam.name).contains("Wisco")
        ..where((o) => o.awayTeam.name).contains("Iowa");
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
        "Join on to-many, with where clause on joined table that acesses parent table",
        () async {
      // 'All teams and their away games where %Minn% is away team'
      var q = Query<Team>(ctx);
      q
          .join(set: (t) => t.awayGames)
          .where((o) => o.awayTeam.name)
          .contains("Minn");
      var results = await q.fetch();
      expect(results.length, 3);
      expect(
          results.firstWhere((t) => t.name == "Minnesota").awayGames.length, 1);
      expect(
          results
              .where((t) => t.name != "Minnesota")
              .every((t) => t.awayGames.isEmpty),
          true);

      // All teams and their games played at %Minn%
      q = Query<Team>(ctx);
      q
          .join(set: (t) => t.awayGames)
          .where((o) => o.homeTeam.name)
          .contains("Minn");
      results = await q.fetch();
      expect(results.length, 3);
      expect(results.firstWhere((t) => t.name == "Iowa").awayGames.length, 1);
      expect(
          results
              .where((t) => t.name != "Iowa")
              .every((t) => t.awayGames.isEmpty),
          true);
    });
  });

  group("Self joins - standard + filter", () {
    test("Can filter returned nested objects by their values", () async {
      // 'All teams and the games they've played at Minnesota'
      var q = Query<Team>(ctx);
      q
          .join(set: (t) => t.awayGames)
          .where((o) => o.homeTeam.name)
          .contains("Minn");
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

  @Relate(Symbol('homeGames'))
  Team homeTeam;

  @Relate(Symbol('awayGames'))
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

Future populateGameSchedule(ManagedContext ctx) async {
  var teams = [
    Team()..name = "Wisconsin",
    Team()..name = "Minnesota",
    Team()..name = "Iowa",
  ];

  for (var t in teams) {
    var q = Query<Team>(ctx)..values = t;
    t.id = (await q.insert()).id;
  }

  var games = [
    Game()
      ..homeTeam = teams[0] // Wisconsin
      ..awayTeam = teams[1] // Minnesota
      ..homeScore = 45
      ..awayScore = 0,
    Game()
      ..homeTeam = teams[0] // Wisconsin
      ..awayTeam = teams[2] // Iowa
      ..homeScore = 35
      ..awayScore = 3,
    Game()
      ..homeTeam = teams[1] // Minnesota
      ..awayTeam = teams[2] // Iowa
      ..homeScore = 0
      ..awayScore = 3,
  ];

  for (var g in games) {
    var q = Query<Game>(ctx)..values = g;
    await q.insert();
  }
}
