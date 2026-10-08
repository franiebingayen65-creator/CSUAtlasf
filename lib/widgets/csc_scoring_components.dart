import 'package:flutter/material.dart';

class CSCScoringStyles {
  static const headerStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black);
  static const subHeaderStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black);
  static const labelStyle = TextStyle(fontSize: 11, color: Colors.black87);
  static const cellStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w600);
  static const inputStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold);
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
  if (percent <= 45) return 1.0;
  if (percent <= 51) return 2.0;
  if (percent <= 57) return 3.0;
  if (percent <= 63) return 4.0;
  if (percent <= 69) return 5.0;
  if (percent <= 75) return 6.0;
  if (percent <= 81) return 7.0;
  if (percent <= 87) return 8.0;
  if (percent <= 93) return 9.0;
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

  const SDGMatrixGridCard({
    super.key,
    required this.code,
    required this.title,
    required this.maxPoints,
    required this.levelControllers,
    required this.totalController,
    required this.onCalculated,
  });

  @override
  Widget build(BuildContext context) {
    final levels = [
      {'key': 'intl', 'label': 'Int\'l'},
      {'key': 'natl', 'label': 'Nat\'l'},
      {'key': 'regl', 'label': 'Reg\'l'},
      {'key': 'univ', 'label': 'Univ'},
      {'key': 'camp', 'label': 'Campus'},
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

  const CategoricalGridCard({
    super.key,
    required this.code,
    required this.title,
    required this.maxPoints,
    required this.levelControllers,
    required this.totalController,
    required this.onCalculated,
  });

  @override
  Widget build(BuildContext context) {
    final levels = [
      {'key': 'intl', 'label': 'Int\'l\n(3.5pt)'},
      {'key': 'natl', 'label': 'Nat\'l\n(3.0pt)'},
      {'key': 'regl', 'label': 'Reg\'l\n(2.5pt)'},
      {'key': 'univ', 'label': 'Univ\n(2.0pt)'},
      {'key': 'camp', 'label': 'Campus\n(1.5pt)'},
      {'key': 'coll', 'label': 'College\n(1.0pt)'},
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
