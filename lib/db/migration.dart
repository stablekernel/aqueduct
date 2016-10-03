part of aqueduct;

abstract class Migration {
  Migration(this.context, this.database);

  ModelContext context;
  SchemaBuilder database;
  int version;

  // This needs to be wrapped in a transaction.
  Future upgrade();

  // This needs to be wrapped in a transaction.
  Future downgrade();

  Future seed(ModelContext context);
}