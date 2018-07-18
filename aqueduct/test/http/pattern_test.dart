import 'package:aqueduct/src/http/route_node.dart';
import "package:test/test.dart";
import 'package:aqueduct/src/http/route_specification.dart';

void main() {
  group("Pattern splitting", () {
    test("No optionals, no expressions", () {
      expect(_segmentsForRoute("/"), [
        [RouteSegment.direct(literal: "")]
      ]);
      expect(_segmentsForRoute("/a"), [
        [RouteSegment.direct(literal: "a")]
      ]);
      expect(_segmentsForRoute("/a/b"), [
        [RouteSegment.direct(literal: "a"), RouteSegment.direct(literal: "b")]
      ]);
      expect(_segmentsForRoute("/a/:b"), [
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(variableName: "b")
        ]
      ]);
      expect(_segmentsForRoute("/abcd/:efgh/*"), [
        [
          RouteSegment.direct(literal: "abcd"),
          RouteSegment.direct(variableName: "efgh"),
          RouteSegment.direct(matchesAnything: true)
        ]
      ]);
    });

    test("With expressions, no optionals", () {
      expect(_segmentsForRoute("/(\\d+)"), [
        [RouteSegment.direct(expression: r"\d+")]
      ]);
      expect(_segmentsForRoute("/a/(\\d+)"), [
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(expression: r"\d+")
        ]
      ]);
      expect(_segmentsForRoute("/a/:id/(\\d+)"), [
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(variableName: "id"),
          RouteSegment.direct(expression: r"\d+")
        ]
      ]);
    });

    test("With expressions that look like optionals and remaining paths", () {
      expect(_segmentsForRoute("/([^x]*)"), [
        [RouteSegment.direct(expression: r"[^x]*")]
      ]);
      expect(_segmentsForRoute("/a/([^x])"), [
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(expression: "[^x]")
        ]
      ]);
      expect(_segmentsForRoute("/a/:id/([^\\]])"), [
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(variableName: "id"),
          RouteSegment.direct(expression: r"[^\]]")
        ]
      ]);
    });

    test("Optionals, no expressions", () {
      expect(_segmentsForRoute("/[a]"), [
        [RouteSegment.direct(literal: "")],
        [RouteSegment.direct(literal: "a")]
      ]);
      expect(_segmentsForRoute("/a[/:b]"), [
        [RouteSegment.direct(literal: "a")],
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(variableName: "b")
        ]
      ]);
      expect(_segmentsForRoute("/a[/b[/c]]"), [
        [RouteSegment.direct(literal: "a")],
        [RouteSegment.direct(literal: "a"), RouteSegment.direct(literal: "b")],
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(literal: "b"),
          RouteSegment.direct(literal: "c")
        ]
      ]);
      expect(_segmentsForRoute("/a[/b/c]"), [
        [RouteSegment.direct(literal: "a")],
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(literal: "b"),
          RouteSegment.direct(literal: "c")
        ]
      ]);
      expect(_segmentsForRoute("/a[/ba/:cef]"), [
        [RouteSegment.direct(literal: "a")],
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(literal: "ba"),
          RouteSegment.direct(variableName: "cef")
        ]
      ]);
      expect(_segmentsForRoute("/a[/*]"), [
        [RouteSegment.direct(literal: "a")],
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(matchesAnything: true)
        ]
      ]);

      expect(_segmentsForRoute("/a/[b]"), [
        [RouteSegment.direct(literal: "a")],
        [RouteSegment.direct(literal: "a"), RouteSegment.direct(literal: "b")]
      ]);
    });

    test("Optionals with expression", () {
      expect(_segmentsForRoute("/[(any)]"), [
        [RouteSegment.direct(literal: "")],
        [RouteSegment.direct(expression: "any")],
      ]);
      expect(_segmentsForRoute("/a[/:b(a*)]"), [
        [RouteSegment.direct(literal: "a")],
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(variableName: "b", expression: "a*")
        ]
      ]);

      expect(_segmentsForRoute("/a[/b[/:c(x)]]"), [
        [RouteSegment.direct(literal: "a")],
        [RouteSegment.direct(literal: "a"), RouteSegment.direct(literal: "b")],
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(literal: "b"),
          RouteSegment.direct(variableName: "c", expression: "x")
        ]
      ]);

      expect(_segmentsForRoute("/a[/:b(^x)[/*]]"), [
        [RouteSegment.direct(literal: "a")],
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(variableName: "b", expression: "^x")
        ],
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(variableName: "b", expression: "^x"),
          RouteSegment.direct(matchesAnything: true)
        ]
      ]);
    });

    test("Optionals with expressions that look like optionals", () {
      expect(_segmentsForRoute("/a[/([^x])]"), [
        [RouteSegment.direct(literal: "a")],
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(expression: "[^x]")
        ]
      ]);
      expect(_segmentsForRoute("/a[/:b([^x])]"), [
        [RouteSegment.direct(literal: "a")],
        [
          RouteSegment.direct(literal: "a"),
          RouteSegment.direct(variableName: "b", expression: "[^x]")
        ]
      ]);
    });

    test("Unterminated optionals", () {
      expectRouterException(() {
        _segmentsForRoute("/[");
      });
      expectRouterException(() {
        _segmentsForRoute("/a/[b");
      });
      expectRouterException(() {
        _segmentsForRoute("/a[/b");
      });
      expectRouterException(() {
        _segmentsForRoute("/a/[b/[c]");
      });
    });

    test("Bad expressions", () {
      expectRouterException(() {
        _segmentsForRoute("/(()");
      });
      expectRouterException(() {
        _segmentsForRoute("/(");
      });
    });
  });
}

void expectRouterException(void f(), {String exceptionMessage}) {
  try {
    f();
    fail("Expected RouterException");
  } on ArgumentError catch (e) {
    if (exceptionMessage != null) {
      expect(e.message, exceptionMessage);
    }
  }
}

List<List<RouteSegment>> _segmentsForRoute(String route) {
  return RouteSpecification.specificationsForRoutePattern(route)
      .map((spec) => spec.segments)
      .map((segs) => segs)
      .toList();
}
