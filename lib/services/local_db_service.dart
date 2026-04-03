import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
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
          CREATE TABLE exercise_telemetry (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            exercise_name TEXT NOT NULL,
            good_reps INTEGER DEFAULT 0,
            bad_reps INTEGER DEFAULT 0,
            exercise_score INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES workout_sessions (id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE rep_telemetry (
            id TEXT PRIMARY KEY,
            exercise_telemetry_id TEXT NOT NULL,
            rep_number INTEGER NOT NULL,
            score REAL NOT NULL,
            FOREIGN KEY (exercise_telemetry_id) REFERENCES exercise_telemetry (id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  // --- NEW: CREATE SESSION CHECKPOINT ---
  Future<void> createSessionRecord(Map<String, dynamic> sessionData) async {
    final db = await database;
    // Use ConflictAlgorithm.ignore so we don't overwrite it if we re-save
    await db.insert('workout_sessions', sessionData,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // --- NEW: APPEND EXERCISE TELEMETRY ---
  Future<void> appendExerciseTelemetry(
      Map<String, dynamic> exerciseData) async {
    final db = await database;
    final batch = db.batch();

    final String exerciseId = exerciseData['id'];

    // 1. Insert the parent exercise record (removed rep_scores_array)
    batch.insert('exercise_telemetry', {
      'id': exerciseId,
      'session_id': exerciseData['session_id'],
      'exercise_name': exerciseData['exercise_name'],
      'good_reps': exerciseData['good_reps'],
      'bad_reps': exerciseData['bad_reps'],
      'exercise_score': exerciseData['exercise_score'],
    });

    // 2. Insert the child rep records
    final List<double> reps =
        List<double>.from(exerciseData['rep_scores_array'] ?? []);
    for (int i = 0; i < reps.length; i++) {
      batch.insert('rep_telemetry', {
        'id': const Uuid().v4(),
        'exercise_telemetry_id': exerciseId,
        'rep_number': i + 1,
        'score': reps[i],
      });
    }

    await batch.commit(noResult: true);
  }

  // --- NEW: UPDATE SESSION STATUS & SCORE ---
  Future<void> updateSessionCompletion(String sessionId, String status,
      int globalScore, int durationSeconds) async {
    final db = await database;
    await db.update(
        'workout_sessions',
        {
          'status': status,
          'global_score': globalScore,
          'duration_seconds': durationSeconds,
          'sync_status':
              0 // Reset sync status so the server gets the final update
        },
        where: 'id = ?',
        whereArgs: [sessionId]);
  }

  // --- SAVE WORKOUT TO PHONE ---
  Future<void> saveWorkoutOffline(Map<String, dynamic> sessionData,
      List<Map<String, dynamic>> exercisesData) async {
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

    // 1. Fetch parent sessions
    final sessions = await db
        .query('workout_sessions', where: 'sync_status = ?', whereArgs: [0]);

    List<Map<String, dynamic>> masterPayload = [];

    for (var session in sessions) {
      Map<String, dynamic> sessionData = Map.from(session);

      // 2. Fetch child exercises
      final exercises = await db.query('exercise_telemetry',
          where: 'session_id = ?', whereArgs: [session['id']]);

      List<Map<String, dynamic>> exercisesList = [];

      for (var ex in exercises) {
        Map<String, dynamic> exData = Map.from(ex);

        // 3. Fetch grandchild reps from the NEW normalized table
        final reps = await db.query('rep_telemetry',
            where: 'exercise_telemetry_id = ?',
            whereArgs: [ex['id']],
            orderBy: 'rep_number ASC');

        // Map exactly to the 'reps' key the PHP script expects
        exData['reps'] = reps.map((r) => r['score']).toList();
        exercisesList.add(exData);
      }

      sessionData['exercises'] = exercisesList;
      masterPayload.add(sessionData);
    }

    return masterPayload;
  }

  Future<void> markSessionSynced(String sessionId) async {
    final db = await database;
    await db.update(
      'workout_sessions',
      {'sync_status': 1},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
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
        await txn.insert('workout_sessions', sessionData,
            conflictAlgorithm: ConflictAlgorithm.replace);

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
            'rep_scores_array':
                jsonEncode(ex['rep_scores']), // Re-stringify for SQLite
          };
          await txn.insert('exercise_telemetry', exData,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  // --- DASHBOARD ANALYTICS ENGINE ---
  Future<Map<String, dynamic>> getDashboardAggregates() async {
    final db = await database;

    // 1. Bento Box Data (Weekly vs Monthly Averages)
    final bentoResult = await db.rawQuery('''
      SELECT 
        (SELECT AVG(global_score) FROM workout_sessions WHERE status = 'COMPLETED' AND created_at >= date('now', '-7 days')) as weekly_avg,
        (SELECT AVG(global_score) FROM workout_sessions WHERE status = 'COMPLETED' AND created_at >= date('now', '-30 days')) as monthly_avg
    ''');

    // 2. Fallback Intelligence (Today -> Yesterday -> Last Known)
    final lastSession = await db.rawQuery('''
      SELECT *, 
      CASE 
        WHEN date(created_at) = date('now') THEN 'TODAY'
        WHEN date(created_at) = date('now', '-1 day') THEN 'YESTERDAY'
        ELSE date(created_at)
      END as relative_date
      FROM workout_sessions 
      WHERE status = 'COMPLETED' 
      ORDER BY created_at DESC LIMIT 1
    ''');

    // 3. Weekly Volume Bucket (Sum of today + last 6 days)
    final weeklyVolume = await db.rawQuery('''
      SELECT 
        SUM(s.duration_seconds) as total_time, 
        SUM(t.good_reps) as total_reps,
        COUNT(DISTINCT date(s.created_at)) as active_days
      FROM workout_sessions s
      JOIN exercise_telemetry t ON s.id = t.session_id
      WHERE s.status = 'COMPLETED' AND s.created_at >= date('now', '-6 days')
    ''');

    // 4. Swipable Graph Data (Daily Averages for 7 and 30 days)
    final daily7 = await db.rawQuery('''
      SELECT date(created_at) as day, AVG(global_score) as avg_score 
      FROM workout_sessions WHERE status = 'COMPLETED' AND created_at >= date('now', '-7 days')
      GROUP BY day ORDER BY day ASC
    ''');

    final daily30 = await db.rawQuery('''
      SELECT date(created_at) as day, AVG(global_score) as avg_score 
      FROM workout_sessions WHERE status = 'COMPLETED' AND created_at >= date('now', '-30 days')
      GROUP BY day ORDER BY day ASC
    ''');

    // 5. Form Diagnostics (Top 2 / Bottom 2)
    final diagnostics = await db.rawQuery('''
      SELECT exercise_name, AVG(exercise_score) as avg_score FROM exercise_telemetry 
      GROUP BY exercise_name ORDER BY avg_score DESC
    ''');

    // 6. Latest Activity (All history for the timeline)
    final timeline = await db.rawQuery('''
      SELECT *, date(created_at) as session_date FROM workout_sessions 
      WHERE status = 'COMPLETED' ORDER BY created_at DESC
    ''');

    return {
      'bento': bentoResult.first,
      'last_known': lastSession.isNotEmpty ? lastSession.first : null,
      'weekly_volume': weeklyVolume.first,
      'graph_7': daily7,
      'graph_30': daily30,
      'diagnostics': diagnostics,
      'timeline': timeline,
    };
  }

  // Helper for the Configurable Form Endurance dropdown
  Future<List<Map<String, dynamic>>> getRawTelemetryForPeriod(int days) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT exercise_name, rep_scores_array, good_reps, bad_reps
      FROM exercise_telemetry 
      JOIN workout_sessions ON exercise_telemetry.session_id = workout_sessions.id
      WHERE workout_sessions.status = 'COMPLETED' 
      AND workout_sessions.created_at >= date('now', '-$days days')
    ''');
  }

  Future<List<Map<String, dynamic>>> getTelemetryForSession(
      String sessionId) async {
    final db = await database;
    return await db.query('exercise_telemetry',
        where: 'session_id = ?', whereArgs: [sessionId]);
  }
}
