import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../storage/bill_repository.dart';
import '../storage/saved_bill_record.dart';
import 'app_platform.dart';

typedef DarkModeWriter = Future<bool> Function(bool enabled);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.hasActiveDraft,
    required this.darkMode,
    required this.onDarkModeChanged,
    required this.onDataReset,
  });

  final BillRepository repository;
  final bool hasActiveDraft;
  final bool darkMode;
  final DarkModeWriter onDarkModeChanged;
  final VoidCallback onDataReset;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _darkMode = widget.darkMode;
  bool _themeSaving = false;
  String? _operation;
  int? _savedCount;
  bool _countLoading = true;
  bool _countError = false;

  bool get _busy => _operation != null || _themeSaving;

  @override
  void initState() {
    super.initState();
    _refreshCount();
  }

  Future<void> _refreshCount() async {
    setState(() {
      _countLoading = true;
      _countError = false;
    });
    try {
      final count = (await widget.repository.allRecords()).length;
      if (!mounted) return;
      setState(() {
        _savedCount = count;
        _countLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savedCount = null;
        _countError = true;
        _countLoading = false;
      });
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeTheme(bool enabled) async {
    if (_busy) return;
    final previous = _darkMode;
    setState(() {
      _darkMode = enabled;
      _themeSaving = true;
    });
    var saved = false;
    try {
      saved = await widget.onDarkModeChanged(enabled);
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    setState(() {
      _themeSaving = false;
      if (!saved) _darkMode = previous;
    });
    if (!saved) _message('Dark Mode preference could not be saved.');
  }

  Future<void> _backup() async {
    if (_busy) return;
    setState(() => _operation = 'backup');
    try {
      final records =
          (await widget.repository.allRecords())
              .map((record) => SavedBillRecord.decode(record.encode()))
              .toList()
            ..sort((a, b) {
              final category = a.category.compareTo(b.category);
              if (category != 0) return category;
              final year = a.assignedYear.compareTo(b.assignedYear);
              if (year != 0) return year;
              final month = a.assignedMonth.compareTo(b.assignedMonth);
              return month != 0 ? month : a.id.compareTo(b.id);
            });
      _validateRecordSet(records);
      if (records.length > 5000) {
        throw const FormatException('Backup contains too many records');
      }
      final encodedRecords = records.map((record) => record.encode()).toList();
      if (utf8.encode(jsonEncode(encodedRecords)).length > 32 * 1024 * 1024) {
        throw const FormatException('Backup data exceeds the supported size');
      }
      final created = DateTime.now();
      final filename =
          'Splitter-Backup-'
          '${created.year.toString().padLeft(4, '0')}-'
          '${created.month.toString().padLeft(2, '0')}-'
          '${created.day.toString().padLeft(2, '0')}_'
          '${created.hour.toString().padLeft(2, '0')}-'
          '${created.minute.toString().padLeft(2, '0')}.zip';
      final saved = await AppPlatform.createBackup(
        records: encodedRecords,
        filename: filename,
      );
      if (!mounted) return;
      if (saved) _message('Backup exported successfully.');
    } catch (_) {
      _message('Backup could not be created. Saved bills were not changed.');
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _operation = 'restore');
    try {
      final incoming = await AppPlatform.pickBackup();
      if (!mounted || incoming == null) return;
      if (incoming.length > 5000) {
        throw const FormatException('Backup contains too many records');
      }
      final records = incoming
          .map(SavedBillRecord.decode)
          .toList(growable: false);
      _validateRecordSet(records);
      final existing = await widget.repository.allRecords();
      if (!mounted) return;
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Replace saved bills?'),
              content: Text(
                'This backup contains ${records.length} saved bills. Restoring it will replace all ${existing.length} bills currently saved on this device.\n\n'
                'Existing saved bills not included in the backup will be permanently removed.\n\n'
                'This action cannot be undone.'
                '${widget.hasActiveDraft ? '\n\nThe active calculation will also be discarded after a successful restore.' : ''}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Restore'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;

      final written = await widget.repository.replaceAll(records);
      if (!_sameRecordSets(records, written)) {
        throw StateError('Restored records did not match the validated backup');
      }
      if (!mounted) return;
      setState(() {
        _savedCount = written.length;
        _countLoading = false;
        _countError = false;
      });
      widget.onDataReset();
      _message('Saved bills restored successfully.');
      Navigator.of(context).pop();
    } catch (_) {
      _message(
        'Backup could not be restored. Existing saved bills were preserved.',
      );
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _clearCurrentCalculation() async {
    if (_busy || !widget.hasActiveDraft) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear current calculation?'),
            content: const Text(
              'This will discard the current bill details, households, usage, and calculation results.\n\nPreviously saved bills will not be affected.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear All'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    widget.onDataReset();
    _message('Current calculation cleared. Saved bills were not changed.');
    Navigator.of(context).pop();
  }

  Future<void> _wipeSavedBills() async {
    if (_busy) return;
    setState(() => _operation = 'wipe');
    try {
      final existing = await widget.repository.allRecords();
      if (!mounted) return;
      if (existing.isEmpty) {
        setState(() {
          _savedCount = 0;
          _countLoading = false;
          _countError = false;
        });
        _message('There are no saved bills to delete.');
        return;
      }
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Permanently delete saved bills?'),
              content: Text(
                'This will permanently delete all ${existing.length} saved bills from this device.\n\n'
                'History will become empty, and the deleted records cannot be recovered unless you have a separate backup.\n\n'
                'This action cannot be undone.'
                '${widget.hasActiveDraft ? '\n\nThe current calculation will also be discarded after the saved bills are deleted.' : ''}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Wipe Data'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;

      await widget.repository.deleteAll();
      if (!mounted) return;
      setState(() {
        _savedCount = 0;
        _countLoading = false;
        _countError = false;
      });
      widget.onDataReset();
      _message('Saved bills deleted.');
      Navigator.of(context).pop();
    } catch (_) {
      _message('Saved bills could not be deleted. No success was reported.');
      await _refreshCount();
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  static void _validateRecordSet(List<SavedBillRecord> records) {
    final ids = <String>{};
    final keys = <String>{};
    for (final record in records) {
      if (!ids.add(record.id) || !keys.add(record.uniqueKey)) {
        throw const FormatException('Backup contains duplicate records');
      }
    }
  }

  static bool _sameRecordSets(
    List<SavedBillRecord> expected,
    List<SavedBillRecord> actual,
  ) {
    if (expected.length != actual.length) return false;
    final byId = {for (final item in expected) item.id: item};
    if (byId.length != expected.length) return false;
    for (final item in actual) {
      final original = byId[item.id];
      if (original == null ||
          original.uniqueKey != item.uniqueKey ||
          _canonical(original.toJson()) != _canonical(item.toJson())) {
        return false;
      }
    }
    return true;
  }

  static String _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return jsonEncode({
        for (final key in keys) key: jsonDecode(_canonical(value[key])),
      });
    }
    if (value is List) {
      return jsonEncode(
        value.map((item) => jsonDecode(_canonical(item))).toList(),
      );
    }
    return jsonEncode(value);
  }

  Widget _operationTrailing(String name) {
    if (_operation == name) {
      return const SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return const Icon(Icons.chevron_right);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'DATA MANAGEMENT',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey('settingsBackup'),
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Backup'),
            subtitle: const Text('Export saved bills to a ZIP file'),
            trailing: _operationTrailing('backup'),
            enabled: !_busy,
            onTap: _backup,
          ),
          ListTile(
            key: const ValueKey('settingsRestore'),
            leading: const Icon(Icons.unarchive_outlined),
            title: const Text('Restore'),
            subtitle: const Text('Replace saved bills from a ZIP backup'),
            trailing: _operationTrailing('restore'),
            enabled: !_busy,
            onTap: _restore,
          ),
          ListTile(
            key: const ValueKey('settingsClearAll'),
            leading: Icon(
              Icons.cleaning_services_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Clear All'),
            subtitle: const Text('Clear the current calculation'),
            trailing: _operationTrailing('clear'),
            enabled: !_busy && widget.hasActiveDraft,
            onTap: _clearCurrentCalculation,
          ),
          ListTile(
            key: const ValueKey('settingsWipeData'),
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Wipe Data'),
            subtitle: Text(
              _countLoading
                  ? 'Checking saved bills…'
                  : _countError
                  ? 'Saved bill count is unavailable'
                  : (_savedCount ?? 0) == 0
                  ? 'No saved bills to delete'
                  : 'Permanently delete all ${_savedCount ?? 0} saved bills',
            ),
            trailing: _operationTrailing('wipe'),
            enabled:
                !_busy &&
                !_countLoading &&
                !_countError &&
                (_savedCount ?? 0) > 0,
            onTap: _wipeSavedBills,
          ),
          const SizedBox(height: 4),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'ZIP backups are not encrypted. Store exported files securely. Backups are saved only to a destination you choose in Android’s document picker.',
              ),
            ),
          ),
          const Divider(height: 32),
          Text('APPEARANCE', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            key: const ValueKey('settingsDarkMode'),
            title: const Text('Dark Mode'),
            value: _darkMode,
            onChanged: _busy ? null : _changeTheme,
          ),
          if (_countError)
            TextButton.icon(
              key: const ValueKey('settingsRetryCount'),
              onPressed: _busy ? null : _refreshCount,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry saved bill count'),
            ),
        ],
      ),
    ),
  );
}
