import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:aqueduct/src/compilers/project_analyzer.dart';
import 'package:test/test.dart';

import '../command/cli_helpers.dart';

void main() {
  Runner runner;
  Terminal terminal;

  setUpAll(() async {
    terminal = await Terminal.createProject();
    await terminal.getDependencies(offline: true);
    runner = Runner(terminal);
  });

  setUp(() async {
    await terminal.restoreDefaultTestProject();
  });

  tearDownAll(() async {
    Terminal.deleteTemporaryDirectory();
  });

  test("Can generate runtimes for channel and controllers (no ORM types)", () async {
    await runner.run();
    await runner.ensureValidSyntax();

    expect(Directory.fromUri(terminal.workingDirectory.uri.resolve("out/").resolve("channelruntime/")).existsSync(), true);
    expect(Directory.fromUri(terminal.workingDirectory.uri.resolve("out/").resolve("controllerruntime/")).existsSync(), true);
    expect(Directory.fromUri(terminal.workingDirectory.uri.resolve("out/").resolve("managedentityruntime/")).existsSync(), false);
  });

  test("If no channel exists, no channel runtime created", () async {
    terminal.modifyFile("lib/channel.dart", (original) {
      return "";
    });
    await runner.run();
    await runner.ensureValidSyntax();

    expect(Directory.fromUri(terminal.workingDirectory.uri.resolve("out/").resolve("controllerruntime/")).existsSync(), true);
    expect(Directory.fromUri(terminal.workingDirectory.uri.resolve("out/").resolve("channelruntime/")).existsSync(), false);
    expect(Directory.fromUri(terminal.workingDirectory.uri.resolve("out/").resolve("managedentityruntime/")).existsSync(), false);
  });

  test("Can generate ORM runtimes", () async {
    terminal.modifyFile("lib/channel.dart", (src) {
      return "import 'package:application_test/model/model1.dart';\nimport 'package:application_test/model/model2.dart';\n$src";
    });
    terminal.addOrReplaceFile("lib/model/model1.dart", """
    import 'package:aqueduct/aqueduct.dart';
    class M1 extends ManagedObject<_M1> {}
    class _M1 { @primaryKey int id; }
    """);
    terminal.addOrReplaceFile("lib/model/model2.dart", """
    import 'package:aqueduct/aqueduct.dart';
    class M2 extends ManagedObject<_M2> {}
    class _M2 { @primaryKey int id; }
    """);

    await runner.run();
    await runner.ensureValidSyntax();

    expect(Directory.fromUri(terminal.workingDirectory.uri.resolve("out/").resolve("controllerruntime/")).existsSync(), true);
    expect(Directory.fromUri(terminal.workingDirectory.uri.resolve("out/").resolve("channelruntime/")).existsSync(), true);

    final moDir = Directory.fromUri(terminal.workingDirectory.uri.resolve("out/").resolve("managedentityruntime/"));
    expect(moDir.existsSync(), true);
    expect(moDir.listSync().length, 2);
  });
}

class Runner {
  Runner(this.terminal);

  final Terminal terminal;
  CodeAnalyzer analyzer;

  Future run() async {
    final dataUri = Uri.parse(
        "data:application/dart;charset=utf-8,${Uri.encodeComponent(_script)}");

    final onExit = ReceivePort();
    await Isolate.spawnUri(
        dataUri, [terminal.workingDirectory.uri.toString()], null,
        packageConfig: terminal.workingDirectory.uri.resolve(".packages"),
        errorsAreFatal: true,
        onExit: onExit.sendPort);
    await onExit.first;

    analyzer = CodeAnalyzer(terminal.workingDirectory.absolute.uri.resolve("out/"));
  }

  Future ensureValidSyntax() async {
    await Future.forEach(analyzer.contexts.contexts, (AnalysisContext ctx) async {
      final files = ctx.contextRoot.analyzedFiles();
      await Future.forEach(files, (String file) async {
        final msgs = await ctx.currentSession.getErrors(file);
        final errors = msgs.errors.where((e) => e.severity == Severity.error).toList();
        if (errors.isNotEmpty) {
          print("${msgs.errors.map((e) => "${e.source.uri}:${e.offset}: ${e.message}").join("\n")}");
        }
        expect(errors.isEmpty, true);
      });
    });
  }

  String get _script => """
import 'package:application_test/application_test.dart';
import 'package:aqueduct/src/runtime/loader.dart';

Future main(List<String> args) async {
  final uri = Uri.parse(args.first);
  final generator = RuntimeLoader.createGenerator();
  await generator.writeTo(uri.resolve("out/"));
}
""";
}
