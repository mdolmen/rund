import 'dart:async';

import 'database_helper.dart';

final dbHelper = DatabaseHelper();

const String BACKEND_URL = "http://vps-433a4dd6.vps.ovh.net:8080";
//const String BACKEND_URL = "http://127.0.0.1:8080";

String USER_ID = "";

Future<void> setUserIdGlobal() async {
  USER_ID = await dbHelper.getUserId();
  print("DEBUG: USER_ID = $USER_ID");
}
