import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; 
import 'pose_camera_page.dart';

class SessionSetupPage extends StatefulWidget {
  const SessionSetupPage({super.key});

  @override
  State<SessionSetupPage> createState() => _SessionSetupPageState();
}

class _SessionSetupPageState extends State<SessionSetupPage> {
  List<WorkoutSet> _routine = [];
  Map<String, List<WorkoutSet>> _templates = {};
  bool _isLoading = true;

  final List<String> _availableExercises = [
    'Push Up',
    'Bench Dip',
    'Bicep Curl',
    'Squat',
    'Lunge',
    'Plank'
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String? savedRoutineStr = prefs.getString('saved_routine');
    if (savedRoutineStr != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(savedRoutineStr);
        _routine = decodedList.map((item) => WorkoutSet.fromJson(item)).toList();
      } catch (e) {
        debugPrint("Error loading routine: $e");
      }
    }

    final String? templatesStr = prefs.getString('saved_templates');
    if (templatesStr != null) {
      try {
        final Map<String, dynamic> decodedMap = jsonDecode(templatesStr);
        _templates = decodedMap.map((key, value) {
          final list = (value as List).map((item) => WorkoutSet.fromJson(item)).toList();
          return MapEntry(key, list);
        });
      } catch (e) {
        debugPrint("Error loading templates: $e");
      }
    }
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveActiveRoutine() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedRoutine = jsonEncode(_routine.map((e) => e.toJson()).toList());
    await prefs.setString('saved_routine', encodedRoutine);
  }

  Future<void> _saveTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> serializableMap = _templates.map((key, value) {
      return MapEntry(key, value.map((e) => e.toJson()).toList());
    });
    await prefs.setString('saved_templates', jsonEncode(serializableMap));
  }

  void _confirmDeleteTemplate(String templateName, StateSetter setSheetState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkSlate,
        title: const Text('DELETE TEMPLATE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Permanently delete the "$templateName" template?', style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: neonRed, foregroundColor: Colors.white),
            onPressed: () {
              setSheetState(() {
                _templates.remove(templateName);
              });
              _saveTemplates();
              Navigator.pop(context); 
            },
            child: const Text('DELETE', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showTemplateManager() {
    showModalBottomSheet(
      context: context,
      backgroundColor: darkSlate,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("TEMPLATES", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                  const SizedBox(height: 16),
                  
                  if (_routine.isNotEmpty)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: mintGreen, foregroundColor: navyBlue),
                      icon: const Icon(Icons.save),
                      label: const Text("SAVE CURRENT AS TEMPLATE", style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(context);
                        _promptSaveTemplate();
                      },
                    ),
                  
                  const Divider(color: Colors.grey, height: 32),
                  
                  _templates.isEmpty 
                    ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text("No templates saved.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                      )
                    : Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _templates.length,
                          itemBuilder: (context, index) {
                            String templateName = _templates.keys.elementAt(index);
                            return ListTile(
                              title: Text(templateName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text("${_templates[templateName]!.length} Exercises", style: const TextStyle(color: mintGreen)),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: neonRed),
                                onPressed: () => _confirmDeleteTemplate(templateName, setSheetState),
                              ),
                              onTap: () {
                                setState(() {
                                  // We generate fresh IDs when loading a template so they don't share memory references
                                  _routine = _templates[templateName]!.map((e) => WorkoutSet(name: e.name, target: e.target, isDuration: e.isDuration)).toList();
                                });
                                _saveActiveRoutine();
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                      ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _promptSaveTemplate() {
    TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkSlate,
        title: const Text('NAME TEMPLATE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "e.g., Upper Body Day",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: mintGreen)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: mintGreen, foregroundColor: navyBlue),
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                setState(() {
                  _templates[nameController.text] = _routine.map((e) => WorkoutSet(name: e.name, target: e.target, isDuration: e.isDuration)).toList();
                });
                _saveTemplates();
                Navigator.pop(context);
              }
            },
            child: const Text('SAVE'),
          )
        ],
      ),
    );
  }

  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkSlate,
        title: const Text('DELETE EXERCISE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Remove ${_routine[index].name} from your session?', style: const TextStyle(color: Colors.grey)),
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
              _saveActiveRoutine();
              Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showAddEditDialog({WorkoutSet? existingSet, int? index}) {
    String selectedName = existingSet?.name ?? _availableExercises.first;
    bool isDuration = selectedName.toLowerCase() == 'plank';
    
    int initialTarget = existingSet?.target ?? (isDuration ? 60 : 10);
    double sliderValue = initialTarget.toDouble().clamp(1.0, 300.0);
    TextEditingController targetController = TextEditingController(text: initialTarget.toString());

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: darkSlate,
              title: Text(existingSet == null ? 'ADD EXERCISE' : 'EDIT EXERCISE', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedName,
                    dropdownColor: navyBlue,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    items: _availableExercises.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedName = val;
                          isDuration = selectedName.toLowerCase() == 'plank';
                          
                          int newTarget = isDuration ? 60 : 10;
                          sliderValue = newTarget.toDouble();
                          targetController.text = newTarget.toString();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  TextField(
                    controller: targetController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: isDuration ? 'Target (Seconds)' : 'Target (Reps)',
                      labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: mintGreen)),
                    ),
                    onChanged: (val) {
                      int? parsed = int.tryParse(val);
                      if (parsed != null) {
                        setDialogState(() {
                          sliderValue = parsed.toDouble().clamp(1.0, 300.0);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: mintGreen,
                      inactiveTrackColor: Colors.grey.shade800,
                      thumbColor: Colors.white,
                      overlayColor: mintGreen.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: sliderValue,
                      min: 1,
                      max: 300, 
                      divisions: 299,
                      onChanged: (val) {
                        setDialogState(() {
                          sliderValue = val;
                          targetController.text = val.toInt().toString();
                        });
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: mintGreen, foregroundColor: navyBlue),
                  onPressed: () {
                    final target = int.tryParse(targetController.text) ?? (isDuration ? 60 : 10);
                    
                    setState(() {
                      if (index != null) {
                        // Keep original ID if editing
                        _routine[index].name = selectedName;
                        _routine[index].target = target;
                        _routine[index].isDuration = isDuration;
                      } else {
                        // Generates a fresh unique ID automatically
                        _routine.add(WorkoutSet(name: selectedName, target: target, isDuration: isDuration));
                      }
                    });
                    
                    _saveActiveRoutine(); 
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

  Widget _buildAddButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: mintGreen,
        side: const BorderSide(color: mintGreen, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.add),
      label: const Text('ADD EXERCISE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      onPressed: () => _showAddEditDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: navyBlue, body: Center(child: CircularProgressIndicator(color: mintGreen)));
    }

    return Scaffold(
      backgroundColor: navyBlue, 
      appBar: AppBar(
        backgroundColor: navyBlue, 
        title: const Text('SESSION SETUP', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined, color: Colors.white),
            tooltip: "Templates",
            onPressed: _showTemplateManager,
          )
        ],
      ),
      body: _routine.isEmpty 
          ? Center(child: _buildAddButton()) 
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 100, top: 16),
              itemCount: _routine.length,
              // Requires items to be dragged instantly by the handle instead of long-pressing the whole card
              buildDefaultDragHandles: false, 
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _routine.removeAt(oldIndex);
                  _routine.insert(newIndex, item);
                });
                _saveActiveRoutine(); 
              },
              footer: Padding(
                key: const Key("add_button_footer"),
                padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                child: Center(child: _buildAddButton()),
              ),
              itemBuilder: (context, index) {
                final item = _routine[index];
                return Card(
                  // Now driven by an absolute unique identifier
                  key: ValueKey(item.id), 
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
                          onPressed: () => _confirmDelete(index),
                        ),
                        // --- THE FIX: The functional drag handle ---
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8.0, right: 8.0),
                            child: Icon(Icons.drag_handle, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'start_btn',
        backgroundColor: _routine.isEmpty ? Colors.grey.shade800 : mintGreen,
        foregroundColor: _routine.isEmpty ? Colors.grey.shade500 : navyBlue,
        onPressed: _routine.isEmpty ? null : () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PoseCameraPage(routine: _routine)),
          );
        },
        icon: const Icon(Icons.play_arrow),
        label: const Text('START SESSION', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// --- WORKOUT SET MODEL (Now with Immutable Unique IDs) ---
class WorkoutSet {
  final String id; 
  String name;
  int target;
  bool isDuration;

  WorkoutSet({
    String? id,
    required this.name,
    required this.target,
    this.isDuration = false,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(); 

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'target': target,
    'isDuration': isDuration,
  };

  // The 'id' check handles backward compatibility in case you load an old save that didn't have an ID
  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
    id: json['id'] as String?,
    name: json['name'] as String,
    target: json['target'] as int,
    isDuration: json['isDuration'] as bool,
  );
}