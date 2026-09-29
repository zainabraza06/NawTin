import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'glass_panel.dart';
import 'token_painter.dart';

/// A player's card: avatar token, name, tokens left to place and the tokens
/// they have eaten. The active card glows and lifts; the other dims.
class PlayerCard extends StatelessWidget {
  const PlayerCard({
    super.key,
    required this.seat,
    required this.name,
    required this.toPlace,
    required this.onBoard,
    required this.eaten,
    required this.active,
  });

  final int seat;
  final String name;
  final int toPlace;
  final int onBoard;

  /// Opponent tokens this player has captured.
  final int eaten;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final color = tk.seatColor(seat);
    final status = toPlace > 0 ? '$toPlace to place' : '$onBoard on board';
    return Semantics(
      label: '$name, ${active ? "your turn" : "waiting"}, $status, $eaten tokens eaten',
      child: AnimatedOpacity(
        duration: tk.medium,
        opacity: active ? 1 : 0.55,
        child: AnimatedSlide(
          duration: tk.medium,
          curve: tk.emphasized,
          offset: active ? const Offset(0, -0.04) : Offset.zero,
          child: AnimatedScale(
            duration: tk.medium,
            curve: tk.emphasized,
            scale: active ? 1.02 : 1,
            child: GlassPanel(
              glow: active ? color : null,
              radius: tk.radiusM,
              padding: EdgeInsets.symmetric(horizontal: tk.space2, vertical: tk.space1 + 4),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.14),
                      border: Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    child: Center(child: TokenIcon(seat: seat, size: 40)),
                  ),
                  SizedBox(width: tk.space2 - 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tk.heading(NawTinTokens.scaleS)),
                        const SizedBox(height: 2),
                        Text(status, style: tk.body(NawTinTokens.scaleXS)),
                      ],
                    ),
                  ),
                  _EatenRow(eaten: eaten, victimSeat: 1 - seat),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EatenRow extends StatelessWidget {
  const _EatenRow({required this.eaten, required this.victimSeat});
  final int eaten;
  final int victimSeat;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    if (eaten == 0) {
      return Text('0', style: tk.digits(NawTinTokens.scaleS, color: tk.textMuted));
    }
    const shown = 4;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < eaten && i < shown; i++)
          Align(
            widthFactor: 0.6,
            child: TokenIcon(seat: victimSeat, size: 22, glow: 0.2),
          ),
        if (eaten > shown)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('+${eaten - shown}', style: tk.digits(NawTinTokens.scaleXS)),
          ),
      ],
    );
  }
}
