import 'package:flutter/material.dart';

import '../main.dart'; // Inherit global colors
import 'main_layout.dart';
import 'progress_report_page.dart';

class SessionSummaryPage extends StatefulWidget {
  
  // We can pass real data here later when the ML math is done.
  // For now, these are placeholders for the UI.
  final int totalReps;
  final int durationMinutes;
  final int formWarnings;

  const SessionSummaryPage({
    super.key, 
    this.totalReps = 142,
    this.durationMinutes = 45,
    this.formWarnings = 3,
  });

  @override
  State<SessionSummaryPage> createState() => _SessionSummaryPageState();
}

class _SessionSummaryPageState extends State<SessionSummaryPage> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1200)
    );
    
    // Delays the button appearance so the user focuses on the checkmark first
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.5, 1.0, curve: Curves.easeIn))
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Widget _buildStatBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.0)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              
              // --- HERO SECTION ---
              TweenAnimationBuilder(
                tween: Tween<double>(begin: 0.5, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: mintGreen.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: mintGreen, width: 4),
                    boxShadow: [
                      BoxShadow(color: mintGreen.withOpacity(0.3), blurRadius: 30, spreadRadius: 5),
                    ]
                  ),
                  child: const Icon(Icons.check_rounded, color: mintGreen, size: 80),
                ),
              ),
              
              const SizedBox(height: 32),
              
              const Text(
                'SESSION COMPLETE',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 3.0),
              ),
              const SizedBox(height: 8),
              const Text(
                'Biomechanical data successfully logged.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              
              const SizedBox(height: 48),

              // --- STATS GRID ---
              Row(
                children: [
                  Expanded(child: _buildStatBox('TOTAL REPS', widget.totalReps.toString(), Icons.fitness_center, mintGreen)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatBox('MINUTES', widget.durationMinutes.toString(), Icons.timer, Colors.blueAccent)),
                ],
              ),
              const SizedBox(height: 16),
              _buildStatBox('FORM WARNINGS', widget.formWarnings.toString(), Icons.warning_amber_rounded, widget.formWarnings > 5 ? neonRed : Colors.orange),

              const Spacer(),

              // --- ACTIONS ---
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: mintGreen,
                        foregroundColor: navyBlue,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => ProgressReportPage()),
                        );
                      },
                      child: const Text('VIEW DETAILED REPORT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.grey),
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        // Flushes the route stack and returns to the Dashboard
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => MainLayout()),
                          (route) => false,
                        );
                      },
                      child: const Text('RETURN TO DASHBOARD', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}