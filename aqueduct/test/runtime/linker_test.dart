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
  Terminal template;
  Terminal terminal;

  setUpAll(() async {
    template = await Terminal.createProject();
    await template.getDependencies(offline: true);
  });

  setUp(() async {
    terminal = template.replicate();
    runner = Runner(terminal);
  });

  tearDownAll(() async {
    Terminal.deleteTemporaryDirectory();
  });

  test("Can generate validly linked project + runtime + framework",
      () async {
      await runner.run();
      final appTerminal = Terminal(Directory.fromUri(terminal.workingDirectory.uri.resolve("out/").resolve("app/")));
      await appTerminal.getDependencies();
      await runner.ensureValidSyntax();
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
    final buildDirPath = terminal.workingDirectory.uri.resolve("out").toString();
    await Isolate.spawnUri(
      dataUri, [buildDirPath], null,
      packageConfig: terminal.workingDirectory.uri.resolve(".packages"),
      errorsAreFatal: true,
      onExit: onExit.sendPort);
    await onExit.first;

    analyzer =
      CodeAnalyzer(terminal.workingDirectory.absolute.uri.resolve("out/").resolve("app/"));
  }

  Future ensureValidSyntax() async {
    await Future.forEach(analyzer.contexts.contexts,
        (AnalysisContext ctx) async {
        final files = ctx.contextRoot.analyzedFiles().where((name) => name.endsWith(".dart"));
        await Future.forEach(files, (String file) async {
          final msgs = await ctx.currentSession.getErrors(file);
          final errors =
          msgs.errors.where((e) => e.severity == Severity.error).toList();
          if (errors.isNotEmpty) {
            print(
              "${msgs.errors.map((e) => "${e.source.uri}:${e.offset}: ${e.message}").join("\n")}");
          }
          expect(errors.isEmpty, true);
        });
      });
  }

  String get _script => """
import 'dart:io';
import 'dart:async';

import 'package:application_test/application_test.dart';
import 'package:aqueduct/src/runtime/loader.dart';
import 'package:aqueduct/src/runtime/linker.dart';

Future main(List<String> args) async {
  final uri = Uri.parse(args.first);
  final buildDir = Directory.fromUri(uri)..createSync();
  final generator = RuntimeLoader.createGenerator();
  await generator.writeTo(buildDir.uri.resolve("runtime/"));

  final linker = RuntimeLinker(buildDir.parent.uri, buildDir.uri.resolve("runtime/").resolve("loader.dart"));
  await linker.link(buildDir.uri);
}
""";
}
