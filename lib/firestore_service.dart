library angel_firestore.services;

import 'dart:async';

import 'package:angel_firestore/angel_firestore.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:dartbase_admin/dartbase_admin.dart';

final List<String> _sensitiveFieldNames = const [
  'id',
];

Map<String, dynamic> _removeSensitive(Map<String, dynamic> data) {
  return data.keys
      .where((k) => !_sensitiveFieldNames.contains(k))
      .fold({}, (map, key) => map..[key] = data[key]);
}

/// Apply a where filter
QueryReference _whereFilter(
    CollectionReference collection, FirestoreWhereFilter whereFilter) {
  switch (whereFilter.comparisonType) {
    case ComparisonType.isEqualTo:
      return collection.where(whereFilter.field, isEqualTo: whereFilter.value);
    case ComparisonType.isGreaterThan:
      return collection.where(whereFilter.field,
          isGreaterThan: whereFilter.value);
    case ComparisonType.isLessThan:
      return collection.where(whereFilter.field, isLessThan: whereFilter.value);
    default:
      throw AngelHttpException('Unknown comparison type');
  }
}

Map<String, dynamic> _mapWithId(Document doc) {
  var result = doc.map;
  result['id'] = doc.id;
  return result;
}

/// Manipulates data from Firestore as Maps.
class FirestoreClientService extends Service<String, Map<String, dynamic>> {
  CollectionReference collection;

  /// If set to `true`, clients can remove all items by passing a `null` `id` to `remove`.
  ///
  /// `false` by default.
  final bool allowRemoveAll;

  FirestoreClientService(this.collection, {this.allowRemoveAll = false})
      : super();

  /// GET /
  /// Fetch all resources. Usually returns a List.
  @override
  Future<List<Map<String, dynamic>>> index(
      [Map<String, dynamic> params]) async {
    List<Document> documents;
    if (params == null ||
        (params.containsKey('query') && (params['query'] as Map).isEmpty) ||
        (!params.containsKey(r'$where') && !params.containsKey('query'))) {
      documents = await collection.get();
    } else {
      FirestoreWhereFilter whereFilter;
      if (params.containsKey('query')) {
        Map<String, dynamic> queryMap = params['query'];
        whereFilter = FirestoreWhereFilter(
            queryMap.keys.first, queryMap.values.first,
            comparisonType: ComparisonType.isEqualTo);
      }
      if (params.containsKey(r'$where')) {
        whereFilter = params[r'$where'];
      }

      documents = await _whereFilter(collection, whereFilter).get();
    }
    return documents.map((doc) => _mapWithId(doc)).toList();
  }

  /// GET /:id
  /// Fetch one resource, by its ID
  @override
  Future<Map<String, dynamic>> read(String id,
      [Map<String, dynamic> params]) async {
    var found = await collection.document(id);

    if (found == null) {
      throw AngelHttpException.notFound(message: 'No record found for ID $id');
    }

    var doc = await found.get();
    return _mapWithId(doc);
  }

  /// POST /
  /// Create a resource. This endpoint should return
  // the created resource.
  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> data,
      [Map<String, dynamic> params]) async {
    var item = _removeSensitive(data);

    try {
      var doc = await collection.add(item);
      return _mapWithId(doc);
    } catch (e, st) {
      throw AngelHttpException(e, stackTrace: st);
    }
  }

  /// PATCH /:id
  /// Modifies a resource. Clients can submit only the data
  /// they want to change, and the corresponding resource will
  /// have only those fields changed. This endpoint should return
  /// the modified resource.
  @override
  Future<Map<String, dynamic>> modify(String id, Map<String, dynamic> data,
      [Map<String, dynamic> params]) async {
    await collection.document(id).update(data);
    return _mapWithId(await collection.document(id).get());
  }

  /// POST /:id
  /// Overwrites a resource. The existing resource is completely
  /// replaced by the new data. This endpoint should return the
  /// new resource.
  @override
  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> data,
      [Map<String, dynamic> params]) async {
    var doc = await collection.document(id).get();
    await collection.document(id).set(data);
    doc = await collection.document(id).get();
    return _mapWithId(doc);
  }

  /// DELETE /:id
  /// Deletes a resource. This endpoint should return the deleted resource.
  @override
  Future<Map<String, dynamic>> remove(String id,
      [Map<String, dynamic> params]) async {
    if (id == null || id == 'null') {
      // Remove everything...
      if (!(allowRemoveAll == true ||
          params?.containsKey('provider') != true)) {
        throw AngelHttpException.forbidden(
            message: 'Clients are not allowed to delete all items.');
      } else {
        var page = await collection.get();
        page.forEach((doc) async {
          await doc.reference.delete();
        });
        while (page.isNotEmpty) {
          page = await collection.get(nextPageToken: page.nextPageToken);
          page.forEach((doc) async {
            await doc.reference.delete();
          });
        }
        return {};
      }
    }

    // when id != null
    try {
      var docRef = collection.document(id);
      var doc = await docRef.get();
      await docRef.delete();
      return _mapWithId(doc);
    } catch (e, st) {
      throw AngelHttpException(e, stackTrace: st);
    }
  }

  // Retrieves the first object from the result of calling index with the given params.
  /// If the result of index is null, OR an empty Iterable, a 404 AngelHttpException will be thrown.
  /// If the result is both non-null and NOT an Iterable, it will be returned as-is.
  /// If the result is a non-empty Iterable, findOne will return it.first, where it is the aforementioned Iterable.
  /// A custom errorMessage may be provided
  @override
  Future<Map<String, dynamic>> findOne(
      [Map<String, dynamic> params,
      String errorMessage =
          'No record was found matching the given query.']) async {
    List<Document> documents;
    if (params == null ||
        (params.containsKey('query') && (params['query'] as Map).isEmpty) ||
        (!params.containsKey(r'$where') && !params.containsKey('query'))) {
      documents = await collection.limit(1).get();
    } else {
      FirestoreWhereFilter whereFilter;
      if (params.containsKey('query')) {
        Map<String, dynamic> queryMap = params['query'];
        whereFilter = FirestoreWhereFilter(
            queryMap.keys.first, queryMap.values.first,
            comparisonType: ComparisonType.isEqualTo);
      }
      if (params.containsKey(r'$where')) {
        whereFilter = params[r'$where'];
      }

      documents = await _whereFilter(collection, whereFilter).limit(1).get();
    }
    if (documents.length != 1) {
      throw AngelHttpException('Such document not found', statusCode: 404);
    }
    return _mapWithId(documents[0]);
  }

  /// Reads multiple resources at once.
  @override
  Future<List<Map<String, dynamic>>> readMany(List<String> ids,
      [Map<String, dynamic> params]) async {
    var results = <Map<String, dynamic>>[];
    ids.forEach((id) async {
      results.add(await read(id));
    });
    return results;
  }
}
