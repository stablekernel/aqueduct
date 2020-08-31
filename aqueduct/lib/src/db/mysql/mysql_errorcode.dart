/// https://www.jianshu.com/p/935333f3074b
class MySqlErrorCode {
  const MySqlErrorCode._(this.code, this.message);
  final int code;
  final String message;

  /// Invalid use of NULL value
  static const MySqlErrorCode invalid_use_of_NULL_value =
      const MySqlErrorCode._(1138, "Invalid use of NULL value");

  static const MySqlErrorCode table_existed =
      const MySqlErrorCode._(1146, "数据表已存在");

  /// 违反唯一索引规则
  static const MySqlErrorCode uniqueViolation =
      const MySqlErrorCode._(1062, "Duplicate entry ");

  static const MySqlErrorCode notNullViolation =
      const MySqlErrorCode._(1048, "cannot be null");
  static const MySqlErrorCode notDefaultValueViolation =
      const MySqlErrorCode._(1364, "doesn't have default value");

  static const MySqlErrorCode foreignKeyViolation =
      MySqlErrorCode._(1216, "外键约束检查失败");
  static const MySqlErrorCode foreignKeyViolation1 =
      MySqlErrorCode._(1217, "外键约束检查失败");
}
