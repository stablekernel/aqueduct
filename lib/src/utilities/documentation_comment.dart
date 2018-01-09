//    var reflectedType = reflect(this).type;
//    var uri = reflectedType.location.sourceUri;
//    var fileUnit = parseDartFile(resolver.resolve(uri));
//    var classUnit = fileUnit.declarations
//        .where((u) => u is ClassDeclaration)
//        .map((cu) => cu as ClassDeclaration)
//        .firstWhere((ClassDeclaration classDecl) {
//      return classDecl.name.token.lexeme == MirrorSystem.getName(reflectedType.simpleName);
//    });
//
//    Map<Symbol, MethodDeclaration> methodMap = {};
//    classUnit.childEntities.forEach((child) {
//      if (child is MethodDeclaration) {
//        methodMap[new Symbol(child.name.token.lexeme)] = child;
//      }
//    });


// Add documentation comments
//      var methodDeclaration = methodMap[cachedMethod.methodSymbol];
//      if (methodDeclaration != null) {
//        var comment = methodDeclaration.documentationComment;
//        var tokens = comment?.tokens ?? [];
//        var lines = tokens.map((t) => t.lexeme.trimLeft().substring(3).trim()).toList();
//        if (lines.length > 0) {
//          op.summary = lines.first;
//        }
//
//        if (lines.length > 1) {
//          op.description = lines.sublist(1, lines.length).join("\n");
//        }
//      }
