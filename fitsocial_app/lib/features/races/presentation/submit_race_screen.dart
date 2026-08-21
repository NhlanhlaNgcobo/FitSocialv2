import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../../../shared/widgets/quick_toast.dart';
import '../application/race_providers.dart';
import '../domain/race_formatting.dart';
import '../domain/race_models.dart';
import 'race_widgets.dart';

/// Tell us about a race that isn't listed.
///
/// Deliberately short. Five fields, only four of them required, and the
/// distances are free text. A form that demanded structured distance rows and an
/// exact venue would collect better records and far fewer of them — and a
/// moderator has to read the submission before it goes live anyway, so the
/// structure can be added by the person who is already looking at it.
class SubmitRaceScreen extends ConsumerStatefulWidget {
  const SubmitRaceScreen({super.key});

  @override
  ConsumerState<SubmitRaceScreen> createState() => _SubmitRaceScreenState();
}

class _SubmitRaceScreenState extends ConsumerState<SubmitRaceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _organiser = TextEditingController();
  final _entryUrl = TextEditingController();
  final _distances = TextEditingController();
  final _notes = TextEditingController();

  Province _province = Province.gauteng;
  DateTime? _date;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _organiser.dispose();
    _entryUrl.dispose();
    _distances.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final signedIn = ref.watch(currentUserIdProvider) != null;

    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('SUBMIT A RACE')),
        body: const RaceMessage(
          icon: Icons.lock_outline_rounded,
          title: 'Sign in to submit a race',
          body: 'Submissions are tied to an account so we can follow up on the '
              'details.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('SUBMIT A RACE')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            40,
          ),
          children: [
            Text(
              'Know a race that should be on the calendar? Send us what you '
              'know and we’ll check it before it goes live.',
              style:
                  TextStyle(fontSize: 13.5, height: 1.45, color: palette.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            _Field(
              controller: _name,
              label: 'Race name',
              hint: 'Chamberlain Country Classic',
              textCapitalization: TextCapitalization.words,
              validator: (value) => (value == null || value.trim().length < 3)
                  ? 'Give the race its name'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _DateField(
              date: _date,
              onPick: _pickDate,
              // Validated outside the TextFormField chain because a date picker
              // has no text to validate — see _submit, which checks it before
              // touching the form.
            ),
            const SizedBox(height: AppSpacing.md),
            _Field(
              controller: _city,
              label: 'Town or city',
              hint: 'Midrand',
              textCapitalization: TextCapitalization.words,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Where does it start?'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _ProvinceField(
              value: _province,
              onChanged: (province) => setState(() => _province = province),
            ),
            const SizedBox(height: AppSpacing.md),
            _Field(
              controller: _distances,
              label: 'Distances',
              hint: '5 km, 10 km and 21.1 km',
              optional: true,
            ),
            const SizedBox(height: AppSpacing.md),
            _Field(
              controller: _organiser,
              label: 'Club or organiser',
              hint: 'Midrand Striders',
              textCapitalization: TextCapitalization.words,
              optional: true,
            ),
            const SizedBox(height: AppSpacing.md),
            _Field(
              controller: _entryUrl,
              label: 'Entry link',
              hint: 'https://…',
              keyboardType: TextInputType.url,
              optional: true,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return null;
                final url = Uri.tryParse(text);
                // Checked here rather than left for a moderator because the
                // person filling this in is the one who can still fix it.
                if (url == null || !url.hasScheme || !url.hasAuthority) {
                  return 'That does not look like a full web address';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _Field(
              controller: _notes,
              label: 'Anything else',
              hint: 'Comrades qualifier, trail route, start time…',
              maxLines: 3,
              optional: true,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.brand,
                  foregroundColor: AppColors.onBrandInk,
                  disabledBackgroundColor: palette.stroke,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'SEND IT IN',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = ref.read(raceClockProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 30)),
      // No past dates: this form is for races that have not happened. A fixture
      // list going two years out is normal, so the far bound is generous.
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    // Held before the await: the screen pops itself on success.
    final overlay = Overlay.of(context, rootOverlay: true);
    final navigator = Navigator.of(context);

    if (_date == null) {
      showQuickToastOn(
        overlay,
        'Pick the race date first.',
        icon: Icons.event_rounded,
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      await ref.read(raceActionsProvider).submit(
            RaceSubmission(
              name: _name.text,
              startAt: _date!,
              city: _city.text,
              province: _province,
              organiser: _emptyToNull(_organiser.text),
              entryUrl: _emptyToNull(_entryUrl.text),
              distancesNote: _emptyToNull(_distances.text),
              notes: _emptyToNull(_notes.text),
            ),
          );
      if (!mounted) return;
      showQuickToastOn(
        overlay,
        'Thanks — we’ll check it and add it to the calendar.',
        tone: ToastTone.success,
        visibleFor: const Duration(milliseconds: 2600),
      );
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      debugPrint('Submitting a race failed: $error');
      showQuickToastOn(
        overlay,
        "Couldn't send that. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
    this.maxLines = 1,
    this.optional = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RaceLabel(label.toUpperCase()),
            if (optional) ...[
              const SizedBox(width: 6),
              Text(
                'optional',
                style: TextStyle(fontSize: 10.5, color: palette.muted),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          maxLines: maxLines,
          style: TextStyle(fontSize: 14, color: palette.text),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: palette.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: _border(palette.stroke),
            enabledBorder: _border(palette.stroke),
            focusedBorder: _border(palette.brand),
            errorBorder: _border(palette.danger),
            focusedErrorBorder: _border(palette.danger),
          ),
        ),
      ],
    );
  }

  static OutlineInputBorder _border(Color colour) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colour),
      );
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onPick});

  final DateTime? date;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final picked = date;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RaceLabel('RACE DATE'),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onPick,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.stroke),
            ),
            child: Row(
              children: [
                Icon(Icons.event_rounded, size: 17, color: palette.muted),
                const SizedBox(width: 10),
                Text(
                  picked == null ? 'Pick a date' : RaceFormat.date(picked),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        picked == null ? FontWeight.w400 : FontWeight.w600,
                    color: picked == null ? palette.muted : palette.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProvinceField extends StatelessWidget {
  const _ProvinceField({required this.value, required this.onChanged});

  final Province value;
  final ValueChanged<Province> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RaceLabel('PROVINCE'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.stroke),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Province>(
              value: value,
              isExpanded: true,
              dropdownColor: palette.surface,
              style: TextStyle(fontSize: 14, color: palette.text),
              items: [
                for (final province in Province.values)
                  DropdownMenuItem(
                    value: province,
                    child: Text(province.label),
                  ),
              ],
              onChanged: (province) {
                if (province != null) onChanged(province);
              },
            ),
          ),
        ),
      ],
    );
  }
}
