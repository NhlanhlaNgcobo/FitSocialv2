import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/primary_button.dart';
import '../domain/routine.dart';

/// The frame every routine sheet sits in: glass, a grabber, a title.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        12 + keyboard + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: LiquidGlass(
        lens: true,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.stroke),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.stroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> _showSheet<T>(BuildContext context, Widget sheet) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (_) => sheet,
  );
}

/// Asks for a line of text — a routine name, a folder name. Null when
/// dismissed or left blank.
Future<String?> showRoutineTextPrompt(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
  String action = 'Save',
}) {
  return _showSheet<String>(
    context,
    _TextPromptSheet(
      title: title,
      hint: hint,
      initial: initial,
      action: action,
    ),
  );
}

class _TextPromptSheet extends StatefulWidget {
  const _TextPromptSheet({
    required this.title,
    required this.hint,
    required this.initial,
    required this.action,
  });

  final String title;
  final String hint;
  final String initial;
  final String action;

  @override
  State<_TextPromptSheet> createState() => _TextPromptSheetState();
}

class _TextPromptSheetState extends State<_TextPromptSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    Navigator.of(context).pop(text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _SheetFrame(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassWell(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                color: palette.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: TextStyle(color: palette.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(label: widget.action, onPressed: _submit),
        ],
      ),
    );
  }
}

/// What picking a folder returned: [folder] null is "My routines".
class FolderChoice {
  const FolderChoice(this.folder);

  final String? folder;
}

/// Picks a folder from those in use, "My routines", or a new one typed in.
/// Null when dismissed.
Future<FolderChoice?> showRoutineFolderPicker(
  BuildContext context, {
  required List<String> folders,
  String? current,
}) {
  return _showSheet<FolderChoice>(
    context,
    _FolderPickerSheet(folders: folders, current: current),
  );
}

class _FolderPickerSheet extends StatelessWidget {
  const _FolderPickerSheet({required this.folders, required this.current});

  final List<String> folders;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final named = [
      for (final f in folders)
        if (f != Routine.defaultFolder) f,
    ];

    Widget row(String label, String? value, {IconData? icon}) {
      final selected = value == current;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          icon ?? Icons.folder_outlined,
          color: selected ? palette.brand : palette.muted,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: palette.text,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        trailing:
            selected ? Icon(Icons.check_rounded, color: palette.brand) : null,
        onTap: () => Navigator.of(context).pop(FolderChoice(value)),
      );
    }

    return _SheetFrame(
      title: 'Move to folder',
      child: Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            row(Routine.defaultFolder, null, icon: Icons.inbox_outlined),
            for (final f in named) row(f, f),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  Icon(Icons.create_new_folder_outlined, color: palette.brand),
              title: Text(
                'New folder',
                style: TextStyle(
                  color: palette.brandText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () async {
                final name = await showRoutineTextPrompt(
                  context,
                  title: 'New folder',
                  hint: 'e.g. Push · Pull · Legs',
                  action: 'Create',
                );
                if (name != null && context.mounted) {
                  Navigator.of(context).pop(FolderChoice(name));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// When a routine is started over a session already running.
enum StartConflict { resume, discardAndStart }

Future<StartConflict?> showStartConflictSheet(
  BuildContext context, {
  required String routineName,
}) {
  return _showSheet<StartConflict>(
    context,
    _StartConflictSheet(routineName: routineName),
  );
}

class _StartConflictSheet extends StatelessWidget {
  const _StartConflictSheet({required this.routineName});

  final String routineName;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _SheetFrame(
      title: 'A workout is already running',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Starting $routineName ends the one in progress without saving '
            'it.',
            style: TextStyle(color: palette.muted, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Resume current workout',
            onPressed: () => Navigator.of(context).pop(StartConflict.resume),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(StartConflict.discardAndStart),
            style: TextButton.styleFrom(foregroundColor: palette.danger),
            child: Text('Discard it and start $routineName'),
          ),
        ],
      ),
    );
  }
}
