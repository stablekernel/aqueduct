# Database Transactions

Learn how to execute multiple `Query<T>`s in a database transaction.

## Transactions

A transaction is a series of queries that are executed together. If one of the queries in that set fails, then all of the queries fail and their changes are reversed if they had already been executed.

Consider an application that stores employee records. Each employee belongs to a department. Management decides to combine two departments into a totally new department. To do this, the application must insert a new department, set each employee's foreign key reference to that department, and then delete the old departments. An straightforward (but problematic) implementation would look like this:

```dart
// Create the new department
final newDepartment = await ctx.insertObject(Department()..name = "New Department");

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
  final newDepartment = await transaction.insertObject(Department()..name = "New Department");

  final changeDepartmentQuery = Query<Employee>(transaction)
    ..where((e) => e.department.id).oneOf([1, 2])      
    ..values.department.id = newDepartment.id;
  await changeDepartmentQuery.update();

  final deleteDepartmentQuery = Query<Department>(transaction)
    ..where((e) => e.department.id).oneOf([1, 2]);
  await deleteDepartmentQuery.delete();      
});
```

The closure has a `transaction` object that all queries in the transaction must use as their context. Queries that use this transaction context will be grouped in the same transaction. Once they have all succeeded, the `transaction` method's future completes. If an exception is thrown in the closure, the transaction is rolled back and the `transaction` method re-throws that exception.

!!! warning "Failing to Use the Transaction Context will Deadlock your Application"
      If you use the transaction's parent context in a query inside a transaction closure, the database connection will deadlock and will stop working.

### Returning Values

The value returned from a transaction closure is returned to the caller, so values created within the transaction closure can escape its scope.

```dart
final employees = [...];
final insertedEmployees = await context.transaction((transaction) async {
  return Future.wait(employees.map((e) => transaction.insertObject(e)));
});
```

### Rollbacks

You can cancel a transaction and revert its changes at anytime within the transaction closure by throwing a `Rollback` object.

```dart
try {
  await context.transaction((t) async {
    // do something

    if (somethingIsTrue) {
      throw Rollback("something was true");    
    }

    // do something
  });
} on Rollback catch (rollback) {
  print("${rollback.reason}"); // prints 'something was true'
}
```

When you rollback, your transaction fails, the transaction closure is aborted and all changes are reverted. The `transaction` method completes with an error, where the error object is the `Rollback`.
