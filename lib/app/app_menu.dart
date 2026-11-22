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
            'Choose a bill type on Home. The five tabs—Details, Households, Usage, Review, and Results—unlock as each preceding step validates. Earlier available steps can be revisited.\n\n'
            'Details — enter the amount, billing period, and hybrid total consumption. The allocation method can be changed for this bill.\n\n'
            'Households — name each household and set its 0–10 headcount with the stepper. Zero is selectable, but continuing requires 1–10 occupants per household. Clear resets households to one default household and occupant.\n\n'
            'Usage — enter optional measured usage and choose manual days, Full Period, or non-overlapping date ranges. Clear resets all usage and duration inputs while preserving household and bill details.\n\n'
            'Review — check inputs and Calculate to recompute.\n\n'
            'Results — view reconciled household and applicable occupant amounts. Revisiting inputs asks for confirmation; editing requires calculating again. Save stores the result on this device. Share remains unavailable. Exit offers Save & Exit, Exit Without Saving, or Cancel when needed.\n\n'
            'Saved bills are kept in app-private storage, one per category and assigned month. A bill belongs to the month with the most covered days; ties go to the later month. Replacing a saved bill requires confirmation. New drafts propose a period after the latest saved bill of that category. Overlapping periods show a warning, but calculation can continue.\n\n'
            'Hybrid charges measured usage, then shares remaining usage among all occupants by person-days, including metered occupants. Person-days splits by occupancy duration. Equal per household does not assign individual monetary shares.\n\n'
            'Drafts are not restored after the app closes. History, Share, ZIP Backup/Restore, and Settings are unavailable.',
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
    icon: const Icon(Icons.menu),
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
