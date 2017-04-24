import 'package:test/test.dart';
import 'dart:io';
import '../cli_helpers.dart';

void main() {
  group("Invalid schema changes", () {
    var projectSourceDirectory = getTestProjectDirectory("initial");
    Directory projectDirectory = new Directory("test_project");

    var replaceLibraryFileWith = (String contents) {
      var f = new File.fromUri(projectDirectory.uri.resolve("lib/").resolve("wildfire.dart"));
      contents = "import 'package:aqueduct/aqueduct.dart';\n" + contents;
      f.writeAsStringSync(contents);
    };

    setUp(() async {
      createTestProject(projectSourceDirectory, projectDirectory);
    });

    tearDown(() {
      projectDirectory.deleteSync(recursive: true);
    });

    test("Cannot delete primary key column", () async {
      var code = [
        """
        class U extends ManagedObject<_U> implements _U {}
        class _U {
          @managedPrimaryKey int id;
          int foo;
        }
        """,
        """
        class U extends ManagedObject<_U> implements _U {}
        class _U {
          int id;
          @managedPrimaryKey int foo;
        }
        """
      ];

      await runPubGet(projectDirectory, offline: true);

      replaceLibraryFileWith(code.first);
      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

      replaceLibraryFileWith(code.last);
      res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, isNot(0));
      expect(res.output, contains("Cannot change primary key of '_U'"));
    });

    test("Cannot change relatedTable", () async {
      var code = [
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @managedPrimaryKey int id;
          T x;
        }
        class T extends ManagedObject<_T> {}
        class _T {
          @managedPrimaryKey int id;
          @ManagedRelationship(#x)
          U y;
        }
        """,
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @managedPrimaryKey int id;
        }
        class T extends ManagedObject<_T> {}
        class _T {
          @managedPrimaryKey int id;
          @ManagedRelationship(#x)
          V y;
        }
        class V extends ManagedObject<_V> {}
        class _V {
          @managedPrimaryKey int id;
          T x;
        }
        """
      ];

      await runPubGet(projectDirectory, offline: true);

      replaceLibraryFileWith(code.first);
      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

      replaceLibraryFileWith(code.last);
      res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, isNot(0));
      expect(res.output, contains("Cannot change type of '_T.y'"));
    });

    test("Cannot generate without primary key", () async {
      var code = [
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @managedPrimaryKey int id;
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

      await runPubGet(projectDirectory, offline: true);

      replaceLibraryFileWith(code.first);
      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

      replaceLibraryFileWith(code.last);
      res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, isNot(0));
      expect(res.output, contains("Class '_U' doesn't declare a primary key property"));
    });

    test("Cannot change primaryKey", () async {
      var code = [
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @managedPrimaryKey int id;
          int x;
        }
        """,
        """
        class U extends ManagedObject<_U> {}
        class _U {
          int id;
          @managedPrimaryKey int x;
        }
        """
      ];

      await runPubGet(projectDirectory, offline: true);

      replaceLibraryFileWith(code.first);
      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

      replaceLibraryFileWith(code.last);
      res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, isNot(0));
      expect(res.output, contains("Cannot change primary key of '_U'"));
    });

    test("Cannot change autoincrement", () async {
      var code = [
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @managedPrimaryKey int id;
          int x;
        }
        """,
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @managedPrimaryKey int id;

          @ManagedColumnAttributes(autoincrement: true)
          int x;
        }
        """
      ];

      await runPubGet(projectDirectory, offline: true);

      replaceLibraryFileWith(code.first);
      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

      replaceLibraryFileWith(code.last);
      res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, isNot(0));
      expect(res.output, contains("Cannot change autoincrement behavior of '_U.x'"));
    });

    test("Cannot change type", () async {
      var code = [
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @managedPrimaryKey int id;
          int x;
        }
        """,
        """
        class U extends ManagedObject<_U> {}
        class _U {
          @managedPrimaryKey int id;

          String x;
        }
        """
      ];

      await runPubGet(projectDirectory, offline: true);

      replaceLibraryFileWith(code.first);
      var res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, 0);

      replaceLibraryFileWith(code.last);
      res = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(res.exitCode, isNot(0));
      expect(res.output, contains("Cannot change type of '_U.x'"));
    });
  });
}