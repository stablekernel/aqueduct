import 'dart:async';
import 'dart:io';
import 'dart:mirrors' hide Comment;
import 'dart:isolate';

import 'package:analyzer/analyzer.dart';
import 'package:aqueduct/src/utilities/documented_element.dart';

class AnalyzerDocumentedElementProvider implements DocumentedElementProvider {
  @override
  Future<DocumentedElement> resolve(Type type) async {
    final reflectedType = reflectType(type);
    final uri = reflectedType.location.sourceUri;
    final resolvedUri = await Isolate.resolvePackageUri(uri);
    final fileUnit = parseDartFile(resolvedUri.toFilePath(windows: Platform.isWindows));

    var classDeclaration = fileUnit.declarations
        .where((u) => u is ClassDeclaration)
        .map((cu) => cu as ClassDeclaration)
        .firstWhere((ClassDeclaration classDecl) {
      return classDecl.name.token.lexeme == MirrorSystem.getName(reflectedType.simpleName);
    });

    return new AnalyzerDocumentedElement._(classDeclaration);
  }
}

class AnalyzerDocumentedElement extends DocumentedElement {
  AnalyzerDocumentedElement._(AnnotatedNode decl) {
    _apply(decl.documentationComment);

    if (decl is MethodDeclaration) {
      decl.parameters?.parameters?.forEach((p) {
        if (p.childEntities.length == 1 && p.childEntities.first is SimpleFormalParameter) {
          SimpleFormalParameter def = p.childEntities.first;
          children[new Symbol(p.identifier.name)] = new AnalyzerDocumentedElement._leaf(def.documentationComment);
        } else {
          Comment comment = p.childEntities.firstWhere((c) => c is Comment, orElse: () => null);
          if (comment != null) {
            children[new Symbol(p.identifier.name)] = new AnalyzerDocumentedElement._leaf(comment);
          }
        }
      });
    } else if (decl is ClassDeclaration) {
      decl.childEntities?.forEach((c) {
        if (c is MethodDeclaration) {
          children[new Symbol(c.name.token.lexeme)] = new AnalyzerDocumentedElement._(c);
        } else if (c is FieldDeclaration) {
          c.fields?.variables?.forEach((v) {
            children[new Symbol(v.name.token.lexeme)] = new AnalyzerDocumentedElement._(v);
          });
        }
      });
    } else if (decl is FieldDeclaration) {
      decl.fields?.variables?.forEach((v) {
        children[new Symbol(v.name.token.lexeme)] = new AnalyzerDocumentedElement._(v);
      });
    }
  }

  AnalyzerDocumentedElement._leaf(Comment docComment) {
    _apply(docComment);
  }

  void _apply(Comment comment) {
    final lines = comment?.tokens
            ?.map((t) => t.lexeme.trimLeft().substring(3).trim())
            ?.where((str) => str.isNotEmpty)
            ?.toList() ??
        [];

    if (lines.length > 0) {
      summary = lines.first;
    } else {
      summary = "";
    }

    if (lines.length > 1) {
      description = lines.sublist(1).join(" ");
    } else {
      description = "";
    }
  }
}
