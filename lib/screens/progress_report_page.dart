import 'package:flutter/material.dart';
import '../main.dart';
import 'main_layout.dart';

class ProgressReportPage extends StatelessWidget {
  const ProgressReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navyBlue,
      appBar: AppBar(
        backgroundColor: navyBlue,
        elevation: 0,
        title: const Text('PROGRESS REPORT', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
        centerTitle: true,
        automaticallyImplyLeading: false, 
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart, size: 100, color: darkSlate),
            const SizedBox(height: 24),
            const Text(
              "REPORT ENGINE UNDER CONSTRUCTION",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16, letterSpacing: 1.5),
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: mintGreen,
                foregroundColor: navyBlue,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.dashboard),
              label: const Text("RETURN TO DASHBOARD", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const MainLayout()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}