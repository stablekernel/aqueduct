import 'package:aqueduct/src/db/shared/builders/table.dart';
import 'package:aqueduct/src/db/shared/returnable.dart';
import 'package:aqueduct/src/db/shared/row_instantiator.dart';
import 'package:sqljocky5/sqljocky.dart';

class MySqlRowInstantiator extends RowInstantiator<Row> {
  MySqlRowInstantiator(
      TableBuilder rootTableBuilder, List<Returnable> returningValues)
      : super(rootTableBuilder, returningValues);
}
