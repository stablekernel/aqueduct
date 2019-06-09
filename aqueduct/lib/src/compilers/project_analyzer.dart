import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/context_builder.dart';
import 'package:analyzer/dart/analysis/context_locator.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

class CodeAnalyzer {
  CodeAnalyzer(this.uri) {
    final locator = ContextLocator();

    final path = PhysicalResourceProvider.INSTANCE.pathContext
        .normalize(uri.toFilePath(windows: Platform.isWindows));
    final roots = locator.locateRoots(includedPaths: [path]);
    if (roots.isEmpty) {
      print("Roots:");
      print("\t${roots.map((cr) => "Packages: ${cr.packagesFile} Files: ${cr.analyzedFiles().join(", ")}").join("\n\t")}");
      throw ArgumentError(
          "no analysis context found for path '${path}'; make sure this is a directory containing Dart files or a Dart file");
    }

    if (roots.length > 1) {
      throw ArgumentError(
          "directory contains multiple possible analysis contexts; make sure only one project is in the path '${path}");
    }

    final projectRoot = roots.first;
    if (projectRoot.packagesFile == null) {
      throw StateError("No .packages file found. Run 'pub get'.");
    }

    context = ContextBuilder().createContext(contextRoot: projectRoot);
  }

  final Uri uri;
  AnalysisContext context;

  ClassDeclaration getClassFromFile(String className,
      {String relativePath, String absolutePath}) {
    return _getFileAstRoot(
            relativePath: relativePath, absolutePath: absolutePath)
        .declarations
        .whereType<ClassDeclaration>()
        .firstWhere((c) => c.name.name == className, orElse: () => null);
  }

  List<ClassDeclaration> getSubclassesFromFile(String superclassName,
      {String relativePath, String absolutePath}) {
    return _getFileAstRoot(
            relativePath: relativePath, absolutePath: absolutePath)
        .declarations
        .whereType<ClassDeclaration>()
        .where((c) => c.extendsClause.superclass.name.name == superclassName)
        .toList();
  }

  CompilationUnit _getFileAstRoot({String relativePath, String absolutePath}) {
    String path;
    if (relativePath != null) {
      var p = relativePath;
      while (p.startsWith("/")) {
        p = p.substring(1);
      }

      path = "${context.contextRoot.root.path}/$relativePath";
    } else {
      path = absolutePath;
    }

    path = PhysicalResourceProvider.INSTANCE.pathContext.normalize(path);
    final unit = context.currentSession.getParsedUnit(path);

    if (unit.errors.isNotEmpty) {
      throw StateError(
          "Project file '${relativePath}' could not be analysed for the following reasons:\n\t${unit.errors.join("\n\t")}");
    }

    return unit.unit;
  }
}

class ProjectAnalyzer extends CodeAnalyzer {
  ProjectAnalyzer(Uri projectUri) : super(projectUri) {
    if (context.contextRoot.packagesFile.parent.toUri() != projectUri) {
      throw StateError(
          "No .packages file found in project directory. Run 'pub get'.");
    }
  }
}
