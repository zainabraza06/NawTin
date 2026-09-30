import 'package:flutter/material.dart';

import '../../services/ads/ads_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/naw_button.dart';

enum _Phase { idle, watching, failed, done }

/// Bottom sheet that gates an assist behind [ads] rewarded ads: "Watch 2 ads to
/// see the best move?" with progress dots (ad 1 of 2) and Watch / Cancel.
/// Resolves true only when every ad was watched to the end.
Future<bool> showAdGate(
  BuildContext context, {
  required String title,
  required String body,
  required int ads,
  required IconData icon,
  required Future<AdChainResult> Function(void Function(int index) onStart, void Function(int done) onProgress) run,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    isScrollControlled: true,
    builder: (_) => _AdGateSheet(title: title, body: body, ads: ads, icon: icon, run: run),
  );
  return ok ?? false;
}

class _AdGateSheet extends StatefulWidget {
  const _AdGateSheet({
    required this.title,
    required this.body,
    required this.ads,
    required this.icon,
    required this.run,
  });

  final String title;
  final String body;
  final int ads;
  final IconData icon;
  final Future<AdChainResult> Function(void Function(int) onStart, void Function(int) onProgress) run;

  @override
  State<_AdGateSheet> createState() => _AdGateSheetState();
}

class _AdGateSheetState extends State<_AdGateSheet> {
  _Phase _phase = _Phase.idle;
  int _done = 0;
  int _current = 0;
  String? _error;

  Future<void> _watch() async {
    setState(() {
      _phase = _Phase.watching;
      _done = 0;
      _current = 1;
      _error = null;
    });
    final result = await widget.run(
      (i) {
        if (mounted) setState(() => _current = i);
      },
      (d) {
        if (mounted) setState(() => _done = d);
      },
    );
    if (!mounted) return;
    if (result.granted) {
      setState(() => _phase = _Phase.done);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() {
        _phase = _Phase.failed;
        _error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final watching = _phase == _Phase.watching;
    return PopScope(
      canPop: !watching,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(tk.space2),
          child: GlassPanel(
            padding: EdgeInsets.all(tk.space3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(widget.icon, color: tk.lime),
                    const SizedBox(width: 10),
                    Expanded(child: Text(widget.title, style: tk.heading(NawTinTokens.scaleM))),
                  ],
                ),
                const SizedBox(height: 8),
                Text(widget.body, style: tk.body(NawTinTokens.scaleS - 1)),
                SizedBox(height: tk.space2),
                _Dots(total: widget.ads, done: _done, current: watching ? _current : 0),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: tk.medium,
                  child: Text(
                    switch (_phase) {
                      _Phase.idle => 'Ad 0 of ${widget.ads}',
                      _Phase.watching => 'Ad $_current of ${widget.ads} is playing. Watch it to the end.',
                      _Phase.failed => _error ?? AdsService.noAdMessage,
                      _Phase.done => 'Unlocked!',
                    },
                    key: ValueKey('$_phase$_current$_done'),
                    textAlign: TextAlign.center,
                    style: tk.body(
                      NawTinTokens.scaleXS + 1,
                      color: _phase == _Phase.failed
                          ? tk.amber
                          : (_phase == _Phase.done ? tk.lime : tk.textPrimary),
                    ),
                  ),
                ),
                SizedBox(height: tk.space3),
                if (watching)
                  const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)))
                else if (_phase != _Phase.done) ...[
                  NawButton(
                    label: _phase == _Phase.failed
                        ? 'Try again'
                        : 'Watch ${widget.ads} ${widget.ads == 1 ? "ad" : "ads"}',
                    icon: Icons.play_circle_fill_rounded,
                    onPressed: _watch,
                  ),
                  SizedBox(height: tk.space1),
                  NawButton(
                    label: 'Cancel',
                    style: NawButtonStyle.ghost,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.total, required this.done, required this.current});
  final int total;
  final int done;

  /// 1-based ad currently playing, or 0.
  final int current;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: tk.medium,
            curve: tk.emphasized,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: i + 1 == current ? 30 : 14,
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              color: i < done
                  ? tk.lime
                  : (i + 1 == current ? tk.violet : Colors.white.withValues(alpha: 0.18)),
              boxShadow: [
                if (i < done) BoxShadow(color: tk.lime.withValues(alpha: 0.5), blurRadius: 10),
              ],
            ),
          ),
      ],
    );
  }
}

/// Lets the player choose between the two hints. Returns 1 or 2, or null.
Future<int?> showHintChooser(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final tk = ctx.tokens;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.all(tk.space2),
          child: GlassPanel(
            padding: EdgeInsets.all(tk.space3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Need a hand?', style: tk.heading(NawTinTokens.scaleM)),
                const SizedBox(height: 4),
                Text('Hints are free to ask for, paid for with rewarded ads.', style: tk.body(NawTinTokens.scaleXS + 1)),
                SizedBox(height: tk.space2),
                NawButton(
                  label: 'Warning',
                  caption: '1 ad - what to watch out for',
                  icon: Icons.warning_amber_rounded,
                  style: NawButtonStyle.secondary,
                  onPressed: () => Navigator.of(ctx).pop(1),
                ),
                SizedBox(height: tk.space1),
                NawButton(
                  label: 'Best move',
                  caption: '2 ads - warning plus the move, highlighted',
                  icon: Icons.tips_and_updates_rounded,
                  onPressed: () => Navigator.of(ctx).pop(2),
                ),
                SizedBox(height: tk.space1),
                NawButton(label: 'Not now', style: NawButtonStyle.ghost, onPressed: () => Navigator.of(ctx).pop()),
              ],
            ),
          ),
        ),
      );
    },
  );
}
