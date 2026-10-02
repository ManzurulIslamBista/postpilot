import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// A SQLite file in the application's documents directory.
QueryExecutor openAppConnection() => driftDatabase(name: 'postpilot');
