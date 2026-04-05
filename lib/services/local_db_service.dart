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
      version: 4,
      onCreate: (db, version) async {
        // Create workout_sessions too if not yet in your DB init
        await db.execute('''
          CREATE TABLE workout_sessions (
            id TEXT PRIMARY KEY,
            user_id INTEGER NOT NULL,
            routine_id TEXT,
            status TEXT NOT NULL,
            global_score INTEGER,
            duration_seconds INTEGER,
            session_type TEXT NOT NULL DEFAULT 'realtime',
            sync_status INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
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

        await db.execute('''
          CREATE TABLE processed_videos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            session_id TEXT NOT NULL,
            exercise_name TEXT NOT NULL,
            result_json TEXT NOT NULL,
            file_path TEXT,
            file_name TEXT,
            score INTEGER,
            model_status TEXT DEFAULT 'processing'
              CHECK(model_status IN ('processing', 'done', 'failed')),
            error_message TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE processed_videos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              session_id TEXT NOT NULL,
              exercise_name TEXT NOT NULL,
              result_json TEXT NOT NULL,
              model_status TEXT DEFAULT 'processing'
                CHECK(model_status IN ('processing', 'done', 'failed')),
              error_message TEXT,
              created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
              ALTER TABLE workout_sessions 
              ADD COLUMN session_type TEXT NOT NULL DEFAULT 'realtime'
            ''');

          // optional: set all old to AI
          await db.execute('''
              UPDATE workout_sessions 
              SET session_type = 'ai'
            ''');
        }
        if (oldVersion < 4) {
          await db.execute(
              'ALTER TABLE processed_videos ADD COLUMN file_path TEXT');
          await db.execute(
              'ALTER TABLE processed_videos ADD COLUMN file_name TEXT');
          await db
              .execute('ALTER TABLE processed_videos ADD COLUMN score INTEGER');
        }
      },
    );
  }

  Future<void> createSessionRecord(Map<String, dynamic> sessionData) async {
    final db = await database;
    await db.insert(
      'workout_sessions',
      sessionData,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> appendExerciseTelemetry(
      Map<String, dynamic> exerciseData) async {
    final db = await database;
    final batch = db.batch();

    final String exerciseId = exerciseData['id'];

    batch.insert('exercise_telemetry', {
      'id': exerciseId,
      'session_id': exerciseData['session_id'],
      'exercise_name': exerciseData['exercise_name'],
      'good_reps': exerciseData['good_reps'],
      'bad_reps': exerciseData['bad_reps'],
      'exercise_score': exerciseData['exercise_score'],
    });

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

  Future<void> updateSessionCompletion(
    String sessionId,
    String status,
    int globalScore,
    int durationSeconds,
  ) async {
    final db = await database;
    await db.update(
      'workout_sessions',
      {
        'status': status,
        'global_score': globalScore,
        'duration_seconds': durationSeconds,
        'sync_status': 0,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> saveWorkoutOffline(
    Map<String, dynamic> sessionData,
    List<Map<String, dynamic>> exercisesData,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.insert('workout_sessions', sessionData);
      for (var ex in exercisesData) {
        ex['rep_scores_array'] = jsonEncode(ex['rep_scores_array']);
        await txn.insert('exercise_telemetry', ex);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getUnsyncedSessions() async {
    final db = await database;

    final sessions = await db.query(
      'workout_sessions',
      where: 'sync_status = ?',
      whereArgs: [0],
    );

    List<Map<String, dynamic>> masterPayload = [];

    for (var session in sessions) {
      Map<String, dynamic> sessionData = Map.from(session);

      final exercises = await db.query(
        'exercise_telemetry',
        where: 'session_id = ?',
        whereArgs: [session['id']],
      );

      List<Map<String, dynamic>> exercisesList = [];

      for (var ex in exercises) {
        Map<String, dynamic> exData = Map.from(ex);

        final reps = await db.query(
          'rep_telemetry',
          where: 'exercise_telemetry_id = ?',
          whereArgs: [ex['id']],
          orderBy: 'rep_number ASC',
        );

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

  Future<List<Map<String, dynamic>>> getCompletedSessions() async {
    final db = await database;
    return await db.query(
      'workout_sessions',
      where: 'status = ?',
      whereArgs: ['COMPLETED'],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> saveDownloadedHistory(
    List<dynamic> serverSessions,
    List<dynamic> processedVideos,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      // Optional but recommended: clear old pulled data first
      await txn.delete('rep_telemetry');
      await txn.delete('exercise_telemetry');
      await txn.delete('processed_videos');
      await txn.delete('workout_sessions');

      for (var session in serverSessions) {
        final Map<String, dynamic> sessionData = {
          'id': session['id'],
          'user_id': session['user_id'],
          'routine_id': session['routine_id'],
          'status': session['status'],
          'global_score': session['global_score'],
          'duration_seconds': session['duration_seconds'],
          'session_type': session['session_type'] ?? 'realtime',
          'sync_status': 1,
          'created_at': session['created_at'],
        };

        await txn.insert(
          'workout_sessions',
          sessionData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final List<dynamic> exercises = session['exercises'] ?? [];
        for (var ex in exercises) {
          final Map<String, dynamic> exData = {
            'id': ex['id'],
            'session_id': ex['session_id'],
            'exercise_name': ex['exercise_name'],
            'good_reps': ex['good_reps'],
            'bad_reps': ex['bad_reps'],
            'exercise_score': ex['exercise_score'],
          };

          await txn.insert(
            'exercise_telemetry',
            exData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          final List<dynamic> repScores = ex['rep_scores'] ?? ex['reps'] ?? [];
          for (int i = 0; i < repScores.length; i++) {
            await txn.insert(
              'rep_telemetry',
              {
                'id': const Uuid().v4(),
                'exercise_telemetry_id': ex['id'],
                'rep_number': i + 1,
                'score': (repScores[i] as num).toDouble(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }

      for (var item in processedVideos) {
        final Map<String, dynamic> processedData = {
          'id': item['id'],
          'user_id': item['user_id'],
          'session_id': item['session_id'],
          'exercise_name': item['exercise_name'],
          'result_json': item['result_json'],
          'file_path': item['file_path'],
          'file_name': item['file_name'],
          'score': item['score'],
          'model_status': item['model_status'] ?? 'processing',
          'error_message': item['error_message'],
          'created_at': item['created_at'],
        };

        await txn.insert(
          'processed_videos',
          processedData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<Map<String, dynamic>> getDashboardAggregates() async {
    final db = await database;

    final bentoResult = await db.rawQuery('''
      SELECT 
        (SELECT AVG(global_score) FROM workout_sessions WHERE status = 'COMPLETED' AND created_at >= date('now', '-7 days')) as weekly_avg,
        (SELECT AVG(global_score) FROM workout_sessions WHERE status = 'COMPLETED' AND created_at >= date('now', '-30 days')) as monthly_avg
    ''');

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

    final weeklyVolume = await db.rawQuery('''
      SELECT 
        SUM(s.duration_seconds) as total_time, 
        SUM(t.good_reps) as total_reps,
        COUNT(DISTINCT date(s.created_at)) as active_days
      FROM workout_sessions s
      JOIN exercise_telemetry t ON s.id = t.session_id
      WHERE s.status = 'COMPLETED' AND s.created_at >= date('now', '-6 days')
    ''');

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

    final diagnostics = await db.rawQuery('''
      SELECT exercise_name, AVG(exercise_score) as avg_score FROM exercise_telemetry 
      GROUP BY exercise_name ORDER BY avg_score DESC
    ''');

    final timelineRealtime = await db.rawQuery('''
  SELECT *, date(created_at) as session_date
  FROM workout_sessions
  WHERE status = 'COMPLETED'
    AND session_type = 'realtime'
  ORDER BY created_at DESC
''');

    final timelineAi = await db.rawQuery('''
  SELECT *, date(created_at) as session_date
  FROM workout_sessions
  WHERE status = 'COMPLETED'
    AND session_type = 'ai'
  ORDER BY created_at DESC
''');

    return {
      'bento': bentoResult.first,
      'last_known': lastSession.isNotEmpty ? lastSession.first : null,
      'weekly_volume': weeklyVolume.first,
      'graph_7': daily7,
      'graph_30': daily30,
      'diagnostics': diagnostics,
      'timeline_realtime': timelineRealtime,
      'timeline_ai': timelineAi,
    };
  }

  Future<List<Map<String, dynamic>>> getRawTelemetryForPeriod(int days) async {
    final db = await database;

    final rows = await db.rawQuery('''
      SELECT
        et.id as exercise_id,
        et.exercise_name,
        et.good_reps,
        et.bad_reps,
        rt.rep_number,
        rt.score
      FROM exercise_telemetry et
      JOIN workout_sessions ws ON et.session_id = ws.id
      LEFT JOIN rep_telemetry rt ON rt.exercise_telemetry_id = et.id
      WHERE ws.status = 'COMPLETED'
        AND ws.created_at >= date('now', '-$days days')
      ORDER BY et.exercise_name ASC, et.id ASC, rt.rep_number ASC
    ''');

    Map<String, Map<String, dynamic>> grouped = {};

    for (final row in rows) {
      final exerciseId = row['exercise_id'] as String;

      grouped.putIfAbsent(exerciseId, () {
        return {
          'exercise_name': row['exercise_name'],
          'good_reps': row['good_reps'],
          'bad_reps': row['bad_reps'],
          'rep_scores_array': <double>[],
        };
      });

      final score = row['score'];
      if (score != null) {
        (grouped[exerciseId]!['rep_scores_array'] as List<double>)
            .add((score as num).toDouble());
      }
    }

    return grouped.values.toList();
  }

  Future<List<Map<String, dynamic>>> getTelemetryForSession(
      String sessionId) async {
    final db = await database;
    return await db.query(
      'exercise_telemetry',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  // =========================
  // processed_videos helpers
  // =========================

  Future<int> insertProcessedVideo({
    required int userId,
    required String sessionId,
    required String exerciseName,
    required String resultJson,
    String? filePath,
    String? fileName,
    int? score,
    String modelStatus = 'processing',
    String? errorMessage,
  }) async {
    final db = await database;
    return await db.insert('processed_videos', {
      'user_id': userId,
      'session_id': sessionId,
      'exercise_name': exerciseName,
      'result_json': resultJson,
      'file_path': filePath,
      'file_name': fileName,
      'score': score,
      'model_status': modelStatus,
      'error_message': errorMessage,
    });
  }

  Future<void> updateProcessedVideoStatus({
    required int id,
    required String modelStatus,
    String? resultJson,
    String? filePath,
    String? fileName,
    int? score,
    String? errorMessage,
  }) async {
    final db = await database;

    final Map<String, dynamic> data = {
      'model_status': modelStatus,
      'error_message': errorMessage,
    };

    if (resultJson != null) data['result_json'] = resultJson;
    if (filePath != null) data['file_path'] = filePath;
    if (fileName != null) data['file_name'] = fileName;
    if (score != null) data['score'] = score;

    await db.update(
      'processed_videos',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getProcessedVideosForSession(
      String sessionId) async {
    final db = await database;
    return await db.query(
      'processed_videos',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getProcessedVideosByStatus(
      String status) async {
    final db = await database;
    return await db.query(
      'processed_videos',
      where: 'model_status = ?',
      whereArgs: [status],
      orderBy: 'created_at DESC',
    );
  }

  Future<Map<String, dynamic>?> getAiResultForSession(String sessionId) async {
    final db = await database;

    final result = await db.query(
      'processed_videos',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
      limit: 1,
    );

    if (result.isEmpty) return null;
    return result.first;
  }

  Future<List<Map<String, dynamic>>> getAiResultsForSession(
      String sessionId) async {
    final db = await database;

    final rows = await db.query(
      'processed_videos',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );

    return rows;
  }
}
