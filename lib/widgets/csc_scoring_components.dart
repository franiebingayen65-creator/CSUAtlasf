import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


class CSCScoringStyles {
  static const headerStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black);
  static const subHeaderStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black);
  static const labelStyle = TextStyle(fontSize: 11, color: Colors.black87);
  static const cellStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w600);
  static const inputStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold);

}
class MaxDecimalFormatter extends TextInputFormatter {
  final double max;
  final int decimals;
  MaxDecimalFormatter(this.max, {this.decimals = 1});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = newValue.text;
    if (t.isEmpty) return newValue;
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(t)) return oldValue;
    if (decimals == 0 && t.contains('.')) return oldValue;
    final parts = t.split('.');
    if (parts.length == 2 && parts[1].length > decimals) return oldValue;

    // Make "5." and ".5" parse safely
    var safe = t;
    if (safe.endsWith('.')) safe = '${safe}0';
    if (safe.startsWith('.')) safe = '0$safe';
    final v = double.tryParse(safe);
    if (v != null && v > max + 1e-9) return oldValue;
    return newValue;
  }
}
// ==========================================
// OFFICIAL RUBRIC CALCULATION LOGIC
// ==========================================

double calculateSDGPoints(String level, int sdgCount, [String? orgType]) {
  if (sdgCount <= 0) return 0;
  final t = (orgType ?? '').toLowerCase();
  final isCampus = t.contains('campus');
  final isSpecialized = t.contains('specialized') || t.contains('special');

  if (isSpecialized) {
    switch (level) {
      case 'intl':
        if (sdgCount >= 3) return 5.5;
        if (sdgCount == 2) return 5.0;
        return 4.5;
      case 'natl':
        if (sdgCount >= 3) return 5.0;
        if (sdgCount == 2) return 4.5;
        return 4.0;
      case 'regl':
        if (sdgCount >= 5) return 4.5;
        if (sdgCount == 4) return 4.0;
        if (sdgCount == 3) return 3.5;
        return 0;
      case 'univ':
        if (sdgCount >= 5) return 4.0;
        if (sdgCount == 4) return 3.5;
        if (sdgCount == 3) return 3.0;
        return 0;
      case 'camp':
        if (sdgCount >= 7) return 3.5;
        if (sdgCount == 6) return 3.0;
        if (sdgCount == 5) return 2.5;
        return 0;
      case 'coll':
        if (sdgCount >= 10) return 3.0;
        if (sdgCount == 9) return 2.5;
        if (sdgCount == 8) return 2.0;
        return 0;
      default:
        return 0;
    }
  } else if (isCampus) {
    switch (level) {
      case 'intl':
        if (sdgCount >= 3) return 1.5;
        if (sdgCount == 2) return 1.0;
        return 0.5;
      case 'natl':
        if (sdgCount >= 5) return 2.5;
        if (sdgCount == 4) return 2.0;
        if (sdgCount == 3) return 1.5;
        if (sdgCount == 2) return 1.0;
        if (sdgCount == 1) return 0.5;
        return 0;
      case 'regl':
        if (sdgCount >= 5) return 2.0;
        if (sdgCount == 4) return 1.5;
        if (sdgCount == 3) return 1.0;
        return 0;
      case 'univ':
        if (sdgCount >= 5) return 1.5;
        if (sdgCount == 4) return 1.0;
        if (sdgCount == 3) return 0.5;
        return 0;
      case 'camp':
        if (sdgCount >= 7) return 2.5;
        if (sdgCount == 6) return 2.0;
        if (sdgCount == 5) return 1.5;
        return 0;
      default:
        return 0;
    }
  } else {
    switch (level) {
      case 'intl':
      case 'natl':
        if (sdgCount >= 3) return 2.5;
        if (sdgCount == 2) return 2.0;
        return 1.5;
      case 'regl':
        if (sdgCount >= 5) return 2.5;
        if (sdgCount == 4) return 2.0;
        if (sdgCount == 3) return 1.5;
        return 0;
      case 'univ':
        if (sdgCount >= 5) return 2.0;
        if (sdgCount == 4) return 1.5;
        if (sdgCount == 3) return 1.0;
        return 0;
      case 'camp':
        if (sdgCount >= 5) return 1.5;
        if (sdgCount == 4) return 1.0;
        if (sdgCount == 3) return 0.5;
        return 0;
      case 'coll':
        if (sdgCount >= 7) return 2.5;
        if (sdgCount == 6) return 2.0;
        if (sdgCount >= 5) return 1.5;
        return 0;
      default:
        return 0;
    }
  }
}

double getCategoricalLevelUnitPoints(String level, [String? orgType]) {
  final t = (orgType ?? '').toLowerCase();
  final isCampus = t.contains('campus');
  final isSpecialized = t.contains('specialized') || t.contains('special');

  if (isSpecialized) {
    switch (level) {
      case 'intl': return 3.5;
      case 'natl': return 3.0;
      case 'regl': return 2.5;
      case 'univ': return 2.0;
      case 'camp': return 1.5;
      case 'coll': return 1.0;
      default: return 0;
    }
  } else if (isCampus) {
    switch (level) {
      case 'intl': return 3.0;
      case 'natl': return 2.5;
      case 'regl': return 2.0;
      case 'univ': return 1.5;
      case 'camp': return 1.0;
      default: return 0;
    }
  } else {
    switch (level) {
      case 'intl': return 3.5;
      case 'natl': return 3.0;
      case 'regl': return 2.5;
      case 'univ': return 2.0;
      case 'camp': return 1.5;
      case 'coll': return 1.0;
      default: return 0;
    }
  }
}

double calculateTangibleScore(double amount, [String? orgType]) {
  final isSpecialized = (orgType ?? '').toLowerCase().contains('special');
  if (amount <= 0) return 0;
  if (isSpecialized) {
    if (amount <= 2000) return 1.0;
    if (amount <= 3000) return 1.5;
    if (amount <= 4000) return 2.0;
    if (amount <= 5000) return 2.5;
    if (amount <= 6000) return 3.0;
    if (amount <= 7000) return 3.5;
    if (amount <= 8000) return 4.0;
    if (amount <= 9000) return 4.5;
    if (amount <= 10000) return 5.0;
    if (amount <= 11000) return 5.5;
    if (amount <= 12000) return 6.0;
    if (amount <= 13000) return 6.5;
    if (amount <= 14000) return 7.0;
    if (amount <= 15000) return 7.5;
    if (amount <= 16000) return 8.0;
    if (amount <= 17000) return 8.5;
    if (amount <= 18000) return 9.0;
    if (amount <= 19000) return 9.5;
    return 10.0;
  } else {
    if (amount <= 25000) return 1.0;
    if (amount <= 30000) return 2.0;
    if (amount <= 35000) return 3.0;
    if (amount <= 40000) return 4.0;
    if (amount <= 45000) return 5.0;
    if (amount <= 50000) return 6.0;
    if (amount <= 55000) return 7.0;
    if (amount <= 60000) return 8.0;
    if (amount <= 65000) return 9.0;
    if (amount <= 70000) return 10.0;
    if (amount <= 75000) return 11.0;
    if (amount <= 80000) return 12.0;
    if (amount <= 85000) return 13.0;
    if (amount <= 90000) return 14.0;
    return 15.0;
  }
}

double calculateFundDriveScore(double amount, [String? orgType]) {
  final t = (orgType ?? '').toLowerCase();
  final isCampus = t.contains('campus');
  final isSpecialized = t.contains('special');

  if (amount <= 0) return 0;
  if (isSpecialized) {
    if (amount <= 2000) return 1.0;
    if (amount <= 3000) return 1.5;
    if (amount <= 4000) return 2.0;
    if (amount <= 5000) return 2.5;
    if (amount <= 6000) return 3.0;
    if (amount <= 7000) return 3.5;
    if (amount <= 8000) return 4.0;
    if (amount <= 9000) return 4.5;
    if (amount <= 10000) return 5.0;
    if (amount <= 11000) return 5.5;
    if (amount <= 12000) return 6.0;
    if (amount <= 13000) return 6.5;
    if (amount <= 14000) return 7.0;
    if (amount <= 15000) return 7.5;
    if (amount <= 16000) return 8.0;
    if (amount <= 17000) return 8.5;
    if (amount <= 18000) return 9.0;
    if (amount <= 19000) return 9.5;
    return 10.0;
  } else if (isCampus) {
    if (amount < 4001) return 0;
    if (amount <= 5000) return 1.0;
    if (amount <= 10000) return 1.5;
    if (amount <= 15000) return 2.0;
    if (amount <= 20000) return 2.5;
    if (amount <= 25000) return 3.0;
    if (amount <= 30000) return 3.5;
    if (amount <= 35000) return 4.0;
    if (amount <= 40000) return 4.5;
    if (amount <= 45000) return 5.0;
    if (amount <= 50000) return 5.5;
    if (amount <= 55000) return 6.0;
    if (amount <= 60000) return 6.5;
    if (amount <= 65000) return 7.0;
    if (amount <= 70000) return 7.5;
    if (amount <= 75000) return 8.0;
    if (amount <= 80000) return 8.5;
    if (amount <= 85000) return 9.0;
    if (amount <= 90000) return 9.5;
    return 10.0;
  } else {
    if (amount < 4001) return 0;
    if (amount <= 5000) return 1.0;
    if (amount <= 10000) return 2.0;
    if (amount <= 15000) return 3.0;
    if (amount <= 20000) return 4.0;
    if (amount <= 25000) return 5.0;
    if (amount <= 30000) return 6.0;
    if (amount <= 35000) return 7.0;
    if (amount <= 40000) return 8.0;
    if (amount <= 45000) return 9.0;
    return 10.0;
  }
}

double calculateFinancialAssistanceScore(double amount, [String? orgType]) {
  final isCampus = orgType != null && orgType.toLowerCase().contains('campus');
  if (amount <= 0) return 0;
  if (isCampus) {
    if (amount < 4001) return 0;
    if (amount <= 5000) return 1.0;
    if (amount <= 10000) return 1.5;
    if (amount <= 15000) return 2.0;
    if (amount <= 20000) return 2.5;
    if (amount <= 25000) return 3.0;
    if (amount <= 30000) return 3.5;
    if (amount <= 35000) return 4.0;
    if (amount <= 40000) return 4.5;
    if (amount <= 45000) return 5.0;
    if (amount <= 50000) return 5.5;
    if (amount <= 55000) return 6.0;
    if (amount <= 60000) return 6.5;
    if (amount <= 65000) return 7.0;
    if (amount <= 70000) return 7.5;
    if (amount <= 75000) return 8.0;
    if (amount <= 80000) return 8.5;
    if (amount <= 85000) return 9.0;
    if (amount <= 90000) return 9.5;
    return 10.0;
  } else {
    if (amount < 4001) return 0;
    if (amount <= 5000) return 1.0;
    if (amount <= 10000) return 2.0;
    if (amount <= 15000) return 3.0;
    if (amount <= 20000) return 4.0;
    if (amount <= 25000) return 5.0;
    if (amount <= 30000) return 6.0;
    if (amount <= 35000) return 7.0;
    if (amount <= 40000) return 8.0;
    if (amount <= 45000) return 9.0;
    return 10.0;
  }
}

double calculateImplementationScore(double percent) {
  if (percent < 40) return 0;
  if (percent < 46) return 1.0;
  if (percent < 52) return 2.0;
  if (percent < 58) return 3.0;
  if (percent < 64) return 4.0;
  if (percent < 70) return 5.0;
  if (percent < 76) return 6.0;
  if (percent < 82) return 7.0;
  if (percent < 88) return 8.0;
  if (percent < 94) return 9.0;
  return 10.0;
}

String getAdjectivalRating(double totalScore) {
  if (totalScore >= 96) return 'Outstanding';
  if (totalScore >= 86) return 'Very Satisfactory';
  if (totalScore >= 76) return 'Satisfactory';
  if (totalScore >= 66) return 'Fair';
  return 'Poor';
}

// ==========================================
// INTERACTIVE LEVEL GRID CARDS
// ==========================================

class SDGMatrixGridCard extends StatelessWidget {
  final String code;
  final String title;
  final String maxPoints;
  final Map<String, TextEditingController> levelControllers;
  final TextEditingController totalController;
  final VoidCallback onCalculated;
  final String orgType;

  const SDGMatrixGridCard({
    super.key,
    required this.code,
    required this.title,
    required this.maxPoints,
    required this.levelControllers,
    required this.totalController,
    required this.onCalculated,
    this.orgType = '',
  });

  @override
  Widget build(BuildContext context) {
    final levels = [
      {'key': 'intl', 'label': 'Int\'l'},
      {'key': 'natl', 'label': 'Nat\'l'},
      {'key': 'regl', 'label': 'Reg\'l'},
      {'key': 'univ', 'label': 'Univ'},
      {'key': 'camp', 'label': 'Campus'},
      if (!orgType.toLowerCase().contains('campus'))
        {'key': 'coll', 'label': 'College'},
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  code,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1), fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
              ),
              Text('Max: $maxPoints', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Insert SDGs / Points per Level Column Grid:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: levels.map((lvl) {
              final k = lvl['key']!;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Text(lvl['label']!, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: levelControllers['${k}_sdg'],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2), MaxDecimalFormatter(17, decimals: 0)],
                        onChanged: (_) => onCalculated(),
                        decoration: InputDecoration(
                          hintText: 'SDGs',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      TextField(
                        controller: levelControllers['${k}_pts'],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        inputFormatters: [MaxDecimalFormatter(calculateSDGPoints(k, 99, orgType))],
                        onChanged: (_) => onCalculated(),
                        decoration: InputDecoration(
                          hintText: 'Pts',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Item Total Score:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: totalController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: 'pts',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CategoricalGridCard extends StatelessWidget {
  final String code;
  final String title;
  final String maxPoints;
  final Map<String, TextEditingController> levelControllers;
  final TextEditingController totalController;
  final VoidCallback onCalculated;
  final String orgType;
  final int maxActivities;

  const CategoricalGridCard({
    super.key,
    required this.code,
    required this.title,
    required this.maxPoints,
    required this.levelControllers,
    required this.totalController,
    required this.onCalculated,
    this.orgType = '',
    this.maxActivities = 1,
  });
  @override
  Widget build(BuildContext context) {
    const names = {
      'intl': 'Int\'l',
      'natl': 'Nat\'l',
      'regl': 'Reg\'l',
      'univ': 'Univ',
      'camp': 'Campus',
      'coll': 'College',
    };
    final keys = orgType.toLowerCase().contains('campus')
        ? ['intl', 'natl', 'regl', 'univ', 'camp']
        : ['intl', 'natl', 'regl', 'univ', 'camp', 'coll'];
    final levels = keys.map((k) {
      final p = getCategoricalLevelUnitPoints(k, orgType);
      return {'key': k, 'label': '${names[k]}\n(${p}pt)'};
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(code, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1), fontSize: 12)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)))),
              Text('Max: $maxPoints', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Insert Points / Activities inside Level Grid Cells:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: levels.map((lvl) {
              final k = lvl['key']!;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Text(lvl['label']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: levelControllers[k],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        inputFormatters: [MaxDecimalFormatter(getCategoricalLevelUnitPoints(k, orgType) * maxActivities)],
                        onChanged: (_) => onCalculated(),
                        decoration: InputDecoration(
                          hintText: 'Pts',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Item Total Score:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: totalController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: 'pts',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CategoryCalculatorCard extends StatelessWidget {
  final String code;
  final String title;
  final String maxPoints;
  final TextEditingController controller;
  final String? hintText;
  final String? inputLabel;
  final TextEditingController? amountController;
  final ValueChanged<String>? onAmountChanged;

  const CategoryCalculatorCard({
    super.key,
    required this.code,
    required this.title,
    required this.maxPoints,
    required this.controller,
    this.hintText,
    this.inputLabel,
    this.amountController,
    this.onAmountChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  code,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1), fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
              ),
              Text('Max: $maxPoints', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 12),
          if (amountController != null) ...[
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: onAmountChanged,
              decoration: InputDecoration(
                labelText: inputLabel ?? 'Enter Amount (₱) or Percentage (%)',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(hintText ?? 'Points Scored:', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: 'pts',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
// ===== Shared form layout (used by the on-screen sheet AND the PDF) =====
const List<String> kLevelKeys = ['intl', 'natl', 'regl', 'univ', 'camp', 'coll'];

const List<String> kLevelTitles = [
  'International\nLevel',
  'National\nLevel',
  'Regional\nLevel/\nProvincial',
  'University\nWide/\nMunicipality',
  'Campus\nWide/\nBarangay',
  'College\nLevel',
];
const String kIntlNote = '(at least 3 countries)';

const Map<String, List<List<List<num>>>> kSdgTiers = {
  'spec': [
    [[3, 5.5], [2, 5], [1, 4.5]],
    [[3, 5], [2, 4.5], [1, 4]],
    [[5, 4.5], [4, 4], [3, 3.5]],
    [[5, 4], [4, 3.5], [3, 3]],
    [[7, 3.5], [6, 3], [5, 2.5]],
    [[10, 3], [9, 2.5], [8, 2]],
  ],
  'campus': [
    [[3, 1.5], [2, 1], [1, 0.5]],
    [[5, 2.5], [4, 2], [3, 1.5], [2, 1], [1, 0.5]],
    [[5, 2], [4, 1.5], [3, 1]],
    [[5, 1.5], [4, 1], [3, 0.5]],
    [[7, 2.5], [6, 2], [5, 1.5]],
  ],
  'college': [
    [[3, 2.5], [2, 2], [1, 1.5]],
    [[3, 2.5], [2, 2], [1, 1.5]],
    [[5, 2.5], [4, 2], [3, 1.5]],
    [[5, 2], [4, 1.5], [3, 1]],
    [[5, 1.5], [4, 1], [3, 0.5]],
    [[7, 2.5], [6, 2], [5, 1.5]],
  ],
};

/// 2.0 -> "2", 0.5 -> ".5", 1.5 -> "1.5" (same as the printed form)
String formatTier(num v) {
  if (v == v.truncate()) return v.toInt().toString();
  final s = v.toString();
  return s.startsWith('0.') ? s.substring(1) : s;
}

String pointsLabel(num v) => '${formatTier(v)} ${v == 1 ? 'point' : 'points'}';

/// Caps a typed/saved value at the level's maximum (e.g. Campus Int'l = 3)
double clampLevelPts(String level, double v, [String? orgType]) {
  final max = getCategoricalLevelUnitPoints(level, orgType);
  return v > max ? max : v;
}