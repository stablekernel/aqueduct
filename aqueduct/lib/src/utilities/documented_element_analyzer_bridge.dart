import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors' hide Comment;

import 'package:analyzer/analyzer.dart';
import 'package:aqueduct/src/utilities/documented_element.dart';

class AnalyzerDocumentedElementProvider implements DocumentedElementProvider {
  @override
  Future<DocumentedElement> resolve(Type type) async {
    final reflectedType = reflectType(type);
    final uri = reflectedType.location.sourceUri;
    final resolvedUri = await Isolate.resolvePackageUri(uri);
    final fileUnit =
        parseDartFile(resolvedUri.toFilePath(windows: Platform.isWindows));

    var classDeclaration = fileUnit.declarations
        .whereType<ClassDeclaration>()
        .firstWhere((ClassDeclaration classDecl) {
      return classDecl.name.token.lexeme ==
          MirrorSystem.getName(reflectedType.simpleName);
    });

    return AnalyzerDocumentedElement._(classDeclaration);
  }
}

class AnalyzerDocumentedElement extends DocumentedElement {
  AnalyzerDocumentedElement._(AnnotatedNode decl) {
    _apply(decl.documentationComment);

    if (decl is MethodDeclaration) {
      decl.parameters?.parameters?.forEach((p) {
        if (p.childEntities.length == 1 &&
            p.childEntities.first is SimpleFormalParameter) {
          SimpleFormalParameter def = p.childEntities.first;
          children[Symbol(p.identifier.name)] =
              AnalyzerDocumentedElement._leaf(def.documentationComment);
        } else {
          Comment comment = p.childEntities
              .firstWhere((c) => c is Comment, orElse: () => null);
          if (comment != null) {
            children[Symbol(p.identifier.name)] =
                AnalyzerDocumentedElement._leaf(comment);
          }
        }
      });
    } else if (decl is ClassDeclaration) {
      decl.childEntities?.forEach((c) {
        if (c is MethodDeclaration) {
          children[Symbol(c.name.token.lexeme)] =
              AnalyzerDocumentedElement._(c);
        } else if (c is FieldDeclaration) {
          c.fields?.variables?.forEach((v) {
            children[Symbol(v.name.token.lexeme)] =
                AnalyzerDocumentedElement._(v);
          });
        }
      });
    } else if (decl is FieldDeclaration) {
      decl.fields?.variables?.forEach((v) {
        children[Symbol(v.name.token.lexeme)] = AnalyzerDocumentedElement._(v);
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

    if (lines.isNotEmpty) {
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
