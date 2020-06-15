import 'package:angel_container/angel_container.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_framework/http.dart';
import 'package:angel_firestore/angel_firestore.dart';
import 'package:dotenv/dotenv.dart' show load, env;
import 'package:http/http.dart' as http;
import 'package:json_god/json_god.dart' as god;
import 'package:dartbase_admin/dartbase.dart';
import 'package:test/test.dart';


final headers = {
  'accept': 'application/json',
  'content-type': 'application/json'
};

final Map testGreeting = {'to': 'world'};

wireHooked(HookedService hooked) {
  hooked.afterAll((HookedServiceEvent event) {
    print("Just ${event.eventName}: ${event.result}");
    print('Params: ${event.params}');
  });
}

main() {
  group('Generic Tests', () {
    Angel app;
    AngelHttp transport;
    http.Client client;
    Firestore firestore;
    Firebase firebase;
    CollectionReference collection;
    String url;
    HookedService<String, Map<String, dynamic>, FirestoreClientService> greetingService;
    HookedService<String, Map<String, dynamic>, FirestoreClientService> removeAllService;

    setUpAll(() async {
      load();
      firebase = await Firebase.initialize(
          env['FIREBASE_PROJECT_ID'],
          await ServiceAccount.fromFile(env['FIREBASE_SERVICE_ACCOUNT_PATH']));
    });

    setUp(() async {
      app = Angel(reflector: EmptyReflector());
      transport = AngelHttp(app);
      client = http.Client();

      firestore = Firestore(firebase: firebase);
      collection = firestore.collection('test');

      var serviceAllowRemoveAll = FirestoreClientService(collection,
          allowRemoveAll: true);
      removeAllService = HookedService(serviceAllowRemoveAll);
      wireHooked(removeAllService);
      var service = FirestoreClientService(collection);
      greetingService = HookedService(service);
      wireHooked(greetingService);

      // Delete all elements in the collection to start with
      removeAllService.remove(null);

      app.use('/api', greetingService);

      await transport.startServer('127.0.0.1', 0);
      url = transport.uri.toString();
    });

    tearDown(() async {
      // Delete anything left over
      await removeAllService.remove(null);
      await transport.close();
      client = null;
      url = null;
      greetingService = null;
    });

    test('query fields mapped to filters', () async {
      await greetingService.create({'foo': 'bar'});
      expect(
        await greetingService.index({
          r'$where': FirestoreWhereFilter('foo', 'not bar',
              comparisonType: ComparisonType.isEqualTo),
        }),
        isEmpty,
      );
      expect(
        await greetingService.index(),
        isNotEmpty,
      );
    });

    test('insert items', () async {
      var response = await client.post("$url/api",
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));

      response = await client.get("$url/api");
      expect(response.statusCode, isIn([200, 201]));
      var users = god.deserialize(response.body,
          outputType: <Map>[].runtimeType) as List<Map>;
      expect(users.length, equals(1));
    });

    test('read item', () async {
      var response = await client.post("$url/api",
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));
      var created = god.deserialize(response.body) as Map;

      response = await client.get("$url/api/${created['id']}");
      expect(response.statusCode, isIn([200, 201]));
      var read = god.deserialize(response.body) as Map;
      expect(read['id'], equals(created['id']));
      expect(read['to'], equals('world'));
    });

    test('findOne', () async {
      var response = await client.post("$url/api",
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));
      var created = god.deserialize(response.body) as Map;

      var read = await greetingService.findOne(
          {'query': {'to': 'world'}});
      expect(read['id'], equals(created['id']));
      expect(read['to'], equals('world'));
    });

    test('readMany', () async {
      var response = await client.post("$url/api",
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));
      var created = god.deserialize(response.body) as Map;

      var read = await greetingService.readMany([created['id']]);
      expect(read, [created]);
    });

    test('modify item', () async {
      var response = await client.post("$url/api",
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));
      var created = god.deserialize(response.body) as Map;

      response = await client.patch("$url/api/${created['id']}",
          body: god.serialize({"to": "Mom"}), headers: headers);
      var modified = god.deserialize(response.body) as Map;
      expect(response.statusCode, isIn([200, 201]));
      expect(modified['id'], equals(created['id']));
      expect(modified['to'], equals('Mom'));
    });

    test('update item', () async {
      var response = await client.post("$url/api",
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));
      var created = god.deserialize(response.body) as Map;

      response = await client.post("$url/api/${created['id']}",
          body: god.serialize({"to": "Updated"}), headers: headers);
      var modified = god.deserialize(response.body) as Map;
      expect(response.statusCode, isIn([200, 201]));
      expect(modified['id'], equals(created['id']));
      expect(modified['to'], equals('Updated'));
    });

    test('remove item', () async {
      var response = await client.post("$url/api",
          body: god.serialize(testGreeting), headers: headers);
      var created = god.deserialize(response.body) as Map;

      int lastCount = (await greetingService.index()).length;

      await client.delete("$url/api/${created['id']}");
      expect((await greetingService.index()).length, equals(lastCount - 1));
    });

    test('cannot remove all unless explicitly set', () async {
      var response = await client.delete('$url/api/null');
      expect(response.statusCode, 403);
    });

    test('\$sort and query parameters', () async {
      // Search by where.eq
      Map world = await greetingService.create({"to": "world"});
      await greetingService.create({"to": "Mom"});
      await greetingService.create({"to": "Updated"});

      var response = await client.get("$url/api?to=world");
      var queried = god.deserialize(response.body,
          outputType: <Map>[].runtimeType) as List<Map>;
      print(queried);
      expect(queried.length, equals(1));
      expect(queried[0].keys.length, equals(2));
      expect(queried[0]["id"], equals(world["id"]));
      expect(queried[0]["to"], equals(world["to"]));
    });
  });
}
