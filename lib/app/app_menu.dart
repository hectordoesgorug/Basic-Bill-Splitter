import 'package:material_ui/material_ui.dart';

import '../history/bill_history_screen.dart';
import '../storage/bill_repository.dart';
import 'settings_screen.dart';
import '../workflow/bill_draft.dart';
import 'app_platform.dart';

class AppMenu extends StatelessWidget {
  const AppMenu({
    super.key,
    required this.version,
    required this.repository,
    this.confirmExit,
    this.darkMode = false,
    this.onDarkModeChanged,
    this.currencyCode = 'PHP',
    this.onCurrencyChanged,
    this.hasActiveDraft = false,
    this.onDataReset,
  });

  final Future<String?> version;
  final BillRepository repository;
  final Future<bool> Function()? confirmExit;
  final bool darkMode;
  final Future<bool> Function(bool enabled)? onDarkModeChanged;
  final String currencyCode;
  final Future<bool> Function(String code)? onCurrencyChanged;
  final bool hasActiveDraft;
  final VoidCallback? onDataReset;

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

  Widget _howToStep(String number, String title, String detail) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(radius: 14, child: Text(number)),
        const SizedBox(width: 12),
        Expanded(child: Text('$title — $detail')),
      ],
    ),
  );

  Future<void> _history(BuildContext context) async {
    final category = await showDialog<BillCategory>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bill history'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in BillCategory.values)
                ListTile(
                  key: ValueKey('historyCategory-${item.name}'),
                  leading: Icon(switch (item) {
                    BillCategory.electricity => Icons.bolt,
                    BillCategory.water => Icons.water_drop,
                    BillCategory.internet => Icons.wifi,
                    BillCategory.rent => Icons.home,
                    BillCategory.lpg => Icons.local_fire_department,
                    BillCategory.miscellaneous => Icons.more_horiz,
                  }),
                  title: Text(item.label),
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (category == null || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            BillHistoryScreen(repository: repository, category: category),
      ),
    );
  }

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _howToStep(
                '1',
                'Choose a bill type',
                'Select one of the six categories on Home.',
              ),
              _howToStep(
                '2',
                'Enter bill details',
                'Add the amount and billing dates. Enter total consumption when Hybrid requires it.',
              ),
              _howToStep(
                '3',
                'Add households',
                'Name each household and set 1–10 occupants. Zero is selectable but cannot pass validation.',
              ),
              _howToStep(
                '4',
                'Enter usage and duration',
                'Add measured usage where applicable, then choose Full Period, manual days, or date ranges.',
              ),
              _howToStep(
                '5',
                'Review and calculate',
                'Check the inputs and calculate household and applicable occupant shares.',
              ),
              _howToStep(
                '6',
                'Save or share',
                'Save stores the result on this device. Share creates a PNG without saving.',
              ),
              const Text(
                'Hybrid shares remaining usage by person-days across all occupants, including those with measured usage. Person-days follows occupancy duration. Equal per household does not assign occupant amounts.',
              ),
              const Divider(height: 28),
              Text(
                'History and Settings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'History shows saved bills by category and year. Settings provides Backup, Restore, Clear All, Wipe Data, Dark Mode, and Currency. Clear All removes only the current draft. Wipe Data permanently deletes saved bills. Restore replaces the saved dataset. ZIP backups are not encrypted.',
              ),
            ],
          ),
        );
      case 'history':
        await _history(context);
      case 'settings':
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(
              repository: repository,
              hasActiveDraft: hasActiveDraft,
              darkMode: darkMode,
              onDarkModeChanged: onDarkModeChanged ?? (_) async => false,
              currencyCode: currencyCode,
              onCurrencyChanged: onCurrencyChanged ?? (_) async => false,
              onDataReset: onDataReset ?? () {},
            ),
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
      PopupMenuItem(value: 'history', child: Text('History')),
      PopupMenuItem(value: 'settings', child: Text('Settings')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'exit', child: Text('Exit')),
    ],
  );
}
