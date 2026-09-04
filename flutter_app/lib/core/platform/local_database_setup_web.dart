import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Uses browser IndexedDB through SQLite WASM so draft and sync-queue behavior
/// remains the same on a laptop browser as it is in the Android app.
Future<void> configureLocalDatabaseForPlatform() async {
  databaseFactory = databaseFactoryFfiWeb;
}
