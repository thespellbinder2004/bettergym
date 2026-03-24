import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Keep your theme colors (mintGreen, darkSlate, neonRed)
import 'pose_camera_page.dart';

class SessionSetupPage extends StatefulWidget {
  const SessionSetupPage({super.key});

  @override
  State<SessionSetupPage> createState() => _SessionSetupPageState();
}

class _SessionSetupPageState extends State<SessionSetupPage> {
  List<WorkoutSet> _routine = [];
  bool _isLoading = true;

  // The Cleansed Exercise Database
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

  // --- PERSISTENCE LOGIC ---
  
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

  // --- HELPER LOGIC ---

  bool _isDurationBased(String name) {
    // Strict logic: Only Plank is duration-based. Add more here later if needed (e.g., Wall Sit).
    return name.toLowerCase() == 'plank';
  }

  // --- UI LOGIC ---

  void _showAddEditDialog({WorkoutSet? existingSet, int? index}) {
    String selectedName = existingSet?.name ?? _availableExercises.first;
    TextEditingController targetController = TextEditingController(text: existingSet?.target.toString() ?? '10');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool isDuration = _isDurationBased(selectedName);

            return AlertDialog(
              backgroundColor: darkSlate,
              title: Text(existingSet == null ? 'ADD EXERCISE' : 'EDIT EXERCISE', 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Strict Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedName,
                    dropdownColor: darkSlate,
                    style: const TextStyle(color: mintGreen, fontSize: 16, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Exercise',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: mintGreen)),
                    ),
                    items: _availableExercises.map((name) {
                      return DropdownMenuItem(value: name, child: Text(name));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedName = val;
                          isDuration = _isDurationBased(val);
                          // Optional: Auto-adjust target defaults when switching types
                          if (isDuration && targetController.text == '10') targetController.text = '60';
                          if (!isDuration && targetController.text == '60') targetController.text = '10';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  // Dynamic Target Field (Automatically changes label based on selection)
                  TextField(
                    controller: targetController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 24),
                    decoration: InputDecoration(
                      labelText: isDuration ? 'Target Seconds' : 'Target Reps',
                      labelStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: mintGreen)),
                      suffixIcon: Icon(isDuration ? Icons.timer : Icons.repeat, color: mintGreen),
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
                  style: ElevatedButton.styleFrom(backgroundColor: mintGreen, foregroundColor: Colors.black),
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
                    
                    _saveRoutine(); // Save to memory
                    Navigator.pop(context);
                  },
                  child: Text(existingSet == null ? 'ADD' : 'SAVE', style: const TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            );
          }
        );
      },
    );
  }

void _confirmRemoveSet(int index) {
    final item = _routine[index];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkSlate,
        title: const Text('DELETE EXERCISE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        content: Text('Are you sure you want to remove ${item.name.toUpperCase()} from your routine?', style: const TextStyle(color: Colors.grey, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: neonRed, foregroundColor: Colors.white),
            onPressed: () {
              setState(() {
                _routine.removeAt(index);
              });
              _saveRoutine(); // Save new state to persistent memory
              Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: mintGreen)));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('SESSION SETUP', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            onPressed: () {
              // TODO: Route to settings page
            },
          )
        ],
      ),
      body: _routine.isEmpty 
          ? const Center(
              child: Text(
                "NO EXERCISES LOADED.\nTAP '+' TO BUILD YOUR ROUTINE.", 
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16, letterSpacing: 1.5, height: 1.5)
              )
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 100, top: 16),
              itemCount: _routine.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _routine.removeAt(oldIndex);
                  _routine.insert(newIndex, item);
                });
                _saveRoutine(); // Save new order to memory
              },
              itemBuilder: (context, index) {
                final item = _routine[index];
                return Card(
                  key: ValueKey(item.hashCode), // Needed for ReorderableListView
                  color: darkSlate,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    title: Text(item.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        children: [
                          Icon(item.isDuration ? Icons.timer : Icons.repeat, color: mintGreen, size: 16),
                          const SizedBox(width: 8),
                          Text('${item.target} ${item.isDuration ? "SEC" : "REPS"}', style: const TextStyle(color: mintGreen, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.grey),
                          onPressed: () => _showAddEditDialog(existingSet: item, index: index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: neonRed),
                          onPressed: () => _confirmRemoveSet(index), // <-- UPDATED THIS LINE
                        ),
                        const Icon(Icons.drag_handle, color: Colors.grey),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'add_btn',
            backgroundColor: darkSlate,
            foregroundColor: mintGreen,
            onPressed: () => _showAddEditDialog(),
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 16),
          if (_routine.isNotEmpty)
            FloatingActionButton.extended(
              heroTag: 'start_btn',
              backgroundColor: mintGreen,
              foregroundColor: Colors.black,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PoseCameraPage(routine: _routine)),
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('START', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.0)),
            ),
        ],
      ),
    );
  }
}

// --- WORKOUT SET MODEL (With JSON Serialization) ---
class WorkoutSet {
  String name;
  int target;
  bool isDuration;

  WorkoutSet({
    required this.name,
    required this.target,
    this.isDuration = false,
  });

  // Convert to JSON to save in memory
  Map<String, dynamic> toJson() => {
    'name': name,
    'target': target,
    'isDuration': isDuration,
  };

  // Build from JSON when loading from memory
  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
    name: json['name'] as String,
    target: json['target'] as int,
    isDuration: json['isDuration'] as bool,
  );
}