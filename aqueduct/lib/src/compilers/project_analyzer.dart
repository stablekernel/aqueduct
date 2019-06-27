import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

class CodeAnalyzer {
  CodeAnalyzer(this.uri) {
    if (!uri.isAbsolute) {
      throw ArgumentError("'uri' must be absolute for CodeAnalyzer");
    }

    contexts = AnalysisContextCollection(includedPaths: [path]);
    if (contexts.contexts.isEmpty) {
      throw ArgumentError("no analysis context found for path '${path}'");
    }
  }

  String get path {
    return _getPath(uri);
  }

  final Uri uri;

  AnalysisContextCollection contexts;

  ClassDeclaration getClassFromFile(String className, Uri fileUri) {
    return _getFileAstRoot(fileUri)
        .declarations
        .whereType<ClassDeclaration>()
        .firstWhere((c) => c.name.name == className, orElse: () => null);
  }

  List<ClassDeclaration> getSubclassesFromFile(
      String superclassName, Uri fileUri) {
    return _getFileAstRoot(fileUri)
        .declarations
        .whereType<ClassDeclaration>()
        .where((c) => c.extendsClause.superclass.name.name == superclassName)
        .toList();
  }

  CompilationUnit _getFileAstRoot(Uri fileUri) {
    final path = _getPath(fileUri);

    final unit = contexts.contextFor(path).currentSession.getParsedUnit(path);

    if (unit.errors.isNotEmpty) {
      throw StateError(
          "Project file '${path}' could not be analysed for the following reasons:\n\t${unit.errors.join("\n\t")}");
    }

    return unit.unit;
  }


  static String _getPath(Uri inputUri) {
    return PhysicalResourceProvider.INSTANCE.pathContext.normalize(PhysicalResourceProvider.INSTANCE.pathContext.fromUri(inputUri));
  }
}
