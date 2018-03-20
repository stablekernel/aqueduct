# Database Transactions

Learn how to execute multiple `Query<T>`s in a database transaction.

## Transactions

Consider an application that keeps employee records. Each employee belongs to a department. Management decides to combine two departments into a totally new department. To do this, the application must insert a new department, set each employee's foreign key reference to that department, and then delete the old departments. It'd look like this:

```dart
// Create the new department
final newDepartment = await Query.insertObject(ctx, Department()..name = "New Department");

// Set employee's departments to the new one
final changeDepartmentQuery = Query<Employee>(ctx)
  ..where((e) => e.department.id).equalTo(1)
      .or((e) => e.department.id).equalTo(2)
  ..values.department.id = newDepartment.id;
await changeDepartmentQuery.update();

// Delete the old ones
final deleteDepartmentQuery = Query<Department>(ctx)
  ..where((e) => e.department.id).equalTo(1)
      .or((e) => e.department.id).equalTo(2);
await deleteDepartmentQuery();      
```

This change to your database is three separate queries, but they all most complete for the 'transfer' to be successful. If one of them fails, our database can be left in an inconsistent state. For example, what if deleting the departments succeeds but the employees failed to be transferred to the new department? That'd be really bad.

A database transaction links multiple queries together so that they only succeed if every other query in the transaction succeeds. If there is a failure, queries that have already been executed are reverted and the remaining queries are aborted. You create transactions by invoking `ManagedContext.transaction` and writing your queries in its closure argument.

```dart
await context.transaction((transaction) async {
  final newDepartment = await Query.insertObject(transaction, Department()..name = "New Department");
  final changeDepartmentQuery = Query<Employee>(transaction)
    ..where((e) => e.department.id).equalTo(1)
        .or((e) => e.department.id).equalTo(2)
    ..values.department.id = newDepartment.id;
  await changeDepartmentQuery.update();
  final deleteDepartmentQuery = Query<Department>(transaction)
    ..where((e) => e.department.id).equalTo(1)
        .or((e) => e.department.id).equalTo(2);
  await deleteDepartmentQuery();      
});
```

Queries that are to run in the transaction must use the provided `transaction` object as their context. This object - also a `ManagedContext` - allows the query to be associated with the transaction.

!!! warning "Transaction Objects"
    It is very important that your transaction queries use the transaction object provided in the closure. Using the original context that the transaction is being performed on will create a deadlock, and is an easy mistake to make.

If a query fails or an exception is thrown within the transaction closure, the transaction fails and any changes made are reverted. The exception is re-thrown from `transaction` so that you can handle it if necessary.

### Rollbacks

You can cancel a transaction and revert its changes at anytime within the transaction closure by throwing `Query.rollback`.

```dart
await context.transaction((t) async {
  // do some stuff

  throw Query.rollback;

  // do some other stuff
});
```

When you throw a rollback, your transaction fails, but the `transaction` method does not re-throw it.
