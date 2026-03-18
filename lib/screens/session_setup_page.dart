import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../main.dart'; 
import 'pose_camera_page.dart';

class WorkoutSet {
  final String id; 
  String name;
  int target;
  bool isDuration;

  WorkoutSet({required this.name, required this.target, required this.isDuration})
      : id = DateTime.now().microsecondsSinceEpoch.toString(); 
}

class SessionSetupPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const SessionSetupPage({super.key, required this.cameras});

  @override
  State<SessionSetupPage> createState() => _SessionSetupPageState();
}

class _SessionSetupPageState extends State<SessionSetupPage> {
  final List<String> _availableExercises = [
    'Plank', 'Pushup', 'Lunges', 'Bicep Curls', 'Squats', 
    'Pull Ups', 'Pike Pushups', 'Sit Ups', 'Dips', 'Bench Dips'
  ];

  final List<WorkoutSet> _routine = [
    WorkoutSet(name: 'Squats', target: 15, isDuration: false),
    WorkoutSet(name: 'Plank', target: 60, isDuration: true),
  ];

  void _addOrEditExercise({WorkoutSet? existingSet, int? index}) {
    String selectedName = existingSet?.name ?? _availableExercises.first;
    TextEditingController targetController = TextEditingController(text: existingSet?.target.toString() ?? '10');
    bool isDuration = existingSet?.isDuration ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: darkSlate,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20, right: 20, top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(existingSet == null ? 'Add Exercise' : 'Edit Exercise', 
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    dropdownColor: navyBlue,
                    value: selectedName,
                    style: const TextStyle(color: mintGreen),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: navyBlue,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    items: _availableExercises.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedName = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: targetController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: isDuration ? 'Target (Seconds)' : 'Target (Reps)',
                            labelStyle: const TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: navyBlue,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        children: [
                          const Text('Duration?', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Switch(
                            activeColor: mintGreen,
                            value: isDuration,
                            onChanged: (val) => setModalState(() => isDuration = val),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mintGreen,
                      foregroundColor: navyBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      final target = int.tryParse(targetController.text) ?? 10;
                      setState(() {
                        if (existingSet != null && index != null) {
                          existingSet.name = selectedName;
                          existingSet.target = target;
                          existingSet.isDuration = isDuration;
                        } else {
                          _routine.add(WorkoutSet(name: selectedName, target: target, isDuration: isDuration));
                        }
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('SAVE TO ROUTINE', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          }
        );
      },
    );
  }

  void _removeExercise(int index) {
    setState(() {
      _routine.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Setup'), 
        centerTitle: false, // Left aligned
        leading: null, // Removes default left button
        automaticallyImplyLeading: false, 
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context), // Right aligned exit
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _routine.isEmpty
                ? Center(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: mintGreen, side: const BorderSide(color: mintGreen)),
                      icon: const Icon(Icons.add),
                      label: const Text('ADD EXERCISE'),
                      onPressed: () => _addOrEditExercise(),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _routine.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _routine.removeAt(oldIndex);
                        _routine.insert(newIndex, item);
                      });
                    },
                    // Embedded Add Button in the scrolling list
                    footer: Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: mintGreen,
                          side: const BorderSide(color: mintGreen),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('ADD EXERCISE'),
                        onPressed: () => _addOrEditExercise(),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final set = _routine[index];
                      return Card(
                        key: Key(set.id), 
                        color: darkSlate,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: navyBlue,
                            child: Text('${index + 1}', style: const TextStyle(color: mintGreen)),
                          ),
                          title: Text(set.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text(set.isDuration ? '${set.target} seconds' : '${set.target} reps', style: const TextStyle(color: Colors.grey)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.grey, size: 20),
                                onPressed: () => _addOrEditExercise(existingSet: set, index: index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: neonRed, size: 20),
                                onPressed: () => _removeExercise(index),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: navyBlue,
              border: Border(top: BorderSide(color: mintGreen.withOpacity(0.2))),
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.shade400,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 8,
              ),
              onPressed: _routine.isEmpty ? null : () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PoseCameraPage(
                      cameras: widget.cameras,
                      routine: _routine, // Passing the configured routine
                    ),
                  ),
                );
              },
              child: const Text(
                'START SESSION',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
            ),
          )
        ],
      ),
    );
  }
}