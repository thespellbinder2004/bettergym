import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Inherits your existing theme colors
import 'pose_camera_page.dart';

class SessionSetupPage extends StatefulWidget {
  const SessionSetupPage({super.key});

  @override
  State<SessionSetupPage> createState() => _SessionSetupPageState();
}

class _SessionSetupPageState extends State<SessionSetupPage> {
  List<WorkoutSet> _routine = [];
  bool _isLoading = true;

  // 1. Cleansed Exercise List
  final List<String> _availableExercises = [
    'Push Up',
    'Bench Dip',
    'Bicep Curl',
    'Squat',
    'Plank'
  ];

  @override
  void initState() {
    super.initState();
    _loadRoutine();
  }

  // --- PERSISTENCE LOGIC (Loads last setup) ---
  Future<void> _loadRoutine() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedRoutineStr = prefs.getString('saved_routine');
    
    if (savedRoutineStr != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(savedRoutineStr);
        setState(() {
          _routine = decodedList.map((item) => WorkoutSet.fromJson(item)).toList();
        });
      } catch (e) {
        debugPrint("Error loading routine: $e");
      }
    }
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveRoutine() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedRoutine = jsonEncode(_routine.map((e) => e.toJson()).toList());
    await prefs.setString('saved_routine', encodedRoutine);
  }

  // --- DELETE CONFIRMATION ---
  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Delete Exercise?', style: TextStyle(color: Colors.white)),
        content: Text('Remove ${_routine[index].name} from your session?', style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _routine.removeAt(index);
              });
              _saveRoutine();
              Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.redAccent)),
          )
        ],
      ),
    );
  }

  // --- ADD/EDIT DIALOG (No more Duration Checkbox) ---
  void _showAddEditDialog({WorkoutSet? existingSet, int? index}) {
    String selectedName = existingSet?.name ?? _availableExercises.first;
    TextEditingController targetController = TextEditingController(text: existingSet?.target.toString() ?? '10');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 2. Auto-Duration Logic
            bool isDuration = selectedName.toLowerCase() == 'plank';

            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: Text(existingSet == null ? 'Add Exercise' : 'Edit Exercise', style: const TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedName,
                    dropdownColor: Colors.grey[850],
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    items: _availableExercises.map((name) {
                      return DropdownMenuItem(value: name, child: Text(name));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedName = val;
                          isDuration = selectedName.toLowerCase() == 'plank';
                          
                          // Smart defaults: If they switch to plank, default to 60s. Otherwise 10 reps.
                          if (isDuration && targetController.text == '10') targetController.text = '60';
                          if (!isDuration && targetController.text == '60') targetController.text = '10';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: targetController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      // Dynamically changes text based on exercise type
                      labelText: isDuration ? 'Target (Seconds)' : 'Target (Reps)',
                      labelStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
                  onPressed: () {
                    final target = int.tryParse(targetController.text) ?? (isDuration ? 60 : 10);
                    final newSet = WorkoutSet(name: selectedName, target: target, isDuration: isDuration);

                    setState(() {
                      if (index != null) {
                        _routine[index] = newSet;
                      } else {
                        _routine.add(newSet);
                      }
                    });
                    
                    _saveRoutine(); // Save to memory instantly
                    Navigator.pop(context);
                  },
                  child: Text(existingSet == null ? 'ADD' : 'SAVE'),
                )
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Session Setup', style: TextStyle(color: Colors.white)),
      ),
      body: _routine.isEmpty 
          ? Center(
              // 4. Clean Empty State (Just the Add Button)
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                icon: const Icon(Icons.add),
                label: const Text('ADD EXERCISE', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => _showAddEditDialog(),
              ),
            )
          : ListView.builder(
              itemCount: _routine.length,
              itemBuilder: (context, index) {
                final item = _routine[index];
                return Card(
                  color: Colors.grey[900],
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text('${item.target} ${item.isDuration ? "Seconds" : "Reps"}', style: const TextStyle(color: Colors.tealAccent)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.grey),
                          onPressed: () => _showAddEditDialog(existingSet: item, index: index),
                        ),
                        // 5. Delete Confirmation Wire-up
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => _confirmDelete(index),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: _routine.isEmpty ? null : Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'add_btn',
            backgroundColor: Colors.grey[800],
            foregroundColor: Colors.white,
            onPressed: () => _showAddEditDialog(),
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: 'start_btn',
            backgroundColor: Colors.tealAccent,
            foregroundColor: Colors.black,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PoseCameraPage(routine: _routine)),
              );
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('START SESSION', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// --- WORKOUT SET MODEL (With JSON Serialization for Memory) ---
class WorkoutSet {
  String name;
  int target;
  bool isDuration;

  WorkoutSet({
    required this.name,
    required this.target,
    this.isDuration = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'target': target,
    'isDuration': isDuration,
  };

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
    name: json['name'] as String,
    target: json['target'] as int,
    isDuration: json['isDuration'] as bool,
  );
}