import 'package:flutter/material.dart';

class CSCScoringStyles {
  static const headerStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black);
  static const subHeaderStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black);
  static const labelStyle = TextStyle(fontSize: 11, color: Colors.black87);
  static const cellStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
  static const inputStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold);
}

class ScoreTableWrapper extends StatelessWidget {
  final String title;
  final Widget child;
  const ScoreTableWrapper({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black))),
            child: Text(title, style: CSCScoringStyles.headerStyle),
          ),
          child,
        ],
      ),
    );
  }
}

class CategoryIAndIICalculator extends StatelessWidget {
  final String categoryName;
  final Function(double) onScoreChanged;
  final double currentScore;

  const CategoryIAndIICalculator({
    super.key,
    required this.categoryName,
    required this.onScoreChanged,
    required this.currentScore,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Table(
          border: TableBorder.all(color: Colors.black12),
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
            4: FlexColumnWidth(1),
            5: FlexColumnWidth(1),
            6: FlexColumnWidth(1),
          },
          children: [
            const TableRow(
              decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
              children: [
                TableCell(child: Center(child: Padding(padding: EdgeInsets.all(4), child: Text('No. of SDGs', style: CSCScoringStyles.subHeaderStyle)))),
                TableCell(child: Center(child: Padding(padding: EdgeInsets.all(4), child: Text('Int\'l', style: CSCScoringStyles.subHeaderStyle)))),
                TableCell(child: Center(child: Padding(padding: EdgeInsets.all(4), child: Text('Nat\'l', style: CSCScoringStyles.subHeaderStyle)))),
                TableCell(child: Center(child: Padding(padding: EdgeInsets.all(4), child: Text('Reg\'l', style: CSCScoringStyles.subHeaderStyle)))),
                TableCell(child: Center(child: Padding(padding: EdgeInsets.all(4), child: Text('Univ', style: CSCScoringStyles.subHeaderStyle)))),
                TableCell(child: Center(child: Padding(padding: EdgeInsets.all(4), child: Text('Camp', style: CSCScoringStyles.subHeaderStyle)))),
                TableCell(child: Center(child: Padding(padding: EdgeInsets.all(4), child: Text('Coll', style: CSCScoringStyles.subHeaderStyle)))),
              ],
            ),
            _buildMatrixRow('3 SDGs', ['2.5', '2.5', '2.5', '2.0', '1.5', '2.5']),
            _buildMatrixRow('2 SDGs', ['2.0', '2.0', '2.0', '1.5', '1.0', '2.0']),
            _buildMatrixRow('1 SDG', ['1.5', '1.5', '1.5', '1.0', '0.5', '1.5']),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Calculated Points for Category: ', style: CSCScoringStyles.labelStyle),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: TextEditingController(text: currentScore.toString()),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => onScoreChanged(double.tryParse(v) ?? 0),
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  TableRow _buildMatrixRow(String label, List<String> pts) {
    return TableRow(
      children: [
        TableCell(child: Padding(padding: const EdgeInsets.all(8), child: Text(label, style: CSCScoringStyles.labelStyle))),
        ...pts.map((p) => TableCell(child: Center(child: Padding(padding: const EdgeInsets.all(8), child: Text(p, style: CSCScoringStyles.cellStyle))))),
      ],
    );
  }
}
