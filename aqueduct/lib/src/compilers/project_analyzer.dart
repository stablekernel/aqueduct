import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

class CodeAnalyzer {
  CodeAnalyzer(this.uri) {
    if (!uri.isAbsolute) {
      throw ArgumentError("'uri' must be absolute for CodeAnalyzer");
    }

    // A leading slash is being added to path somewhere when running cli commands
    // double-check that project analyzer tests and mgiration soruce tests work to narrow this down to cli only

    contexts = AnalysisContextCollection(includedPaths: [path]);
    if (contexts.contexts.isEmpty) {
      throw ArgumentError("no analysis context found for path '${path}'");
    }

    print("${contexts.contexts.map((c) => "${c.contextRoot.root.path}:"+ c.analyzedFiles().join(", ")).join("\n\n")}");
  }

  String get path {
    return _fixPath(PhysicalResourceProvider.INSTANCE.pathContext.normalize(PhysicalResourceProvider.INSTANCE.pathContext.fromUri(uri)));
  }

  final Uri uri;

  AnalysisContextCollection contexts;

  ClassDeclaration getClassFromFile(String className, String absolutePath) {
    return _getFileAstRoot(absolutePath)
        .declarations
        .whereType<ClassDeclaration>()
        .firstWhere((c) => c.name.name == className, orElse: () => null);
  }

  List<ClassDeclaration> getSubclassesFromFile(
      String superclassName, String absolutePath) {
    return _getFileAstRoot(absolutePath)
        .declarations
        .whereType<ClassDeclaration>()
        .where((c) => c.extendsClause.superclass.name.name == superclassName)
        .toList();
  }

  CompilationUnit _getFileAstRoot(String absolutePath) {
    final path =
        PhysicalResourceProvider.INSTANCE.pathContext.normalize(absolutePath);
    print("${absolutePath} -> $path -> ${_fixPath(path)}");
    final unit = contexts.contextFor(path).currentSession.getParsedUnit(_fixPath(path));

    if (unit.errors.isNotEmpty) {
      throw StateError(
          "Project file '${path}' could not be analysed for the following reasons:\n\t${unit.errors.join("\n\t")}");
    }

    return unit.unit;
  }

  String _fixPath(String inputPath) {
    var p = inputPath;
    if (Platform.isWindows) {
      while (p.startsWith("/")) {
        p = p.substring(1);
      }
    }
    return p;
  }
}
