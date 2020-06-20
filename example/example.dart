import 'package:angel_firestore/angel_firestore.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:dartbase_admin/dartbase_admin.dart';

void main() async {
  var app = Angel();
  var firebase = await Firebase.initialize('your-firebase-project-id',
      await ServiceAccount.fromFile('service-account.json'));
  var firestore = Firestore(firebase: firebase);
  var collection = firestore.collection('test');

  var service = app.use('/api/users', FirestoreClientService(collection));

  service.afterCreated.listen((event) {
    print('New user: ${event.result}');
  });
}
