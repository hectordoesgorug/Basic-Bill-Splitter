import 'package:material_ui/material_ui.dart';

/// A named grouping whose accent is assigned by draft household identity.
class HouseholdSection extends StatelessWidget {
  const HouseholdSection({
    super.key,
    required this.name,
    required this.accent,
    required this.children,
    this.action,
  });

  final String name;
  final Color accent;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: accent, width: 2),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}
