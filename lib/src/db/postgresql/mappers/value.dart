import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/postgresql/mappers/column.dart';
import 'package:aqueduct/src/db/postgresql/mappers/table.dart';

class PropertyValueMapper extends ColumnMapper {
  PropertyValueMapper(TableMapper table, ManagedPropertyDescription property, dynamic value)
      : super(table, property) {
    this.value = convertValueForStorage(value);
  }

  dynamic value;
}
