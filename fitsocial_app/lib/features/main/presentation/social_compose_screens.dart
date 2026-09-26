import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/keyboard_safe_bottom_bar.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/activity_actions.dart';
import '../domain/app_models.dart';

/// The two composers for posts that ask something: a poll, and a session to
/// join. Deliberately short forms — the whole point is that asking the feed a
/// question costs less than a workout log.

/// "Ask the feed": a question and two to four answers.
class PollComposeScreen extends ConsumerStatefulWidget {
  const PollComposeScreen({super.key});

  @override
  ConsumerState<PollComposeScreen> createState() => _PollComposeScreenState();
}

class _PollComposeScreenState extends ConsumerState<PollComposeScreen> {
  final _question = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _saving = false;

  @override
  void dispose() {
    _question.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  List<String> get _filledOptions => _options
      .map((option) => option.text.trim())
      .where((option) => option.isNotEmpty)
      .toList();

  bool get _canPost =>
      _question.text.trim().isNotEmpty &&
      _filledOptions.length >= PostPoll.minOptions;

  Future<void> _post() async {
    if (!_canPost || _saving) return;
    setState(() => _saving = true);
    try {
      final result = await ref.read(activityActionsProvider).createPoll(
            PollDraft(question: _question.text, options: _filledOptions),
          );
      if (!mounted) return;
      showQuickToast(context, result.message, tone: ToastTone.success);
      context.go('/home');
    } catch (error) {
      debugPrint('Posting a poll failed: $error');
      if (mounted) {
        showQuickToast(
          context,
          "Couldn't post that poll. Try again.",
          icon: Icons.error_outline_rounded,
          tone: ToastTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Ask the Feed')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _FormPane(
            children: [
              const _FieldLabel('Question'),
              TextField(
                controller: _question,
                autofocus: true,
                maxLength: PostPoll.maxQuestionLength,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration(
                  context,
                  'e.g. Legs or back tomorrow?',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              const _FieldLabel('Answers'),
              for (var i = 0; i < _options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _options[i],
                          maxLength: PostPoll.maxOptionLength,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: _decoration(
                            context,
                            'Answer ${i + 1}',
                          ).copyWith(counterText: ''),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (_options.length > PostPoll.minOptions)
                        IconButton(
                          tooltip: 'Remove answer',
                          onPressed: () => setState(() {
                            _options.removeAt(i).dispose();
                          }),
                          icon: Icon(
                            Icons.remove_circle_outline_rounded,
                            color: palette.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              if (_options.length < PostPoll.maxOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _options.add(TextEditingController()),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add an answer'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "People see the results once they've voted. You see them "
            'from the start.',
            style: TextStyle(color: palette.muted, fontSize: 12.5),
          ),
        ],
      ),
      bottomNavigationBar: KeyboardSafeBottomBar(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: PrimaryButton(
            label: _saving ? 'Posting...' : 'Post poll',
            icon: _saving ? null : Icons.poll_rounded,
            onPressed: _canPost && !_saving ? _post : null,
          ),
        ),
      ),
    );
  }
}

/// "Plan a session": what, when, where, and an optional note.
class MeetupComposeScreen extends ConsumerStatefulWidget {
  const MeetupComposeScreen({super.key});

  @override
  ConsumerState<MeetupComposeScreen> createState() =>
      _MeetupComposeScreenState();
}

class _MeetupComposeScreenState extends ConsumerState<MeetupComposeScreen> {
  final _title = TextEditingController();
  final _place = TextEditingController();
  final _note = TextEditingController();
  late DateTime _startsAt = _defaultStart(DateTime.now());
  bool _saving = false;

  /// Tomorrow at six — when most group sessions actually happen, and never a
  /// time that has already passed.
  static DateTime _defaultStart(DateTime now) =>
      DateTime(now.year, now.month, now.day + 1, 6);

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _canPost =>
      _title.text.trim().isNotEmpty && _startsAt.isAfter(DateTime.now());

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startsAt.hour,
        _startsAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        _startsAt.year,
        _startsAt.month,
        _startsAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _post() async {
    if (!_canPost || _saving) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    try {
      final result = await ref.read(activityActionsProvider).createMeetup(
            MeetupDraft(
              title: _title.text,
              place: _place.text,
              startsAt: _startsAt,
              note: _note.text,
            ),
          );
      if (!mounted) return;
      showQuickToast(context, result.message, tone: ToastTone.success);
      context.go('/home');
    } catch (error) {
      debugPrint('Posting a meetup failed: $error');
      if (mounted) {
        showQuickToast(
          context,
          "Couldn't post that. Try again.",
          icon: Icons.error_outline_rounded,
          tone: ToastTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final inPast = !_startsAt.isAfter(DateTime.now());
    final when = PostMeetup.whenLabel(_startsAt, DateTime.now()).split(' · ');

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Plan a Session')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _FormPane(
            children: [
              const _FieldLabel('What'),
              TextField(
                controller: _title,
                autofocus: true,
                maxLength: PostMeetup.maxTitleLength,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    _decoration(context, 'e.g. Easy 8K on the beachfront'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              const _FieldLabel('When'),
              Row(
                children: [
                  Expanded(
                    child: _PickerChip(
                      icon: Icons.calendar_today_rounded,
                      label: when.first,
                      onTap: _pickDay,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _PickerChip(
                      icon: Icons.schedule_rounded,
                      label: when.last,
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
              if (inPast) ...[
                const SizedBox(height: 6),
                Text(
                  'Pick a time that hasn’t passed yet.',
                  style: TextStyle(color: palette.danger, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              const _FieldLabel('Where'),
              TextField(
                controller: _place,
                maxLength: PostMeetup.maxPlaceLength,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration(context, 'e.g. uShaka pier, Durban'),
              ),
              const SizedBox(height: AppSpacing.sm),
              const _FieldLabel('Anything else? (optional)'),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 5,
                maxLength: 280,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration(
                  context,
                  'Pace, distance, who it suits…',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Anyone who sees it can tap "I\'m in". Only share places you’re '
            'happy to meet people you don’t know yet.',
            style: TextStyle(color: palette.muted, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
      bottomNavigationBar: KeyboardSafeBottomBar(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: PrimaryButton(
            label: _saving ? 'Posting...' : 'Post invite',
            icon: _saving ? null : Icons.group_add_rounded,
            onPressed: _canPost && !_saving ? _post : null,
          ),
        ),
      ),
    );
  }
}

InputDecoration _decoration(BuildContext context, String hint) {
  final palette = context.palette;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: palette.muted),
    filled: false,
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.stroke),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.stroke),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.brand, width: 1.5),
    ),
  );
}

class _FormPane extends StatelessWidget {
  const _FormPane({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: context.palette.muted,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PickerChip extends StatelessWidget {
  const _PickerChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.stroke),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 17, color: palette.brandText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
