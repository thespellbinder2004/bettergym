import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class LocalDBService {
  static final LocalDBService instance = LocalDBService._internal();
  LocalDBService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'bettergym_local.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE workout_sessions (
            id TEXT PRIMARY KEY,
            user_id INTEGER NOT NULL,
            routine_id TEXT,
            status TEXT NOT NULL,
            global_score INTEGER NOT NULL,
            duration_seconds INTEGER NOT NULL,
            sync_status INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');

        await db.execute('''
          CREATE TABLE exercise_telemetry (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            exercise_name TEXT NOT NULL,
            good_reps INTEGER DEFAULT 0,
            bad_reps INTEGER DEFAULT 0,
            exercise_score INTEGER NOT NULL,
            rep_scores_array TEXT NOT NULL,
            FOREIGN KEY (session_id) REFERENCES workout_sessions(id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }
  
  // --- NEW: CREATE SESSION CHECKPOINT ---
  Future<void> createSessionRecord(Map<String, dynamic> sessionData) async {
    final db = await database;
    // Use ConflictAlgorithm.ignore so we don't overwrite it if we re-save
    await db.insert('workout_sessions', sessionData, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // --- NEW: APPEND EXERCISE TELEMETRY ---
  Future<void> appendExerciseTelemetry(Map<String, dynamic> exerciseData) async {
    final db = await database;
    exerciseData['rep_scores_array'] = jsonEncode(exerciseData['rep_scores_array']);
    await db.insert('exercise_telemetry', exerciseData);
  }

  // --- NEW: UPDATE SESSION STATUS & SCORE ---
  Future<void> updateSessionCompletion(String sessionId, String status, int globalScore, int durationSeconds) async {
    final db = await database;
    await db.update(
      'workout_sessions',
      {
        'status': status,
        'global_score': globalScore,
        'duration_seconds': durationSeconds,
        'sync_status': 0 // Reset sync status so the server gets the final update
      },
      where: 'id = ?',
      whereArgs: [sessionId]
    );
  }

  // --- SAVE WORKOUT TO PHONE ---
  Future<void> saveWorkoutOffline(Map<String, dynamic> sessionData, List<Map<String, dynamic>> exercisesData) async {
    final db = await database;
    
    await db.transaction((txn) async {
      await txn.insert('workout_sessions', sessionData);
      for (var ex in exercisesData) {
        ex['rep_scores_array'] = jsonEncode(ex['rep_scores_array']);
        await txn.insert('exercise_telemetry', ex);
      }
    });
  }

  // --- GRAB TRAPPED DATA ---
  Future<List<Map<String, dynamic>>> getUnsyncedSessions() async {
    final db = await database;
    final sessions = await db.query('workout_sessions', where: 'sync_status = ?', whereArgs: [0]);
    List<Map<String, dynamic>> payload = [];
    
    for (var session in sessions) {
      final sessionMap = Map<String, dynamic>.from(session);
      final telemetry = await db.query('exercise_telemetry', where: 'session_id = ?', whereArgs: [session['id']]);
      
      List<Map<String, dynamic>> decodedTelemetry = telemetry.map((t) {
        var mutableT = Map<String, dynamic>.from(t);
        mutableT['rep_scores'] = jsonDecode(mutableT['rep_scores_array']);
        mutableT.remove('rep_scores_array');
        return mutableT;
      }).toList();

      sessionMap['exercises'] = decodedTelemetry;
      payload.add(sessionMap);
    }
    return payload;
  }

  Future<void> markSessionAsSynced(String sessionId) async {
    final db = await database;
    await db.update('workout_sessions', {'sync_status': 1}, where: 'id = ?', whereArgs: [sessionId]);
  }
  // --- FETCH DASHBOARD DATA ---
  Future<List<Map<String, dynamic>>> getCompletedSessions() async {
    final db = await database;
    // We order by 'created_at ASC' so the oldest workout is on the left of the chart, newest on the right
    return await db.query(
      'workout_sessions',
      where: 'status = ?',
      whereArgs: ['COMPLETED'],
      orderBy: 'created_at ASC', 
    );
  }
  
  // --- INJECT DOWNLOADED HISTORY ---
  Future<void> saveDownloadedHistory(List<dynamic> serverSessions) async {
    final db = await database;
    
    // We run this as a massive batch transaction for speed
    await db.transaction((txn) async {
      for (var session in serverSessions) {
        // Prepare the session row
        final Map<String, dynamic> sessionData = {
          'id': session['id'],
          'user_id': session['user_id'],
          'routine_id': session['routine_id'],
          'status': session['status'],
          'global_score': session['global_score'],
          'duration_seconds': session['duration_seconds'],
          'sync_status': 1, // ALREADY SYNCED
          'created_at': session['created_at'],
        };

        // ConflictAlgorithm.replace prevents crashes if the data already exists locally
        await txn.insert('workout_sessions', sessionData, conflictAlgorithm: ConflictAlgorithm.replace);

        // Prepare the child telemetry rows
        List<dynamic> exercises = session['exercises'] ?? [];
        for (var ex in exercises) {
          final Map<String, dynamic> exData = {
            'id': ex['id'],
            'session_id': ex['session_id'],
            'exercise_name': ex['exercise_name'],
            'good_reps': ex['good_reps'],
            'bad_reps': ex['bad_reps'],
            'exercise_score': ex['exercise_score'],
            'rep_scores_array': jsonEncode(ex['rep_scores']), // Re-stringify for SQLite
          };
          await txn.insert('exercise_telemetry', exData, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }
  // --- DASHBOARD ANALYTICS ENGINE ---
  Future<Map<String, dynamic>> getDashboardAggregates() async {
    final db = await database;

    // 1. Volume Metrics (Total Time & Total Clean Reps)
    final volumeResult = await db.rawQuery('''
      SELECT 
        (SELECT SUM(duration_seconds) FROM workout_sessions WHERE status = 'COMPLETED') as total_time,
        (SELECT SUM(good_reps) FROM exercise_telemetry) as total_reps
    ''');

    // 2. Diagnostics (Exercise Averages)
    final diagnosticsResult = await db.rawQuery('''
      SELECT exercise_name, AVG(exercise_score) as avg_score, COUNT(id) as total_sets
      FROM exercise_telemetry 
      GROUP BY exercise_name 
      HAVING total_sets > 0
      ORDER BY avg_score DESC
    ''');

    // 3. Timeline (Last 5 Sessions)
    final recentSessions = await db.query(
      'workout_sessions',
      where: 'status = ?',
      whereArgs: ['COMPLETED'],
      orderBy: 'created_at DESC',
      limit: 5
    );

    // 4. THE NEW FATIGUE & HEATMAP ENGINE
    final rawTelemetry = await db.rawQuery('''
      SELECT exercise_name, rep_scores_array, good_reps, bad_reps
      FROM exercise_telemetry 
      JOIN workout_sessions ON exercise_telemetry.session_id = workout_sessions.id
      WHERE workout_sessions.status = 'COMPLETED' 
      AND workout_sessions.created_at >= date('now', '-7 days')
    ''');

    return {
      'volume': volumeResult.isNotEmpty ? volumeResult.first : {'total_time': 0, 'total_reps': 0},
      'diagnostics': diagnosticsResult,
      'timeline': recentSessions,
      'raw_telemetry': rawTelemetry, // NEW
    };
  }
}