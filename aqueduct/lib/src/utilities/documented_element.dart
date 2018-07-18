import 'dart:async';

class DocumentedElementProvider {
  Future<DocumentedElement> resolve(Type type) async {
    throw StateError(
        "No provider for 'DocumentedElement'. This occurs when attempting to use "
        "'DocumentedElement' when not documenting an application. This type may only be used during documentation."
        "You must set DocumentedElement.provider = AnalyzerDocumentedElementProvider().");
  }
}

abstract class DocumentedElement {
  static DocumentedElementProvider provider = DocumentedElementProvider();

  final Map<Symbol, DocumentedElement> children = {};
  String summary;
  String description;

  DocumentedElement operator [](Symbol symbol) {
    return children[symbol];
  }

  static Future<DocumentedElement> get(Type type) async {
    if (!_cache.containsKey(type)) {
      _cache[type] = await provider.resolve(type);
    }

    return _cache[type];
  }

  static Map<Type, DocumentedElement> _cache = {};
}
