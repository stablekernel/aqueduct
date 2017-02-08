import '../db.dart';
import 'property_mapper.dart';
import 'query_builder.dart';

abstract class EntityTableMapper {
  ManagedEntity get entity;

  List<PostgresMapper> returningOrderedMappers;

  String get tableDefinition {
    if (tableAlias == null) {
      return entity.tableName;
    }

    return "${entity.tableName} $tableAlias";
  }

  String get tableReference {
    return tableAlias ?? entity.tableName;
  }

  String _tableAlias;
  String get tableAlias {
    if (_tableAlias == null) {
      _tableAlias = generateTableAlias();
    }

    return _tableAlias;
  }

  String generateTableAlias();
}
