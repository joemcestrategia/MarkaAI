import 'package:flutter/material.dart';

class CommissionFilterBar extends StatelessWidget {
  final int selectedMonth;
  final int selectedYear;
  final String? selectedEmployeeId;
  final List<Map<String, dynamic>> employees;
  final Function(int month, int year, String? employeeId) onFilterChanged;

  const CommissionFilterBar({
    super.key,
    required this.selectedMonth,
    required this.selectedYear,
    required this.selectedEmployeeId,
    required this.employees,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = List.generate(5, (index) => (currentYear - 2) + index);
    
    final months = [
      {'value': 1, 'label': 'Jan'},
      {'value': 2, 'label': 'Fev'},
      {'value': 3, 'label': 'Mar'},
      {'value': 4, 'label': 'Abr'},
      {'value': 5, 'label': 'Mai'},
      {'value': 6, 'label': 'Jun'},
      {'value': 7, 'label': 'Jul'},
      {'value': 8, 'label': 'Ago'},
      {'value': 9, 'label': 'Set'},
      {'value': 10, 'label': 'Out'},
      {'value': 11, 'label': 'Nov'},
      {'value': 12, 'label': 'Dez'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Calendar Chip combined Month/Year logic
            // For simplicity, we just keep the two dropdowns visually distinct but chip-like
            _buildChipDropdown<int>(
              icon: Icons.calendar_month,
              value: selectedMonth,
              items: months.map((m) {
                return DropdownMenuItem<int>(
                  value: m['value'] as int,
                  child: Text("${m['label']} $selectedYear", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                );
              }).toList(),
              onChanged: (newMonth) {
                if (newMonth != null) {
                  onFilterChanged(newMonth, selectedYear, selectedEmployeeId);
                }
              },
              isHighlighted: true, // as seen in image for the prominent filter
              displayText: "${months.firstWhere((m) => m['value'] == selectedMonth)['label']} $selectedYear", // override display for the selected month since it's combined visually
            ),
            const SizedBox(width: 8),
            _buildChipDropdown<int>(
              value: selectedYear,
              items: years.map((y) {
                return DropdownMenuItem<int>(
                  value: y,
                  child: Text(y.toString(), style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: (newYear) {
                if (newYear != null) {
                  onFilterChanged(selectedMonth, newYear, selectedEmployeeId);
                }
              },
              displayText: selectedYear.toString(),
            ),
            const SizedBox(width: 8),
            _buildChipDropdown<String?>(
              value: selectedEmployeeId,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text("Todos funcionários", style: TextStyle(fontSize: 13)),
                ),
                ...employees.map((emp) {
                  return DropdownMenuItem<String?>(
                    value: emp['id'],
                    child: Text(emp['name'], style: const TextStyle(fontSize: 13)),
                  );
                }),
              ],
              onChanged: (newEmployee) {
                onFilterChanged(selectedMonth, selectedYear, newEmployee);
              },
              displayText: selectedEmployeeId == null 
                  ? "Todos" 
                  : (employees.firstWhere((e) => e['id'] == selectedEmployeeId, orElse: () => {'name': '...'})['name'] as String).split(' ').first,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipDropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T?>> items,
    required void Function(T?) onChanged,
    required String displayText,
    IconData? icon,
    bool isHighlighted = false,
  }) {
    final bgColor = isHighlighted ? const Color(0xFF5A4FCF) : Colors.white; // roxo
    final textColor = isHighlighted ? Colors.white : const Color(0xFF5A4FCF);
    final borderColor = isHighlighted ? const Color(0xFF5A4FCF) : Colors.grey[300]!;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18), // circular outline
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          icon: const SizedBox.shrink(), // hide down arrow
          selectedItemBuilder: (BuildContext context) {
            return items.map<Widget>((DropdownMenuItem<T?> item) {
              return Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: textColor),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      displayText, 
                      style: TextStyle(
                        fontSize: 13, 
                        fontWeight: FontWeight.bold, 
                        color: textColor
                      )
                    ),
                  ],
                ),
              );
            }).toList();
          },
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
