part of aqueduct;

Future generateTemporarySchemaFromModels(PostgresModelAdapter adapter, List<Type> models) async {
  var schema = new PostgresqlSchema.fromModels(models, temporary: true);

  adapter.schema = schema;

  var conn = await adapter.getDatabaseConnection();
  for (var def in schema.schemaDefinition()) {
    PostgresModelAdapter.logger.info("$def");
    await conn.execute(def);
  }
}
