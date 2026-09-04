/// SQLite WASM keeps web databases in IndexedDB; its database identifier must
/// remain stable, but it is not a native filesystem path.
Future<String> localDatabasePath(String filename) async => filename;

Future<bool> legacyDatabaseExists(String filename) async => false;
