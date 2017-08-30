import "package:test/test.dart";
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/http/route_specification.dart';

import '../../lib/src/http/route_node.dart';

void main() {
  group("Pattern splitting", () {
    test("No optionals, no expressions", () {
      expect(_segmentsForRoute("/"), [
        [new RouteSegment.direct(literal: "")]
      ]);
      expect(_segmentsForRoute("/a"), [
        [new RouteSegment.direct(literal: "a")]
      ]);
      expect(_segmentsForRoute("/a/b"), [
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(literal: "b")
        ]
      ]);
      expect(_segmentsForRoute("/a/:b"), [
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(variableName: "b")
        ]
      ]);
      expect(_segmentsForRoute("/abcd/:efgh/*"), [
        [
          new RouteSegment.direct(literal: "abcd"),
          new RouteSegment.direct(variableName: "efgh"),
          new RouteSegment.direct(matchesAnything: true)
        ]
      ]);
    });

    test("With expressions, no optionals", () {
      expect(_segmentsForRoute("/(\\d+)"), [
        [new RouteSegment.direct(expression: r"\d+")]
      ]);
      expect(_segmentsForRoute("/a/(\\d+)"), [
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(expression: r"\d+")
        ]
      ]);
      expect(_segmentsForRoute("/a/:id/(\\d+)"), [
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(variableName: "id"),
          new RouteSegment.direct(expression: r"\d+")
        ]
      ]);
    });

    test("With expressions that look like optionals and remaining paths", () {
      expect(_segmentsForRoute("/([^x]*)"), [
        [new RouteSegment.direct(expression: r"[^x]*")]
      ]);
      expect(_segmentsForRoute("/a/([^x])"), [
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(expression: "[^x]")
        ]
      ]);
      expect(_segmentsForRoute("/a/:id/([^\\]])"), [
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(variableName: "id"),
          new RouteSegment.direct(expression: r"[^\]]")
        ]
      ]);
    });

    test("Optionals, no expressions", () {
      expect(_segmentsForRoute("/[a]"), [
        [new RouteSegment.direct(literal: "")],
        [new RouteSegment.direct(literal: "a")]
      ]);
      expect(_segmentsForRoute("/a[/:b]"), [
        [new RouteSegment.direct(literal: "a")],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(variableName: "b")
        ]
      ]);
      expect(_segmentsForRoute("/a[/b[/c]]"), [
        [new RouteSegment.direct(literal: "a")],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(literal: "b")
        ],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(literal: "b"),
          new RouteSegment.direct(literal: "c")
        ]
      ]);
      expect(_segmentsForRoute("/a[/b/c]"), [
        [new RouteSegment.direct(literal: "a")],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(literal: "b"),
          new RouteSegment.direct(literal: "c")
        ]
      ]);
      expect(_segmentsForRoute("/a[/ba/:cef]"), [
        [new RouteSegment.direct(literal: "a")],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(literal: "ba"),
          new RouteSegment.direct(variableName: "cef")
        ]
      ]);
      expect(_segmentsForRoute("/a[/*]"), [
        [new RouteSegment.direct(literal: "a")],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(matchesAnything: true)
        ]
      ]);

      expect(_segmentsForRoute("/a/[b]"), [
        [new RouteSegment.direct(literal: "a")],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(literal: "b")
        ]
      ]);
    });

    test("Optionals with expression", () {
      expect(_segmentsForRoute("/[(any)]"), [
        [new RouteSegment.direct(literal: "")],
        [new RouteSegment.direct(expression: "any")],
      ]);
      expect(_segmentsForRoute("/a[/:b(a*)]"), [
        [new RouteSegment.direct(literal: "a")],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(variableName: "b", expression: "a*")
        ]
      ]);

      expect(_segmentsForRoute("/a[/b[/:c(x)]]"), [
        [new RouteSegment.direct(literal: "a")],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(literal: "b")
        ],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(literal: "b"),
          new RouteSegment.direct(variableName: "c", expression: "x")
        ]
      ]);

      expect(_segmentsForRoute("/a[/:b(^x)[/*]]"), [
        [new RouteSegment.direct(literal: "a")],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(variableName: "b", expression: "^x")
        ],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(variableName: "b", expression: "^x"),
          new RouteSegment.direct(matchesAnything: true)
        ]
      ]);
    });

    test("Optionals with expressions that look like optionals", () {
      expect(_segmentsForRoute("/a[/([^x])]"), [
        [new RouteSegment.direct(literal: "a")],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(expression: "[^x]")
        ]
      ]);
      expect(_segmentsForRoute("/a[/:b([^x])]"), [
        [new RouteSegment.direct(literal: "a")],
        [
          new RouteSegment.direct(literal: "a"),
          new RouteSegment.direct(variableName: "b", expression: "[^x]")
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

void expectRouterException(void f(), {String exceptionMessage: null}) {
  try {
    f();
    fail("Expected RouterException");
  } on RouterException catch (e) {
    if (exceptionMessage != null) {
      expect(e.message, exceptionMessage);
    }
  }
}

List<List<RouteSegment>> _segmentsForRoute(String route) {
  return RouteSpecification
      .specificationsForRoutePattern(route)
      .map((spec) => spec.segments)
      .map((segs) => segs as List<RouteSegment>)
      .toList();
}
