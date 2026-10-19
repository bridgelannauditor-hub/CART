import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../models/seller_onboarding_model.dart';
import '../../repositories/seller_application_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../utils/routes.dart';
import 'identity_capture_screen.dart';
import 'seller_application_screen.dart';
import 'seller_shop_setup_screen.dart';

/// Guides a Buyer through becoming a Seller:
/// 1 account, 2 apply and accept terms, 3 verify identity, 4 result,
/// 5 shop setup, 6 final approval. Every transition is decided by the server.
class SellerOnboardingScreen extends StatefulWidget {
  const SellerOnboardingScreen({super.key});

  @override
  State<SellerOnboardingScreen> createState() => _SellerOnboardingScreenState();
}

class _SellerOnboardingScreenState extends State<SellerOnboardingScreen>
    with WidgetsBindingObserver {
  final _repository = SellerApplicationRepository();
  SellerOnboardingState? _state;
  String? _loadError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Returning from the provider's verification page refreshes the result.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final state = await _repository.fetchOnboarding();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _loadError = 'Your Seller application could not be loaded.',
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openApplicationForm() async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SellerApplicationScreen(termsVersion: _state!.currentTermsVersion),
      ),
    );
    if (submitted == true) await _load();
  }

  /// Opens the in-app camera flow for the ID and selfie photos. They are
  /// queued for manual review by an administrator.
  Future<void> _startIdentityVerification() async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const IdentityCaptureScreen()),
    );
    if (submitted == true) {
      _showMessage(
        'Photos sent. An administrator will review them and you will be '
        'notified.',
      );
    }
    await _load();
  }

  Future<void> _requestSchoolEmailVerification() async {
    setState(() => _busy = true);
    try {
      final challenge = await _repository.requestSchoolEmailVerification();
      if (!mounted) return;
      final verified = await _showSchoolEmailCodeDialog(challenge);
      if (verified == true) {
        _showMessage('School email verified.');
        await _load();
      }
    } on FunctionException catch (error) {
      final details = error.details;
      _showMessage(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'The verification email could not be sent.',
      );
    } catch (_) {
      _showMessage('The verification email could not be sent.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _showSchoolEmailCodeDialog(
    SchoolEmailChallengeStart challenge,
  ) {
    final controller = TextEditingController(text: challenge.prototypeCode);
    var saving = false;
    String? errorText;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Verify school email'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (challenge.prototypeCode != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'PROTOTYPE ONLY\nCode: ${challenge.prototypeCode}\n'
                    'No email was sent. Final Seller access still requires '
                    'administrator approval.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ] else
                Text(
                  'Enter the six-digit code sent to ${challenge.maskedEmail}.',
                ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                enabled: !saving,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Verification code',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final code = controller.text.trim();
                      if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                        setDialogState(
                          () => errorText = 'Enter the six-digit code.',
                        );
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        errorText = null;
                      });
                      try {
                        await _repository.verifySchoolEmailCode(
                          challengeId: challenge.challengeId,
                          code: code,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } on FunctionException catch (error) {
                        final details = error.details;
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          saving = false;
                          errorText =
                              details is Map && details['error'] is String
                              ? details['error'] as String
                              : 'The code could not be verified.';
                        });
                      } catch (_) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          saving = false;
                          errorText = 'The code could not be verified.';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('VERIFY'),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _openShopSetup() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SellerShopSetupScreen(application: _state!.application!),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _appeal() async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request another review'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 1000,
          decoration: const InputDecoration(
            hintText:
                'Explain what changed or why the decision should be reviewed.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.isEmpty) return;
    if (message.length < 10) {
      _showMessage('Please explain the appeal in at least 10 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.appeal(message);
      _showMessage('Your appeal was sent for review.');
    } catch (_) {
      _showMessage('The appeal could not be sent. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _openSellerDashboard() async {
    setState(() => _busy = true);
    try {
      final profile = await AuthService().restoreSession();
      if (profile == null || profile.accountType != 'Seller') {
        _showMessage(
          'Your approval is recorded, but your profile is still refreshing. Pull down and try again.',
        );
        return;
      }
      SessionService.loginUser(profile);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.sellerDashboard,
        (route) => false,
      );
    } catch (_) {
      _showMessage('Your Seller dashboard could not be opened. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Become a Seller')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (_loadError != null)
              _Notice(
                icon: Icons.error_outline,
                color: AppColors.error,
                title: 'Something went wrong',
                body: _loadError!,
              )
            else if (state == null)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              const Text(
                'Your Buyer account stays fully active while you apply. Seller tools unlock only after final approval.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 16),
              _ApplicationStatusCard(state: state),
              const SizedBox(height: 12),
              _currentStepCard(state),
              const SizedBox(height: 24),
              _StepList(step: state.step),
            ],
          ],
        ),
      ),
    );
  }

  Widget _currentStepCard(SellerOnboardingState state) {
    final app = state.application;
    switch (state.step) {
      case SellerOnboardingStep.verifyAccount:
        return const _Notice(
          icon: Icons.mark_email_unread_outlined,
          color: AppColors.secondary,
          title: 'Verify your email first',
          body:
              'Open the confirmation link we emailed you, then come back '
              'here. Accounts created with Google or Facebook are already verified.',
        );
      case SellerOnboardingStep.apply:
        return _Notice(
          icon: Icons.storefront_outlined,
          color: AppColors.primary,
          title: app == null ? 'Apply to sell' : 'Accept the updated terms',
          body:
              'Tell us about yourself, choose your ID type, and accept the '
              'Seller terms.',
          action: _ActionButton(
            label: app == null ? 'START APPLICATION' : 'REVIEW APPLICATION',
            busy: _busy,
            onPressed: _openApplicationForm,
          ),
        );
      case SellerOnboardingStep.verifySchoolEmail:
        return _Notice(
          icon: Icons.alternate_email_rounded,
          color: AppColors.primary,
          title: 'Verify your school email',
          body:
              'We will send a six-digit code to ${app?.schoolEmail ?? 'your school address'}. '
              'The code expires after 10 minutes.',
          action: _ActionButton(
            label: 'SEND VERIFICATION CODE',
            busy: _busy,
            onPressed: _requestSchoolEmailVerification,
          ),
        );
      case SellerOnboardingStep.verifyIdentity:
        final retry = app?.identityStatus == 'needs_retry';
        final pending = app?.identityStatus == 'pending';
        return _Notice(
          icon: retry ? Icons.refresh : Icons.badge_outlined,
          color: retry ? AppColors.secondary : AppColors.primary,
          title: retry
              ? 'Needs another attempt'
              : pending
              ? 'Verification in progress'
              : 'Verify your identity',
          body: retry
              ? '${describeSellerReasonCode(app?.identityReasonCode)}\n\n'
                    'Attempts left: ${state.identityAttemptsLeft}.'
              : pending
              ? 'Your earlier verification session did not finish. Take your '
                    'photos again to continue.'
              : 'Take a photo of your ID and a selfie with your camera. An '
                    'administrator reviews them before your Seller access is '
                    'approved.',
          action: _ActionButton(
            label: retry || pending ? 'RETAKE PHOTOS' : 'TAKE ID PHOTOS',
            busy: _busy,
            onPressed: _startIdentityVerification,
          ),
        );
      case SellerOnboardingStep.identityUnderReview:
        return const _Notice(
          icon: Icons.schedule,
          color: AppColors.secondary,
          title: 'Under review',
          body:
              'Your ID photos were received and are waiting for an '
              'administrator to review them. Seller tools stay locked until '
              'it is complete. We will notify you.',
        );
      case SellerOnboardingStep.setUpShop:
        final changesRequested = app?.shopStatus == 'changes_requested';
        return _Notice(
          icon: Icons.check_circle_outline,
          color: AppColors.success,
          title: changesRequested ? 'Update your shop' : 'Verified',
          body: changesRequested
              ? describeSellerReasonCode(app?.reviewReasonCode)
              : 'Your identity checks passed. Set up your shop next; seller '
                    'tools stay locked until final approval.',
          action: _ActionButton(
            label: app?.shopStatus == 'not_started'
                ? 'SET UP SHOP'
                : 'CONTINUE SHOP SETUP',
            busy: _busy,
            onPressed: _openShopSetup,
          ),
        );
      case SellerOnboardingStep.awaitingApproval:
        return _Notice(
          icon: Icons.hourglass_top,
          color: AppColors.secondary,
          title: 'Waiting for final approval',
          body:
              'Cart is reviewing "${app?.shopName ?? 'your shop'}". You '
              'can keep shopping as a Buyer in the meantime.',
        );
      case SellerOnboardingStep.appealed:
        return const _Notice(
          icon: Icons.schedule,
          color: AppColors.secondary,
          title: 'Appeal under review',
          body: 'Your appeal was received. We will notify you of the decision.',
        );
      case SellerOnboardingStep.rejected:
        final reason = app?.reviewReasonCode ?? app?.identityReasonCode;
        final identityRejected = app?.identityStatus == 'rejected';
        return _Notice(
          icon: Icons.cancel_outlined,
          color: AppColors.error,
          title: 'Not approved',
          body:
              '${describeSellerReasonCode(reason)}\n\n'
              '${state.canAppeal ? 'You can correct your application or request another review.' : 'Contact Cart support for next steps.'}',
          action: state.canAppeal
              ? Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _ActionButton(
                      label: 'REQUEST REVIEW',
                      busy: _busy,
                      onPressed: _appeal,
                    ),
                    if (!identityRejected)
                      OutlinedButton(
                        onPressed: _busy ? null : _openApplicationForm,
                        child: const Text('EDIT APPLICATION'),
                      ),
                  ],
                )
              : null,
        );
      case SellerOnboardingStep.approved:
        return _Notice(
          icon: Icons.verified_outlined,
          color: AppColors.success,
          title: 'You are an approved Seller',
          body: 'Your Seller tools are ready.',
          action: _ActionButton(
            label: 'OPEN SELLER DASHBOARD',
            busy: _busy,
            onPressed: _openSellerDashboard,
          ),
        );
      case SellerOnboardingStep.suspended:
        return const _Notice(
          icon: Icons.block,
          color: AppColors.error,
          title: 'Seller access suspended',
          body:
              'Your Buyer account still works. Contact Cart support for details.',
        );
    }
  }
}

class _ApplicationStatusCard extends StatelessWidget {
  final SellerOnboardingState state;

  const _ApplicationStatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final status = state.applicationStatus;
    final (icon, color) = switch (status) {
      SellerApplicationStatus.notApplied => (
        Icons.assignment_outlined,
        AppColors.textSecondary,
      ),
      SellerApplicationStatus.pendingVerification => (
        Icons.pending_actions_outlined,
        AppColors.secondary,
      ),
      SellerApplicationStatus.verificationInProgress => (
        Icons.manage_search_outlined,
        AppColors.secondary,
      ),
      SellerApplicationStatus.verificationFailed => (
        Icons.report_gmailerrorred_outlined,
        AppColors.error,
      ),
      SellerApplicationStatus.shopSetupRequired => (
        Icons.storefront_outlined,
        AppColors.primary,
      ),
      SellerApplicationStatus.pendingAdminApproval => (
        Icons.admin_panel_settings_outlined,
        AppColors.secondary,
      ),
      SellerApplicationStatus.approved => (
        Icons.verified_outlined,
        AppColors.success,
      ),
      SellerApplicationStatus.rejected => (
        Icons.cancel_outlined,
        AppColors.error,
      ),
      SellerApplicationStatus.requiresResubmission => (
        Icons.refresh_outlined,
        AppColors.secondary,
      ),
      SellerApplicationStatus.suspended => (
        Icons.block_outlined,
        AppColors.error,
      ),
    };

    return Semantics(
      container: true,
      label: 'Seller application status ${status.label}',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Application status',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status.label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    state.applicationStatusGuidance,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final Widget? action;

  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  final SellerOnboardingStep step;

  const _StepList({required this.step});

  static const _titles = [
    'Create and verify your account',
    'Apply and accept Seller terms',
    'Verify your identity with your camera',
    'Identity result',
    'Set up your shop',
    'Final approval',
  ];

  int get _currentIndex => switch (step) {
    SellerOnboardingStep.verifyAccount => 0,
    SellerOnboardingStep.apply => 1,
    SellerOnboardingStep.verifySchoolEmail => 2,
    SellerOnboardingStep.verifyIdentity => 2,
    SellerOnboardingStep.identityUnderReview => 3,
    SellerOnboardingStep.setUpShop => 4,
    SellerOnboardingStep.awaitingApproval ||
    SellerOnboardingStep.appealed ||
    SellerOnboardingStep.rejected => 5,
    SellerOnboardingStep.approved || SellerOnboardingStep.suspended => 6,
  };

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex;
    return Column(
      children: [
        for (var i = 0; i < _titles.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: i < current
                  ? AppColors.success
                  : i == current
                  ? AppColors.primary
                  : AppColors.lightGrey,
              child: i < current
                  ? const Icon(Icons.check, size: 16, color: AppColors.white)
                  : Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: i == current
                            ? AppColors.white
                            : AppColors.textSecondary,
                      ),
                    ),
            ),
            title: Text(
              _titles[i],
              style: TextStyle(
                color: i <= current
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight: i == current ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }
}
