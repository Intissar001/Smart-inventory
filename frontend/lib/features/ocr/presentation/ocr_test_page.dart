import 'package:flutter/material.dart';

import '../services/ocr_service.dart';
import '../services/medicine_matcher_service.dart';

class OCRTestPage extends StatefulWidget {
  const OCRTestPage({super.key});

  @override
  State<OCRTestPage> createState() => _OCRTestPageState();
}

class _OCRTestPageState extends State<OCRTestPage> {
  final OCRService ocrService = OCRService();
  final matcher = MedicineMatcherService();
  String medicineInfo = "";

  String recognizedText = "";

  int currentImage = 1;

  @override
  void initState() {
    super.initState();

    matcher.loadMedicines();
  }

  Future<void> runOCR() async {
    final imagePath =
        'assets/images-test/medicament_${currentImage.toString().padLeft(2, '0')}.jpeg';

    final result = await ocrService.processImage(imagePath);

    final medicine = matcher.findMedicine(result);

    setState(() {
      recognizedText = result;

      if (medicine != null) {
        medicineInfo = """
    Nom : ${medicine.name}

    Dosage : ${medicine.dosage}

    Forme : ${medicine.form}
    """;
      } else {
        medicineInfo = "Médicament non trouvé";
      }
    });
  } // <--- Added missing closing brace for runOCR

  @override
  Widget build(BuildContext context) {
    final imagePath =
        'assets/images-test/medicament_${currentImage.toString().padLeft(2, '0')}.jpeg';

    return Scaffold(
      appBar: AppBar(
        title: const Text("ML Kit OCR Test"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Image.asset(
              imagePath,
              height: 250,
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: runOCR,
              child: const Text("Run OCR"),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    if (currentImage > 1) {
                      setState(() {
                        currentImage--;
                        recognizedText = "";
                      });
                    }
                  },
                  child: const Text("Previous"),
                ),

                const SizedBox(width: 20),

                ElevatedButton(
                  onPressed: () {
                    if (currentImage < 10) {
                      setState(() {
                        currentImage++;
                        recognizedText = "";
                      });
                    }
                  },
                  child: const Text("Next"),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Text(
              medicineInfo,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  recognizedText,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ], // <--- Added missing closing bracket for children list
        ), // <--- Added missing closing parenthesis for Column
      ), // <--- Added missing closing parenthesis for Padding
    ); // <--- Added missing closing semicolon and parenthesis for Scaffold
  }
}