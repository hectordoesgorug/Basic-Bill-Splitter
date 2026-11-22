import 'package:material_ui/material_ui.dart';

import '../workflow/bill_draft.dart';
import '../workflow/bill_workflow.dart';
import 'app_menu.dart';
import 'app_platform.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialDraft});

  final BillDraft? initialDraft;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late BillDraft? _draft = widget.initialDraft;
  late final Future<String?> _version = AppPlatform.version();

  Future<void> _visitRepository() async {
    final opened = await AppPlatform.openRepository();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open GitHub. Check that a browser is available.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_draft case final draft?) {
      return BillWorkflow(
        draft: draft,
        version: _version,
        onHome: () => setState(() => _draft = null),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Splitter'),
        actions: [AppMenu(version: _version)],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/banner.png',
                        key: const ValueKey('homeBanner'),
                        semanticLabel: 'Basic Bill Splitter — Simple, exact shared-bill calculation',
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Choose a bill type',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, grid) {
                        final columns =
                            grid.maxWidth >= 360 &&
                                MediaQuery.textScalerOf(context).scale(16) <= 24
                            ? 2
                            : 1;
                        final width =
                            (grid.maxWidth - 12 * (columns - 1)) / columns;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final category in BillCategory.values)
                              SizedBox(
                                width: width,
                                child: FilledButton.tonal(
                                  key: ValueKey('billType-${category.name}'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 22,
                                    ),
                                    alignment: Alignment.centerLeft,
                                  ),
                                  onPressed: () => setState(() {
                                    _draft = BillDraft()
                                      ..selectCategory(category);
                                  }),
                                  child: Text(
                                    category == BillCategory.miscellaneous
                                        ? 'Misc'
                                        : category.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    TextButton.icon(
                      key: const ValueKey('visitGitHub'),
                      onPressed: _visitRepository,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Visit GitHub'),
                    ),
                    FutureBuilder<String?>(
                      future: _version,
                      builder: (context, snapshot) => Text(
                        snapshot.hasData
                            ? 'Version ${snapshot.data}'
                            : snapshot.connectionState == ConnectionState.done
                            ? 'Version unavailable'
                            : 'Loading version…',
                        key: const ValueKey('appVersion'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
