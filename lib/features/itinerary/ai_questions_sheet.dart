import 'package:flutter/material.dart';

const _paces = ['Relaxed', 'Balanced', 'Packed'];
const _interests = [
  'Nature',
  'Food',
  'Culture',
  'Adventure',
  'Beaches',
  'Mountains',
  'History',
  'Nightlife',
];
const _budgets = ['Low', 'Medium', 'High'];
const _stays = ['Any', 'Hotel', 'Homestay', 'Camping'];
const _foods = ['Any', 'Local', 'Veg', 'Non-veg'];

/// Detailed pre-generate questionnaire. Returns answers map, or null on cancel.
class AiQuestionsSheet extends StatefulWidget {
  final int remaining;
  const AiQuestionsSheet({super.key, required this.remaining});

  @override
  State<AiQuestionsSheet> createState() => _AiQuestionsSheetState();
}

class _AiQuestionsSheetState extends State<AiQuestionsSheet> {
  String _pace = 'Balanced';
  final _picked = <String>{};
  String _budget = 'Medium';
  String _stay = 'Any';
  String _food = 'Any';
  final _mustSee = TextEditingController();

  @override
  void dispose() {
    _mustSee.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _answers => {
        'pace': _pace.toLowerCase(),
        'interests': _picked.toList(),
        'budget': _budget.toLowerCase(),
        'stay': _stay,
        'food': _food,
        'mustSee': _mustSee.text.trim(),
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '✨ AI trip plan',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            Text(
              '${widget.remaining} of 2 free AI plans left for this trip',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            const _QLabel('Travel pace'),
            const SizedBox(height: 6),
            _SingleChips(
              options: _paces,
              selected: _pace,
              onPick: (v) => setState(() => _pace = v),
            ),
            const SizedBox(height: 12),
            const _QLabel('Interests (pick any)'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _interests
                  .map((o) => FilterChip(
                        label: Text(o),
                        selected: _picked.contains(o),
                        onSelected: (v) => setState(() =>
                            v ? _picked.add(o) : _picked.remove(o)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            const _QLabel('Budget'),
            const SizedBox(height: 6),
            _SingleChips(
              options: _budgets,
              selected: _budget,
              onPick: (v) => setState(() => _budget = v),
            ),
            const SizedBox(height: 12),
            const _QLabel('Stay preference'),
            const SizedBox(height: 6),
            _SingleChips(
              options: _stays,
              selected: _stay,
              onPick: (v) => setState(() => _stay = v),
            ),
            const SizedBox(height: 12),
            const _QLabel('Food preference'),
            const SizedBox(height: 6),
            _SingleChips(
              options: _foods,
              selected: _food,
              onPick: (v) => setState(() => _food = v),
            ),
            const SizedBox(height: 12),
            const _QLabel('Must-see stops (optional)'),
            const SizedBox(height: 6),
            TextField(
              controller: _mustSee,
              decoration: InputDecoration(
                hintText: 'e.g. Jog Falls, sunrise at Ooty',
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, <String, dynamic>{}),
                  child: const Text('Skip questions'),
                ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  onPressed: () =>
                      Navigator.pop(context, _answers),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Generate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QLabel extends StatelessWidget {
  final String text;
  const _QLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF334155),
      ),
    );
  }
}

class _SingleChips extends StatelessWidget {
  final List<String> options;
  final String selected;
  final void Function(String) onPick;
  const _SingleChips({
    required this.options,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options
          .map((o) => ChoiceChip(
                label: Text(o),
                selected: selected == o,
                onSelected: (_) => onPick(o),
              ))
          .toList(),
    );
  }
}
