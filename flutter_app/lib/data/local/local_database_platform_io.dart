import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<String> localDatabasePath(String filename) async =>
    path.join(await getDatabasesPath(), filename);

Future<bool> legacyDatabaseExists(String filename) => File(filename).exists();
