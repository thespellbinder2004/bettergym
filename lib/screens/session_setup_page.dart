import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart'; 
import 'pose_camera_page.dart';

class WorkoutSet {
  final String id; 
  String name;
  int target;
  bool isDuration;

  WorkoutSet({required this.name, required this.target, required this.isDuration})
      : id = DateTime.now().microsecondsSinceEpoch.toString(); 

  Map<String, dynamic> toJson() => {
        'name': name,
        'target': target,
        'isDuration': isDuration,
      };

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
        name: json['name'],
        target: json['target'],
        isDuration: json['isDuration'],
      );
}

class SessionSetupPage extends StatefulWidget {
  const SessionSetupPage({super.key}); // CLEANED

  @override
  State<SessionSetupPage> createState() => _SessionSetupPageState();
}

class _SessionSetupPageState extends State<SessionSetupPage> {
  final List<String> _availableExercises = [
    'Plank', 'Pushup', 'Lunges', 'Bicep Curls', 'Squats', 
    'Pull Ups', 'Pike Pushups', 'Sit Ups', 'Dips', 'Bench Dips'
  ];

  List<WorkoutSet> _routine = [
    WorkoutSet(name: 'Squats', target: 15, isDuration: false),
    WorkoutSet(name: 'Plank', target: 60, isDuration: true),
  ];

  Future<void> _saveTemplate() async {
    if (_routine.isEmpty) return;

    TextEditingController nameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkSlate,
        title: const Text('Save Template', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "e.g., Leg Day Alpha", hintStyle: const TextStyle(color: Colors.grey),
            filled: true, fillColor: navyBlue, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: mintGreen, foregroundColor: navyBlue),
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              final prefs = await SharedPreferences.getInstance();
              String? existingPrefs = prefs.getString('saved_templates');
              Map<String, dynamic> templates = existingPrefs != null ? jsonDecode(existingPrefs) : {};
              templates[nameController.text] = _routine.map((e) => e.toJson()).toList();
              await prefs.setString('saved_templates', jsonEncode(templates));
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template saved.'), backgroundColor: mintGreen));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    String? existingPrefs = prefs.getString('saved_templates');
    if (existingPrefs == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved templates found.'), backgroundColor: Colors.red));
      return;
    }

    Map<String, dynamic> templates = jsonDecode(existingPrefs);
    if (templates.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved templates found.'), backgroundColor: Colors.red));
      return;
    }

    if (!mounted) return;
    
    showModalBottomSheet(
      context: context, backgroundColor: darkSlate, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (templates.isEmpty) return const Center(child: Text("All templates deleted.", style: TextStyle(color: Colors.grey)));
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Load Template', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ...templates.keys.map((templateName) => ListTile(
                  title: Text(templateName, style: const TextStyle(color: mintGreen, fontWeight: FontWeight.bold)),
                  subtitle: Text('${(templates[templateName] as List).length} exercises', style: const TextStyle(color: Colors.grey)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: neonRed),
                    onPressed: () async {
                      setModalState(() { templates.remove(templateName); });
                      await prefs.setString('saved_templates', jsonEncode(templates));
                      if (templates.isEmpty && mounted) Navigator.pop(context);
                    },
                  ),
                  onTap: () {
                    setState(() {
                      _routine = (templates[templateName] as List).map((item) => WorkoutSet.fromJson(item)).toList();
                    });
                    Navigator.pop(context);
                  },
                )),
              ],
            );
          }
        );
      },
    );
  }

  void _addOrEditExercise({WorkoutSet? existingSet, int? index}) {
    String selectedName = existingSet?.name ?? _availableExercises.first;
    TextEditingController targetController = TextEditingController(text: existingSet?.target.toString() ?? '');
    bool isDuration = existingSet?.isDuration ?? false;
    String? errorMessage; 

    showModalBottomSheet(
      context: context, backgroundColor: darkSlate, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(existingSet == null ? 'Add Exercise' : 'Edit Exercise', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    dropdownColor: navyBlue, value: selectedName, style: const TextStyle(color: mintGreen),
                    decoration: InputDecoration(filled: true, fillColor: navyBlue, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                    items: _availableExercises.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) { if (val != null) setModalState(() => selectedName = val); },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: targetController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: isDuration ? 'Target (Seconds)' : 'Target (Reps)', labelStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: navyBlue,
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: errorMessage != null ? const BorderSide(color: neonRed, width: 2) : BorderSide.none),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: errorMessage != null ? const BorderSide(color: neonRed, width: 2) : const BorderSide(color: mintGreen, width: 2)),
                              ),
                              onChanged: (_) { if (errorMessage != null) setModalState(() => errorMessage = null); },
                            ),
                            if (errorMessage != null)
                              Padding(padding: const EdgeInsets.only(top: 8, left: 4), child: Text(errorMessage!, style: const TextStyle(color: neonRed, fontSize: 12, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          children: [
                            const Text('Duration?', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Switch(
                              activeColor: mintGreen, value: isDuration, 
                              onChanged: (val) { setModalState(() { isDuration = val; errorMessage = null; }); }
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: mintGreen, foregroundColor: navyBlue, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () {
                      final target = int.tryParse(targetController.text);
                      if (target == null || target <= 0) {
                        setModalState(() { errorMessage = isDuration ? "Must be at least 1 second." : "Must be at least 1 rep."; });
                        return; 
                      }
                      setState(() {
                        if (existingSet != null && index != null) {
                          existingSet.name = selectedName; existingSet.target = target; existingSet.isDuration = isDuration;
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

  void _removeExercise(int index) { setState(() => _routine.removeAt(index)); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Setup'), centerTitle: false, automaticallyImplyLeading: false, 
        actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.grey)), icon: const Icon(Icons.folder_open, size: 18), label: const Text('Load'), onPressed: _loadTemplate)),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: mintGreen, side: const BorderSide(color: mintGreen)), icon: const Icon(Icons.save, size: 18), label: const Text('Save'), onPressed: _routine.isEmpty ? null : _saveTemplate)),
              ],
            ),
          ),
          Expanded(
            child: _routine.isEmpty
                ? Center(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: mintGreen, side: const BorderSide(color: mintGreen)), icon: const Icon(Icons.add), label: const Text('ADD EXERCISE'), onPressed: () => _addOrEditExercise()))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(16), itemCount: _routine.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _routine.removeAt(oldIndex);
                        _routine.insert(newIndex, item);
                      });
                    },
                    footer: Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: mintGreen, side: const BorderSide(color: mintGreen), minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        icon: const Icon(Icons.add), label: const Text('ADD EXERCISE'), onPressed: () => _addOrEditExercise(),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final set = _routine[index];
                      return Card(
                        key: Key(set.id), color: darkSlate, margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: navyBlue, child: Text('${index + 1}', style: const TextStyle(color: mintGreen))),
                          title: Text(set.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text(set.isDuration ? '${set.target} seconds' : '${set.target} reps', style: const TextStyle(color: Colors.grey)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, color: Colors.grey, size: 20), onPressed: () => _addOrEditExercise(existingSet: set, index: index)),
                              IconButton(icon: const Icon(Icons.delete, color: neonRed, size: 20), onPressed: () => _removeExercise(index)),
                              ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle, color: Colors.grey)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: navyBlue, border: Border(top: BorderSide(color: mintGreen.withOpacity(0.2)))),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.shade400, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 8,
              ),
              onPressed: _routine.isEmpty ? null : () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PoseCameraPage(routine: _routine))); // CLEANED
              },
              child: const Text('START SESSION', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ),
          )
        ],
      ),
    );
  }
}