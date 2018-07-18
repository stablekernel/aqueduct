// ignore: unnecessary_const
@Tags(const ["cli"])
import 'package:test/test.dart';
import 'cli_helpers.dart';

void main() {
  group("Invalid schema changes", () {
    Terminal terminal;

    setUp(() async {
      terminal = await Terminal.createProject();
    });

    tearDown(Terminal.deleteTemporaryDirectory);

    test("Cannot delete primary key column", () async {
      final code = [
        """        
        class U extends ManagedObject<_U> implements _U {}
        class _U {
          @primaryKey int id;
          int foo;
        }
        """,
        """
        class U extends ManagedObject<_U> implements _U {}
        class _U {
          int id;
          int foo;
        }
        """
      ];

      await terminal.getDependencies(offline: true);

      terminal.addOrReplaceFile("lib/test_application.dart", code.first);
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);
      terminal.clearOutput();

      terminal.addOrReplaceFile("lib/application_test.dart", code.last);
      res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, isNot(0));
      expect(
          terminal.output, contains("doesn't declare a primary key property"));
    });

    test("Cannot change relatedTable", () async {
      final code = [
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @primaryKey int id;
          T x;
        }
        class T extends ManagedObject<_T> {}
        class _T {
          @primaryKey int id;
          @Relate(#x)
          U y;
        }
        """,
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @primaryKey int id;
        }
        class T extends ManagedObject<_T> {}
        class _T {
          @primaryKey int id;
          @Relate(#x)
          V y;
        }
        class V extends ManagedObject<_V> {}
        class _V {
          @primaryKey int id;
          T x;
        }
        """
      ];

      await terminal.getDependencies(offline: true);

      terminal.addOrReplaceFile("lib/application_test.dart", code.first);
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);
      terminal.clearOutput();

      terminal.addOrReplaceFile("lib/application_test.dart", code.last);
      res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, isNot(0));
      expect(terminal.output, contains("Cannot change type of '_T.y'"));
    });

    test("Cannot generate without primary key", () async {
      final code = [
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @primaryKey int id;
          int x;
        }
        """,
        """
        class U extends ManagedObject<_U> {}
        class _U {
          int id;
          int x;
        }
        """
      ];

      await terminal.getDependencies(offline: true);

      terminal.addOrReplaceFile("lib/application_test.dart", code.first);
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);
      terminal.clearOutput();

      terminal.addOrReplaceFile("lib/application_test.dart", code.last);
      res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, isNot(0));
      expect(terminal.output,
          contains("Class '_U' doesn't declare a primary key property"));
    });

    test("Cannot change primaryKey", () async {
      var code = [
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @primaryKey int id;
          int x;
        }
        """,
        """
        class U extends ManagedObject<_U> {}
        class _U {
          int id;
          @primaryKey int x;
        }
        """
      ];

      await terminal.getDependencies(offline: true);

      terminal.addOrReplaceFile("lib/application_test.dart", code.first);
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);
      terminal.clearOutput();

      terminal.addOrReplaceFile("lib/application_test.dart", code.last);
      res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, isNot(0));
      expect(terminal.output, contains("Cannot change primary key of '_U'"));
    });

    test("Cannot change autoincrement", () async {
      var code = [
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @primaryKey int id;
          int x;
        }
        """,
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @primaryKey int id;

          @Column(autoincrement: true)
          int x;
        }
        """
      ];

      await terminal.getDependencies(offline: true);

      terminal.addOrReplaceFile("lib/application_test.dart", code.first);
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);
      terminal.clearOutput();

      terminal.addOrReplaceFile("lib/application_test.dart", code.last);
      res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, isNot(0));
      expect(terminal.output,
          contains("Cannot change autoincrement behavior of '_U.x'"));
    });

    test("Cannot change type", () async {
      var code = [
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @primaryKey int id;
          int x;
        }
        """,
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @primaryKey int id;

          String x;
        }
        """
      ];

      await terminal.getDependencies(offline: true);

      terminal.addOrReplaceFile("lib/application_test.dart", code.first);
      var res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, 0);
      terminal.clearOutput();

      terminal.addOrReplaceFile("lib/application_test.dart", code.last);
      res = await terminal.runAqueductCommand("db", ["generate"]);
      expect(res, isNot(0));
      expect(terminal.output, contains("Cannot change type of '_U.x'"));
    });
  });
}
