/// The test database: in memory, one per settings store, so a new container
/// over the same [JsonStore] sees the same data and an app "restart" in a test
/// works for the database too.
library;

import 'package:bloom/core/db/db.dart';

final Expando<BloomDb> _dbs = Expando('testDb');

BloomDb testDb(Object store) => _dbs[store] ??= BloomDb.memory();
