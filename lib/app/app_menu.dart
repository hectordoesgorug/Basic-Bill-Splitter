import 'package:material_ui/material_ui.dart';

import 'app_platform.dart';

class AppMenu extends StatelessWidget {
  const AppMenu({super.key, required this.version, this.confirmExit});

  final Future<String?> version;
  final Future<bool> Function()? confirmExit;

  Future<void> _information(BuildContext context, String title, Widget body) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          scrollable: true,
          content: body,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  Future<void> _select(BuildContext context, String action) async {
    switch (action) {
      case 'about':
        await _information(
          context,
          'About Basic Bill Splitter',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Splitter'),
              FutureBuilder<String?>(
                future: version,
                builder: (context, snapshot) => Text(
                  snapshot.hasData
                      ? 'Version ${snapshot.data}'
                      : 'Version unavailable',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Basic Bill Splitter is an offline shared-bill calculator for residential expenses. Split one bill among households using measured usage, occupancy days, or equal household shares. No account is required.',
              ),
            ],
          ),
        );
      case 'howTo':
        await _information(
          context,
          'How to',
          const Text(
            'Choose a bill type on Home, then follow five steps:\n\n'
            '1. Bill Details — enter the amount, billing period, and total consumption for hybrid. You can change the allocation method for this bill.\n\n'
            '2. Households — name each household and enter its occupant headcount.\n\n'
            '3. Usage & Duration — enter optional measured usage and choose manual days, Full Period, or non-overlapping date ranges.\n\n'
            '4. Review — check the inputs and go Back to edit.\n\n'
            '5. Results — view reconciled household and applicable occupant amounts.\n\n'
            'Hybrid charges measured usage, then shares remaining usage among all occupants by person-days, including metered occupants.\n\n'
            'Person-days splits the bill by occupancy days.\n\n'
            'Equal per household splits the bill among households without assigning individual monetary shares.\n\n'
            'Drafts remain in memory only. Returning Home starts a fresh calculation after confirmation when work has been entered.',
          ),
        );
      case 'exit':
        final allowed = await confirmExit?.call() ?? true;
        if (allowed) await AppPlatform.exit();
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: const ValueKey('appMenu'),
    tooltip: 'Menu',
    onSelected: (action) => _select(context, action),
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'about', child: Text('About')),
      PopupMenuItem(value: 'howTo', child: Text('How to')),
      PopupMenuItem(enabled: false, child: Text('History — Coming soon')),
      PopupMenuItem(enabled: false, child: Text('Settings — Coming soon')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'exit', child: Text('Exit')),
    ],
  );
}
