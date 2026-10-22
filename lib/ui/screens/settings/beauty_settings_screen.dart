import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../l10n/beauty_labels.dart';
import '../../../playback/beauty_control.dart';
import '../../../playback/beauty_license_store.dart';
import '../../../preference/user_preferences.dart';
import '../../widgets/settings/preference_tiles.dart';
import 'settings_app_bar.dart';

class BeautySettingsScreen extends StatelessWidget {
  const BeautySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: buildSettingsAppBar(context, Text(BeautyLabels.of(context).title)),
    body: const BeautySettingsPanel(),
  );
}

/// Used both in settings and over live playback, with D-pad capable sliders.
class BeautySettingsPanel extends StatefulWidget {
  const BeautySettingsPanel({super.key});

  @override
  State<BeautySettingsPanel> createState() => _BeautySettingsPanelState();
}

class _BeautySettingsPanelState extends State<BeautySettingsPanel> {
  final _prefs = GetIt.instance<UserPreferences>();
  final _enableFocus = FocusNode(debugLabel: 'BeautyEnable');
  Timer? _statusTimer;
  bool _licenseSaved = false;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(BeautyControl.refreshStatus());
    });
    unawaited(BeautyControl.apply(_prefs));
    unawaited(_loadLicense());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enableFocus.requestFocus();
    });
  }

  void _onChanged() => unawaited(BeautyControl.apply(_prefs));

  Future<void> _loadLicense() async {
    try {
      final license = await BeautyLicenseStore.load();
      if (mounted) setState(() => _licenseSaved = license?.configured ?? false);
    } on Exception {
      // The editor reports storage failures without exposing credential data.
    }
  }

  Future<void> _editLicense() async {
    BeautyLicense? license;
    String identifier = '';
    try {
      license = await BeautyLicenseStore.load();
      identifier = (await PackageInfo.fromPlatform()).packageName;
    } on Exception {
      // A storage retry remains available in the editor.
    }
    if (!mounted) return;
    final saved = await showDialog<BeautyLicense>(
      context: context,
      builder: (_) =>
          _BeautyLicenseDialog(license: license, identifier: identifier),
    );
    if (saved == null || !mounted) return;
    setState(() => _licenseSaved = saved.configured);
    await BeautyControl.apply(_prefs);
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _prefs.removeListener(_onChanged);
    _enableFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = BeautyLabels.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ListTile(
          leading: const Icon(Icons.vpn_key_outlined),
          title: Text(
            '${labels.licenseTitle} · ${BeautyLicenseStore.platform}',
          ),
          subtitle: Text(
            _licenseSaved ? labels.licenseSaved : labels.licenseEmpty,
          ),
          onTap: _editLicense,
        ),
        SwitchPreferenceTile(
          preference: UserPreferences.beautyEnabled,
          title: labels.enabled,
          icon: Icons.face_retouching_natural,
          focusNode: _enableFocus,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: ValueListenableBuilder<String>(
            valueListenable: BeautyControl.status,
            builder: (context, status, _) => Text(labels.status(status)),
          ),
        ),
        for (final entry in [
          (UserPreferences.beautySmoothing, labels.smoothing),
          (UserPreferences.beautyWhitening, labels.whitening),
          (UserPreferences.beautyRosiness, labels.rosiness),
          (UserPreferences.beautySharpening, labels.sharpening),
          (UserPreferences.beautyFaceThin, labels.faceThin),
          (UserPreferences.beautyEyeSize, labels.eyeSize),
        ])
          SliderPreferenceTile(
            preference: entry.$1,
            title: entry.$2,
            min: 0,
            max: 100,
            divisions: 20,
            labelOf: (value) => '$value%',
          ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(labels.description),
        ),
      ],
    );
  }
}

class _BeautyLicenseDialog extends StatefulWidget {
  const _BeautyLicenseDialog({this.license, required this.identifier});
  final BeautyLicense? license;
  final String identifier;
  @override
  State<_BeautyLicenseDialog> createState() => _BeautyLicenseDialogState();
}

class _BeautyLicenseDialogState extends State<_BeautyLicenseDialog> {
  final _form = GlobalKey<FormState>();
  late final _token = TextEditingController(text: widget.license?.token ?? '');
  late final _appId = TextEditingController(text: widget.license?.appId ?? '');
  late final _appKey = TextEditingController(
    text: widget.license?.appKey ?? '',
  );
  bool _saving = false;
  String? _error;

  Future<void> _save({bool clear = false}) async {
    if (_saving || (!clear && !(_form.currentState?.validate() ?? false)))
      return;
    final value = clear
        ? const BeautyLicense()
        : BeautyLicense(
            token: _token.text.trim(),
            appId: _appId.text.trim(),
            appKey: _appKey.text.trim(),
          );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await BeautyLicenseStore.save(value);
      if (mounted) Navigator.of(context).pop(value);
    } on Exception {
      if (mounted)
        setState(() {
          _saving = false;
          _error = BeautyLabels.of(context).licenseStorageFailed;
        });
    }
  }

  @override
  void dispose() {
    _token.dispose();
    _appId.dispose();
    _appKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = BeautyLabels.of(context);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text('${labels.licenseTitle} · ${BeautyLicenseStore.platform}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(labels.licenseHelp),
                  if (widget.identifier.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: SelectableText(
                        '${labels.appIdentifier}: ${widget.identifier}',
                      ),
                    ),
                  for (final entry in [
                    (_token, 'License Token', true),
                    (_appId, 'App ID', false),
                    (_appKey, 'App Key', true),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        controller: entry.$1,
                        obscureText: entry.$3,
                        autocorrect: false,
                        enableSuggestions: false,
                        enabled: !_saving,
                        decoration: InputDecoration(labelText: entry.$2),
                        validator: entry.$1 != _appKey
                            ? null
                            : (_) {
                                if (_token.text.trim().isNotEmpty) return null;
                                final id = _appId.text.trim(),
                                    key = _appKey.text.trim();
                                return id.isEmpty != key.isEmpty
                                    ? labels.licenseIncomplete
                                    : null;
                              },
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(clear: true),
            child: Text(labels.clear),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(labels.cancel),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(labels.save),
          ),
        ],
      ),
    );
  }
}
