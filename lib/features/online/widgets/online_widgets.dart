import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naw_tin_core/naw_tin_core.dart';

import '../../../services/online/online_service.dart';
import '../../../services/settings.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/aurora_background.dart';
import '../../../widgets/glass_panel.dart';
import '../../../widgets/naw_button.dart';
import '../online_issue.dart';

/// Shared frame of every online page: aurora background, centred column, an
/// optional title row with a back button.
class OnlineFrame extends ConsumerWidget {
  const OnlineFrame({
    super.key,
    required this.child,
    this.title,
    this.onBack,
    this.trailing,
  });

  final Widget child;
  final String? title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tokens;
    final prefs = ref.watch(settingsProvider).motion;
    return Scaffold(
      body: AuroraBackground(
        prefs: prefs,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: tk.space3),
                child: Column(
                  children: [
                    if (title != null || onBack != null)
                      SizedBox(
                        height: 56,
                        child: Row(
                          children: [
                            if (onBack != null)
                              IconButton(
                                tooltip: 'Back',
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                onPressed: onBack,
                                icon: Icon(
                                  Icons.arrow_back_rounded,
                                  color: tk.textPrimary,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tk.heading(NawTinTokens.scaleM),
                              ),
                            ),
                            if (trailing != null) trailing!,
                          ],
                        ),
                      ),
                    Expanded(child: child),
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

/// Small coloured dot + word for the connection ("Online", "Connecting...").
class ConnectionDot extends StatelessWidget {
  const ConnectionDot({super.key, required this.state, this.showLabel = false});

  final ConnectionState state;
  final bool showLabel;

  static (String, Color Function(NawTinTokens)) describe(ConnectionState s) {
    if (s.isOnline) return ('Online', (t) => t.lime);
    if (s.isStopped) return ('Offline', (t) => t.danger);
    if (s.phase == ConnPhase.idle) return ('Not connected', (t) => t.textMuted);
    return ('Connecting...', (t) => t.amber);
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final (label, color) = describe(state);
    final c = color(tk);
    return Semantics(
      label: 'Connection: $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c,
              boxShadow: [
                BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6),
              ],
            ),
          ),
          if (showLabel) ...[
            const SizedBox(width: 8),
            Text(
              label,
              style: tk.body(NawTinTokens.scaleXS, color: tk.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A full-screen explanation of what is wrong, with a single action.
class IssueView extends StatelessWidget {
  const IssueView({super.key, required this.issue, required this.onAction});

  final OnlineIssue issue;
  final ValueChanged<IssueAction> onAction;

  static IconData iconFor(OnlineIssue i) => switch (i) {
    OnlineIssue.notConfigured => Icons.cloud_off_rounded,
    OnlineIssue.outdated => Icons.system_update_rounded,
    OnlineIssue.replaced => Icons.devices_rounded,
    OnlineIssue.signInFailed => Icons.lock_outline_rounded,
    OnlineIssue.noInternet => Icons.wifi_off_rounded,
    OnlineIssue.serverDown => Icons.dns_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final copy = issueCopy[issue]!;
    return Center(
      child: GlassPanel(
        padding: EdgeInsets.all(tk.space3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconFor(issue), size: 56, color: tk.amber),
            SizedBox(height: tk.space2),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                copy.title,
                textAlign: TextAlign.center,
                style: tk.heading(NawTinTokens.scaleM),
              ),
            ),
            SizedBox(height: tk.space1),
            Text(
              copy.message,
              textAlign: TextAlign.center,
              style: tk.body(NawTinTokens.scaleS, color: tk.textMuted),
            ),
            SizedBox(height: tk.space3),
            NawButton(
              label: copy.actionLabel,
              onPressed: () => onAction(copy.action),
            ),
          ],
        ),
      ),
    );
  }
}

/// Six boxes for a room code, fed by one hidden text field so paste, the
/// keyboard's autofill and screen readers all work.
class CodeBoxes extends StatelessWidget {
  const CodeBoxes({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.error = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Semantics(
      label: 'Room code, $roomCodeLength characters',
      textField: true,
      child: GestureDetector(
        onTap: () => focusNode.requestFocus(),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([controller, focusNode]),
              builder: (context, _) {
                final text = controller.text;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < roomCodeLength; i++)
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 52),
                          height: 58,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(tk.radiusM),
                            color: Colors.white.withValues(alpha: 0.08),
                            border: Border.all(
                              color: error
                                  ? tk.danger
                                  : (focusNode.hasFocus && i == text.length
                                        ? tk.violet
                                        : tk.glassBorder.withValues(
                                            alpha: 0.25,
                                          )),
                              width: focusNode.hasFocus && i == text.length
                                  ? 2
                                  : 1,
                            ),
                          ),
                          child: Text(
                            i < text.length ? text[i] : '',
                            style: tk.digits(NawTinTokens.scaleL),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            // the real input: invisible, but it holds focus and the text
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  key: const ValueKey('code-input'),
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.go,
                  inputFormatters: [_CodeFormatter()],
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  enableInteractiveSelection: false,
                  showCursor: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Upper-cases, drops anything that is not a letter or digit (so pasted
/// "abc-123" works) and caps the length.
class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue old,
    TextEditingValue now,
  ) {
    var t = normalizeRoomCode(now.text);
    if (t.length > roomCodeLength) t = t.substring(0, roomCodeLength);
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}
