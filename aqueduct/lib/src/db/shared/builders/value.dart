import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/shared/returnable.dart';
import 'package:aqueduct/src/db/shared/builders/column.dart';
import 'package:aqueduct/src/db/shared/builders/table.dart';

class ColumnValueBuilder extends ColumnBuilder {
  ColumnValueBuilder(DbWrapper dbWrapper,
      TableBuilder table, ManagedPropertyDescription property, dynamic value)
      : super(dbWrapper,table, property) {
    this.value = convertValueForStorage(value);
  }

  dynamic value;
}
