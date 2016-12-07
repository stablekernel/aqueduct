import 'attributes.dart';
import '../query/query.dart';

export '../query/query.dart';

abstract class QueryMatchableExtension implements QueryMatchable {
  bool get hasJoinElements {
    return backingMap.values
        .where((item) => item is QueryMatchable)
        .any((QueryMatchable item) => item.includeInResultSet);
  }

  List<String> get joinPropertyKeys {
    return backingMap.keys.where((propertyName) {
      var val = backingMap[propertyName];
      var relDesc = entity.relationships[propertyName];

      return val is QueryMatchable &&
          val.includeInResultSet &&
          (relDesc?.relationshipType == ManagedRelationshipType.hasMany ||
              relDesc?.relationshipType == ManagedRelationshipType.hasOne);
    }).toList();
  }
}
