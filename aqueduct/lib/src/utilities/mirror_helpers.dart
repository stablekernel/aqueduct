import 'dart:async';
import 'dart:mirrors' hide Comment;
import 'dart:isolate';

import 'package:analyzer/analyzer.dart';

dynamic firstMetadataOfType(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata.firstWhere((im) => im.type.isSubtypeOf(tMirror), orElse: () => null)?.reflectee;
}

List<dynamic> allMetadataOfType(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata.where((im) => im.type.isSubtypeOf(tMirror)).map((im) => im.reflectee).toList();
}

class DocumentedElement {
  DocumentedElement._(AnnotatedNode decl) {
    _apply(decl.documentationComment);

    if (decl is MethodDeclaration) {
      decl.parameters?.parameters?.forEach((p) {
        if (p.childEntities.length == 1 && p.childEntities.first is SimpleFormalParameter) {
          SimpleFormalParameter def = p.childEntities.first;
          children[new Symbol(p.identifier.name)] = new DocumentedElement._leaf(def.documentationComment);
        } else {
          final comment = p.childEntities.firstWhere((c) => c is Comment, orElse: () => null);
          if (comment != null) {
            children[new Symbol(p.identifier.name)] = new DocumentedElement._leaf(comment);
          }
        }
      });
    } else if (decl is ClassDeclaration) {
      decl.childEntities?.forEach((c) {
        if (c is MethodDeclaration) {
          children[new Symbol(c.name.token.lexeme)] = new DocumentedElement._(c);
        } else if (c is FieldDeclaration) {
          c.fields?.variables?.forEach((v) {
            children[new Symbol(v.name.token.lexeme)] = new DocumentedElement._(v);
          });
        }
      });
    } else if (decl is FieldDeclaration) {
      decl.fields?.variables?.forEach((v) {
        children[new Symbol(v.name.token.lexeme)] = new DocumentedElement._(v);
      });
    }
  }

  DocumentedElement._leaf(Comment docComment) {
    _apply(docComment);
  }

  final Map<Symbol, DocumentedElement> children = {};
  String summary;
  String description;

  DocumentedElement operator [](Symbol symbol) {
    return children[symbol];
  }

  static Future<DocumentedElement> get(Type type) async {
    if (!_cache.containsKey(type)) {
      final reflectedType = reflectType(type);
      final uri = reflectedType.location.sourceUri;
      final resolvedUri = await Isolate.resolvePackageUri(uri);
      final fileUnit = parseDartFile(resolvedUri.path);

      var classDeclaration = fileUnit.declarations
          .where((u) => u is ClassDeclaration)
          .map((cu) => cu as ClassDeclaration)
          .firstWhere((ClassDeclaration classDecl) {
        return classDecl.name.token.lexeme == MirrorSystem.getName(reflectedType.simpleName);
      });

      _cache[type] = new DocumentedElement._(classDeclaration);
    }

    return _cache[type];
  }

  static Map<Type, DocumentedElement> _cache = {};

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
