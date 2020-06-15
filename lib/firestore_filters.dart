enum ComparisonType {
  isEqualTo,
  isGreaterThan,
  isLessThan,
}

class FirestoreWhereFilter {
  ComparisonType comparisonType = ComparisonType.isEqualTo;
  final String field;
  final dynamic value;

  FirestoreWhereFilter(this.field, this.value, {this.comparisonType});
}