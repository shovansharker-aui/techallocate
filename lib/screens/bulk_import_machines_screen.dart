import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

// Bulk-import machines from a CSV file. Expected columns (header row
// required, any order, case-insensitive):
//   Equipment ID, Equipment Name, Brand, Category
// Category must be Engineering, Production, or Warehouse.
// Matching by Equipment ID: if a machine with that ID already exists,
// it's updated instead of duplicated.
class BulkImportMachinesScreen extends StatefulWidget {
  const BulkImportMachinesScreen({super.key});

  @override
  State<BulkImportMachinesScreen> createState() => _BulkImportMachinesScreenState();
}

class _ParsedRow {
  final int lineNumber;
  final String equipmentId;
  final String equipmentName;
  final String brand;
  final String category;
  final String? error;
  const _ParsedRow({
    required this.lineNumber,
    required this.equipmentId,
    required this.equipmentName,
    required this.brand,
    required this.category,
    this.error,
  });
  bool get isValid => error == null;
}

class _BulkImportMachinesScreenState extends State<BulkImportMachinesScreen> {
  static const _validCategories = ['Engineering', 'Production', 'Warehouse'];

  String? _fileName;
  List<_ParsedRow> _rows = [];
  bool _isImporting = false;
  String? _resultMessage;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    final bytes = result.files.single.bytes!;
    final content = String.fromCharCodes(bytes);
    final table = const CsvToListConverter(shouldParseNumbers: false).convert(content, eol: '\n');

    if (table.isEmpty) {
      setState(() {
        _fileName = result.files.single.name;
        _rows = [];
        _resultMessage = 'That file appears to be empty.';
      });
      return;
    }

    final header = table.first.map((c) => c.toString().trim().toLowerCase()).toList();
    final idCol = header.indexWhere((h) => h.contains('equipment id') || h == 'id');
    final nameCol = header.indexWhere((h) => h.contains('equipment name') || h == 'name');
    final brandCol = header.indexWhere((h) => h.contains('brand'));
    final categoryCol = header.indexWhere((h) => h.contains('category'));

    if (idCol == -1 || nameCol == -1) {
      setState(() {
        _fileName = result.files.single.name;
        _rows = [];
        _resultMessage = 'Could not find "Equipment ID" and "Equipment Name" columns in the header row.';
      });
      return;
    }

    final parsed = <_ParsedRow>[];
    for (var i = 1; i < table.length; i++) {
      final row = table[i];
      if (row.every((c) => c.toString().trim().isEmpty)) continue; // skip blank lines

      String field(int col) => col == -1 || col >= row.length ? '' : row[col].toString().trim();

      final equipmentId = field(idCol);
      final equipmentName = field(nameCol);
      final brand = field(brandCol);
      var category = field(categoryCol);
      final normalized = _validCategories.firstWhere(
        (c) => c.toLowerCase() == category.toLowerCase(),
        orElse: () => '',
      );

      String? error;
      if (equipmentId.isEmpty) {
        error = 'Missing Equipment ID';
      } else if (equipmentName.isEmpty) {
        error = 'Missing Equipment Name';
      } else if (category.isNotEmpty && normalized.isEmpty) {
        error = 'Category must be Engineering, Production, or Warehouse (found "$category")';
      }
      category = normalized.isEmpty ? 'Production' : normalized;

      parsed.add(_ParsedRow(
        lineNumber: i + 1,
        equipmentId: equipmentId,
        equipmentName: equipmentName,
        brand: brand,
        category: category,
        error: error,
      ));
    }

    setState(() {
      _fileName = result.files.single.name;
      _rows = parsed;
      _resultMessage = null;
    });
  }

  Future<void> _import() async {
    final validRows = _rows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) return;

    setState(() => _isImporting = true);

    final machines = FirebaseFirestore.instance.collection('machines');
    // Firestore batches cap at 500 writes — chunk if a very large file
    // is ever imported.
    var created = 0, updated = 0;
    for (var i = 0; i < validRows.length; i += 400) {
      final chunk = validRows.skip(i).take(400);
      final batch = FirebaseFirestore.instance.batch();
      for (final row in chunk) {
        final existing = await machines.where('equipmentId', isEqualTo: row.equipmentId).limit(1).get();
        final data = {
          'equipmentId': row.equipmentId,
          'equipmentName': row.equipmentName,
          'brand': row.brand,
          'category': row.category,
        };
        if (existing.docs.isNotEmpty) {
          batch.update(existing.docs.first.reference, data);
          updated++;
        } else {
          batch.set(machines.doc(), data);
          created++;
        }
      }
      await batch.commit();
    }

    if (!mounted) return;
    setState(() {
      _isImporting = false;
      _resultMessage = 'Done — $created machine(s) added, $updated updated.';
      _rows = [];
      _fileName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final validCount = _rows.where((r) => r.isValid).length;
    final errorCount = _rows.length - validCount;

    return Scaffold(
      appBar: AppBar(title: const Text('Bulk Import Machines')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'CSV format: a header row, then one machine per row.\n\n'
                  'Columns needed: Equipment ID, Equipment Name, Brand, Category\n\n'
                  '"Category" must be Engineering, Production, or Warehouse. '
                  '"Brand" is optional. If a machine with a matching Equipment ID '
                  'already exists, it will be updated instead of duplicated.\n\n'
                  'Exported from Excel or Google Sheets as CSV works fine.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isImporting ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: Text(_fileName == null ? 'Choose CSV file' : 'Change file ($_fileName)'),
            ),
            if (_resultMessage != null) ...[
              const SizedBox(height: 12),
              Text(_resultMessage!, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
            if (_rows.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '$validCount ready to import' + (errorCount > 0 ? ', $errorCount with errors (fix and re-upload)' : ''),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: errorCount > 0 ? AppColors.warning : AppColors.success,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (context, index) {
                    final row = _rows[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        row.isValid ? Icons.check_circle_outline : Icons.error_outline,
                        color: row.isValid ? AppColors.success : AppColors.danger,
                      ),
                      title: Text('${row.equipmentId} — ${row.equipmentName}'),
                      subtitle: Text(row.isValid ? '${row.category}${row.brand.isNotEmpty ? ' · ${row.brand}' : ''}' : 'Line ${row.lineNumber}: ${row.error}'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: (_isImporting || validCount == 0) ? null : _import,
                  child: _isImporting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Import $validCount machine(s)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
