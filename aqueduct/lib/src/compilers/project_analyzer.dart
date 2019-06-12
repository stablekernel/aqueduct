import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

class CodeAnalyzer {
  CodeAnalyzer(this.uri) {
    if (!uri.isAbsolute) {
      throw ArgumentError("'uri' must be absolute for CodeAnalyzer");
    }

    final path =
        PhysicalResourceProvider.INSTANCE.pathContext.normalize(uri.toFilePath(windows: Platform.isWindows));
    contexts = AnalysisContextCollection(includedPaths: [path]);
    if (contexts.contexts.isEmpty) {
      throw ArgumentError("no analysis context found for path '${path}' (from ${uri.toFilePath(windows: Platform.isWindows)})");
    }
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
    final unit = contexts.contextFor(path).currentSession.getParsedUnit(path);

    if (unit.errors.isNotEmpty) {
      throw StateError(
          "Project file '${path}' could not be analysed for the following reasons:\n\t${unit.errors.join("\n\t")}");
    }

    return unit.unit;
  }
}
