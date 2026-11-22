import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../storage/bill_repository.dart';
import '../storage/billing_period.dart';
import '../workflow/bill_draft.dart';
import '../workflow/bill_workflow.dart';
import 'app_menu.dart';
import 'app_platform.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.initialDraft,
    this.repository,
    this.darkMode = false,
    this.onDarkModeChanged,
  });

  final BillDraft? initialDraft;
  final BillRepository? repository;
  final bool darkMode;
  final Future<bool> Function(bool enabled)? onDarkModeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late BillDraft? _draft = widget.initialDraft;
  late final Future<String?> _version = AppPlatform.version();
  BillRepository get _repository => widget.repository ?? AppPlatform.bills;

  void _startBill(BillCategory category) {
    final draft = BillDraft()..selectCategory(category);
    setState(() => _draft = draft);
    unawaited(_suggestContinuity(draft));
  }

  Future<void> _suggestContinuity(BillDraft draft) async {
    final originalStart = draft.periodStart;
    final originalEnd = draft.periodEnd;
    try {
      final latest = await _repository.latestForCategory(draft.category.name);
      if (!mounted ||
          !identical(_draft, draft) ||
          latest == null ||
          draft.periodStart != originalStart ||
          draft.periodEnd != originalEnd) {
        return;
      }
      final next = nextBillingPeriod(
        parseDate(latest.startDate)!,
        parseDate(latest.endDate)!,
      );
      draft
        ..periodStart = dateText(next.$1)
        ..periodEnd = dateText(next.$2);
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved bills could not be read.')),
      );
    }
  }

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
        repository: _repository,
        version: _version,
        darkMode: widget.darkMode,
        onDarkModeChanged: widget.onDarkModeChanged,
        onHome: () => setState(() => _draft = null),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: AppMenu(
          version: _version,
          repository: _repository,
          darkMode: widget.darkMode,
          onDarkModeChanged: widget.onDarkModeChanged,
          onDataReset: () => setState(() => _draft = null),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 680,
                  minHeight: constraints.maxHeight > 40
                      ? constraints.maxHeight - 40
                      : 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
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
                                    MediaQuery.textScalerOf(context)
                                            .scale(16) <=
                                        24
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
                                      key: ValueKey(
                                        'billType-${category.name}',
                                      ),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 22,
                                        ),
                                        alignment: Alignment.centerLeft,
                                      ),
                                      onPressed: () => _startBill(category),
                                      child: Row(
                                        children: [
                                          Icon(switch (category) {
                                            BillCategory.electricity =>
                                              Icons.bolt,
                                            BillCategory.water =>
                                              Icons.water_drop,
                                            BillCategory.internet => Icons.wifi,
                                            BillCategory.rent => Icons.home,
                                            BillCategory.lpg =>
                                              Icons.local_fire_department,
                                            BillCategory.miscellaneous =>
                                              Icons.more_horiz,
                                          }, size: 24),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              category ==
                                                      BillCategory.miscellaneous
                                                  ? 'Misc'
                                                  : category.label,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Column(
                        key: const ValueKey('homeFooter'),
                        children: [
                          TextButton.icon(
                            key: const ValueKey('visitGitHub'),
                            onPressed: _visitRepository,
                            icon: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Image.asset(
                                Theme.of(context).brightness == Brightness.dark
                                    ? 'assets/github-mark-white.png'
                                    : 'assets/github-mark-black.png',
                                key: const ValueKey('githubMark'),
                                width: 24,
                                height: 24,
                                excludeFromSemantics: true,
                              ),
                            ),
                            label: const Text('Visit GitHub'),
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<String?>(
                            future: _version,
                            builder: (context, snapshot) => Text(
                              snapshot.hasData
                                  ? 'Version ${snapshot.data}'
                                  : snapshot.connectionState ==
                                        ConnectionState.done
                                  ? 'Version unavailable'
                                  : 'Loading version…',
                              key: const ValueKey('appVersion'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
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
