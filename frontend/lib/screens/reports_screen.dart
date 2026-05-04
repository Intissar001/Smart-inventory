import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as ex;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/settings_provider.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with TickerProviderStateMixin {
  int touchedIndex = -1;

  late AnimationController _animationController;
  double _animationProgress = 0.0;
  UniqueKey _pieChartKey = UniqueKey();

  final List<Map<String, dynamic>> chartData = [
    {'name': 'Analgesics', 'val': 450.0, 'col': Colors.blue},
    {'name': 'Antibiotics', 'val': 320.0, 'col': Colors.green},
    {'name': 'Vitamins', 'val': 280.0, 'col': Colors.orange},
    {'name': 'Antiseptics', 'val': 200.0, 'col': Colors.purple},
    {'name': 'Others', 'val': 150.0, 'col': Colors.blueGrey},
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addListener(() {
      if (mounted) {
        setState(() {
          _animationProgress = _animationController.value;
        });
      }
    });
    _animationController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resetAndAnimate();
  }

  void _resetAndAnimate() {
    if (_animationController.isAnimating) return;
    _animationController.reset();
    _animationController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _pieChartKey = UniqueKey();
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _showProcessingDialog(String type) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 50,
                width: 50,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Generating $type",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Organizing pharmaceutical data...",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleExport(String type) async {
    _showProcessingDialog(type);

    try {
      await Future.delayed(const Duration(milliseconds: 1500));

      if (type == "PDF") {
        final pdf = pw.Document();
        final primaryColor = PdfColor.fromInt(0xFF2563EB);

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) => [
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: primaryColor,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("PHARMA REPORT", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 18)),
                        pw.Text("Inventory Analytics", style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                      ],
                    ),
                    pw.Text(DateTime.now().toString().split(' ')[0], style: const pw.TextStyle(color: PdfColors.white)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                context: context,
                border: null,
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                headerDecoration: pw.BoxDecoration(color: primaryColor),
                rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5))),
                cellHeight: 30,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                },
                data: <List<String>>[
                  <String>['Medicine Category', 'Current Stock Value'],
                  ...chartData.map((item) => [item['name'], "${item['val'].toInt()} Units"])
                ],
              ),
              pw.SizedBox(height: 40),
              pw.Divider(color: PdfColors.grey300),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text("Total Inventory: 1,450 Items", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: primaryColor)),
              )
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
        await Printing.layoutPdf(onLayout: (format) => pdf.save(), name: 'Pharma_Report_${DateTime.now().millisecondsSinceEpoch}');
      }

      else if (type == "Excel") {
        var excel = ex.Excel.createExcel();
        ex.Sheet sheet = excel['Inventory Analytics'];

        var cellStyle = ex.CellStyle(
          backgroundColorHex: ex.ExcelColor.fromHexString("#2563EB"),
          fontColorHex: ex.ExcelColor.fromHexString("#FFFFFF"),
          bold: true,
          horizontalAlign: ex.HorizontalAlign.Center,
        );

        sheet.appendRow([ex.TextCellValue("Medicine Category"), ex.TextCellValue("Stock Units")]);
        sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).cellStyle = cellStyle;
        sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).cellStyle = cellStyle;

        for (var item in chartData) {
          sheet.appendRow([
            ex.TextCellValue(item['name']),
            ex.IntCellValue(item['val'].toInt())
          ]);
        }

        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/Pharma_Inventory_Report.xlsx');
        await file.writeAsBytes(excel.encode()!);

        if (mounted) Navigator.pop(context);
        await Share.shareXFiles([XFile(file.path)], text: 'Monthly Pharmacy Inventory Report');
      }

      else if (type == "Share") {
        if (mounted) Navigator.pop(context);
        String shareText = "📊 *PHARMA INVENTORY INSIGHTS*\n"
            "Date: ${DateTime.now().toString().split(' ')[0]}\n"
            "----------------------------\n"
            "• Total Medicines: 1,450\n"
            "• Top Category: Analgesics (450)\n"
            "----------------------------\n"
            "Detailed stock charts are available in the management app.";
        await Share.share(shareText);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final isDark = settings.darkMode;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF2563EB),
        automaticallyImplyLeading: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Reports & Analytics",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text("Inventory Insights",
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _buildExportBtn(Icons.picture_as_pdf, "PDF", isDark ? Colors.red.withOpacity(0.1) : Colors.red.shade50, Colors.red, () => _handleExport("PDF")),
                    const SizedBox(width: 12),
                    _buildExportBtn(Icons.file_download, "Excel", isDark ? Colors.green.withOpacity(0.1) : Colors.green.shade50, Colors.green, () => _handleExport("Excel")),
                    const SizedBox(width: 12),
                    _buildExportBtn(Icons.share_outlined, "Share", isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.shade50, Colors.blue, () => _handleExport("Share")),
                  ],
                ),
                const SizedBox(height: 20),
                _buildChartCard(cardColor, isDark),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _buildSummaryCard("1,450", "Total Medicines", const Color(0xFF2563EB), Colors.white),
                    const SizedBox(width: 12),
                    _buildSummaryCard("8,750", "Total Boxes", const Color(0xFF10B981), Colors.white),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportBtn(IconData icon, String label, Color bg, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard(Color cardColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Color(0xFF2563EB), size: 20),
              const SizedBox(width: 8),
              Text("Stock Distribution by Category",
                  style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
            ],
          ),
          const SizedBox(height: 30),
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  key: _pieChartKey,
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            touchedIndex = -1;
                            return;
                          }
                          touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                    sectionsSpace: 4,
                    centerSpaceRadius: 65,
                    sections: _getAnimatedSections(),
                  ),
                ),
                if (touchedIndex != -1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: Text(
                      "${chartData[touchedIndex]['name']} : ${(chartData[touchedIndex]['val'] as double).toInt()}",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: chartData.map((data) => _LegendItem(color: data['col'], label: data['name'])).toList(),
          )
        ],
      ),
    );
  }

  List<PieChartSectionData> _getAnimatedSections() {
    return List.generate(chartData.length, (i) {
      final isTouched = i == touchedIndex;
      final radius = isTouched ? 45.0 : 35.0;

      double animatedValue = (chartData[i]['val'] as double) * _animationProgress;
      double total = chartData.fold<double>(0, (sum, item) => sum + (item['val'] as double));
      double percentage = (animatedValue / total) * 100;

      return PieChartSectionData(
        color: chartData[i]['col'] as Color,
        value: animatedValue,
        title: _animationProgress >= 0.9 ? '${percentage.toInt()}%' : '',
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        radius: radius,
        showTitle: _animationProgress >= 0.7,
      );
    });
  }

  Widget _buildSummaryCard(String val, String label, Color bg, Color textCol) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          children: [
            Text(val, style: TextStyle(color: textCol, fontSize: 24, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: textCol.withOpacity(0.8), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<SettingsProvider>(context).darkMode;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 10, width: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
      ],
    );
  }
}