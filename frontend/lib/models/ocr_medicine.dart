/// Modèle léger pour le matching OCR ↔ JSON medicines.
/// Compatible avec le format JSON : { "name": "...", "dosage": "...", "form": "..." }
class OcrMedicine {
  final String name;
  final String? dosage;
  final String? form;

  const OcrMedicine({
    required this.name,
    this.dosage,
    this.form,
  });

  factory OcrMedicine.fromJson(Map<String, dynamic> json) {
    return OcrMedicine(
      name: (json['name'] as String? ?? '').trim(),
      dosage: (json['dosage'] as String?)?.trim(),
      form: (json['form'] as String?)?.trim(),
    );
  }

  /// Affichage formaté pour l'UI
  String get displayDosage => dosage?.isNotEmpty == true ? dosage! : '-';
  String get displayForm   => form?.isNotEmpty   == true ? form!   : '-';

  @override
  String toString() => 'OcrMedicine(name: $name, dosage: $dosage, form: $form)';
}