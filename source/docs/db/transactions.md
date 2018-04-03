# Database Transactions

Learn how to execute multiple `Query<T>`s in a database transaction.

## Transactions

Consider an application that keeps employee records. Each employee belongs to a department. Management decides to combine two departments into a totally new department. To do this, the application must insert a new department, set each employee's foreign key reference to that department, and then delete the old departments. It'd look like this:

```dart
// Create the new department
final newDepartment = await Query.insertObject(ctx, Department()..name = "New Department");

// Set employee's departments to the new one
final changeDepartmentQuery = Query<Employee>(ctx)
  ..where((e) => e.department.id).oneOf([1, 2])      
  ..values.department.id = newDepartment.id;
await changeDepartmentQuery.update();

// Delete the old ones
final deleteDepartmentQuery = Query<Department>(ctx)
  ..where((e) => e.department.id).oneOf([1, 2]);
await deleteDepartmentQuery.delete();      
```

This change to your database is three separate queries, but they all most complete for the 'transfer' to be successful. If one of them fails, our database can be left in an inconsistent state. For example, if deleting the departments succeeds, but the employees failed to be transferred to the new department, then a lot of employees would be without a department.

A database transaction combines queries together as a single unit. If a query in a transaction fails, the previous queries in that transaction are reverted and the remaining queries are aborted. You create transactions by invoking `ManagedContext.transaction` and writing your queries in its closure argument.

```dart
await context.transaction((transaction) async {
  // note that 'transaction' is the context for each of these queries.
  final newDepartment = await Query.insertObject(transaction, Department()..name = "New Department");

  final changeDepartmentQuery = Query<Employee>(transaction)
    ..where((e) => e.department.id).oneOf([1, 2])      
    ..values.department.id = newDepartment.id;
  await changeDepartmentQuery.update();

  final deleteDepartmentQuery = Query<Department>(transaction)
    ..where((e) => e.department.id).oneOf([1, 2]);
  await deleteDepartmentQuery();      
});
```

All of the queries in the transaction closure will run in the same transaction. Once they have all succeeded, the `transaction` method's future completes. If an exception is thrown in the closure, the transaction is rolled back and the `transaction` method re-throws that exception.

Notice that the context for each query is the `transaction` object passed to the transaction closure. You must use this object when using `Query` in a transaction closure.

!!! warning "Failing to Use the Transaction Context will Deadlock your Application"

  While a transaction is in progress, any query sent by the same connection becomes part of that transaction. A `ManagedContext` has a single database connection. Because Dart is asynchronous, a its likely that another request will trigger a database request while a transaction is in progress. For this reason, a context must queue queries from outside of a transaction while the transaction is running. In order for the Aqueduct to know if the query is meant to be in the transaction is through the context of the query. If you await on a query on the original context inside of a transaction closure, it won't complete until the transaction completes - but the transaction can't complete because it is awaiting for the query to complete.

### Rollbacks

You can cancel a transaction and revert its changes at anytime within the transaction closure by throwing a `Rollback` object.

```dart
final reason = await context.transaction((t) async {
  // do something

  if (somethingIsTrue) {
    throw Rollback("something was true");    
  }

  // do something
});

if (reason == "something was true") {
  // do something
}
```

When you rollback, your transaction fails, the transaction closure is aborted and all changes are reverted. The `transaction` method completes successfully with the value provided to `Rollback`. This value can be anything and is used by subsequent code to determine why the transaction was rolled back, in the case of
more than one possible rollback in a transaction.
