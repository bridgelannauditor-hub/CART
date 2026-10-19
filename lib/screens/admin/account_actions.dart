import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../repositories/admin_repository.dart';
import 'suspension_dialog.dart';

/// Warns, suspends or restores an account, with the same dialogs wherever an
/// administrator takes the action (user directory, reports).
///
/// [action] is 'warn', 'suspend' or 'restore'. Suspending an account that has
/// never been warned first offers to send a warning instead. Returns true when
/// the account was changed.
Future<bool> runAccountAction(
  BuildContext context, {
  required AdminRepository repository,
  required int profileId,
  required String name,
  required String action,
}) async {
  var warning = action == 'warn';
  final suspend = action == 'suspend';
  final String reason;
  var categories = const <String>[];

  if (warning || suspend) {
    // The server finds the reports against the account; the administrator
    // reviews them and decides.
    Map<String, dynamic> evidence;
    try {
      evidence = await repository.accountEvidence(profileId);
    } catch (_) {
      evidence = const {};
    }
    if (!context.mounted) return false;
    final warned = ((evidence['warnings'] as Map?)?['total'] as num?)?.toInt();
    if (suspend && (warned ?? 0) == 0) {
      final choice = await showWarnFirstDialog(context, name: name);
      if (choice == null || !context.mounted) return false;
      warning = choice == WarnFirstChoice.warn;
    }
    final decision = await showSuspensionDialog(
      context,
      name: name,
      evidence: evidence,
      warning: warning,
    );
    if (decision == null || !context.mounted) return false;
    reason = decision.reason;
    categories = decision.categories;
  } else {
    final restoreReason = await showDialog<String>(
      context: context,
      builder: (_) => _RestoreDialog(name: name),
    );
    if (restoreReason == null || !context.mounted) return false;
    reason = restoreReason;
  }

  try {
    if (warning) {
      await repository.warnAccount(
        profileId: profileId,
        message: reason,
        categories: categories,
      );
    } else {
      await repository.setAccountSuspension(
        profileId: profileId,
        suspend: suspend,
        reason: reason,
        categories: categories,
      );
    }
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          warning
              ? '$name was warned.'
              : suspend
              ? '$name was suspended.'
              : '$name was restored.',
        ),
      ),
    );
    return true;
  } on PostgrestException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The account could not be updated.')),
      );
    }
  }
  return false;
}

/// Asks for the reason an administrator must give to restore an account. The
/// dialog owns its text controller so it is disposed only after the route has
/// fully closed.
class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.name});
  final String name;

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _controller.text.trim();
    final valid = reason.length >= 3 && reason.length <= 500;
    return AlertDialog(
      title: Text('Restore ${widget.name}?'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        maxLength: 500,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'Why is this account being restored?',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: valid ? () => Navigator.pop(context, reason) : null,
          child: const Text('Restore'),
        ),
      ],
    );
  }
}
