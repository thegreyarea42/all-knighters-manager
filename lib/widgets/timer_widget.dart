import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/tournament_provider.dart';

class TournamentTimer extends StatelessWidget {
  const TournamentTimer({super.key});

  String _formatTime(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Color _getTimerColor(int seconds) {
    if (seconds == 0) return Colors.red;
    if (seconds <= 60) return Colors.redAccent;
    if (seconds <= 300) return Colors.yellowAccent;
    return Colors.white;
  }

  void _handleAlerts(int seconds) {
    if (seconds == 300) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    } else if (seconds == 0) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.vibrate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final seconds = provider.secondsRemaining;
    final isRunning = provider.isTimerRunning;
    final color = _getTimerColor(seconds);

    // Call alerts (this is a bit hacky in build, but since it's a provider change it works for simple cases)
    // For a more robust approach, we could use a listener in a stateful wrapper.
    if (isRunning) {
      _handleAlerts(seconds);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 30,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: Colors.grey, size: 16),
              const SizedBox(width: 8),
              Text(
                seconds <= 300 && seconds > 0
                    ? 'TIME WARNING'
                    : (seconds == 0 ? 'ROUND EXPIRED' : 'MATCH TIME'),
                style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  letterSpacing: 2,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            child: Text(
              _formatTime(seconds),
              style: TextStyle(
                fontSize: 100,
                fontWeight: FontWeight.w900,
                fontFamily: 'Courier',
                color: color,
                letterSpacing: 4,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton(
                onPressed: () => _showTimerControlModal(context, provider),
                icon: Icons.tune_rounded,
                color: Colors.white24,
              ),
              const SizedBox(width: 32),
              _buildControlButton(
                onPressed: provider.toggleTimer,
                icon: isRunning
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: isRunning ? Colors.orangeAccent : Colors.greenAccent,
                isLarge: true,
              ),
              const SizedBox(width: 32),
              _buildControlButton(
                onPressed: () => provider.adjustTime(60),
                icon: Icons.add_circle_outline_rounded,
                color: Colors.white10,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTimerControlModal(
    BuildContext context,
    TournamentProvider provider,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'TIMER OVERLOAD',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildModalButton(
                  context,
                  '+5 MIN',
                  () => provider.adjustTime(300),
                  Colors.blueAccent,
                ),
                _buildModalButton(
                  context,
                  '+1 MIN',
                  () => provider.adjustTime(60),
                  Colors.blueAccent,
                ),
                _buildModalButton(
                  context,
                  '-1 MIN',
                  () => provider.adjustTime(-60),
                  Colors.redAccent,
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _confirmStopRound(context, provider);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.1),
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'STOP ROUND NOW',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _confirmStopRound(BuildContext context, TournamentProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Round Immediately?'),
        content: const Text(
          'This will trigger the buzzer and freeze all boards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              provider.stopRoundNow();
              Navigator.pop(context);
            },
            child: const Text('STOP NOW', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required VoidCallback onPressed,
    required IconData icon,
    required Color color,
    bool isLarge = false,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.all(isLarge ? 16 : 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, color: color, size: isLarge ? 40 : 24),
      ),
    );
  }

  Widget _buildModalButton(
    BuildContext context,
    String label,
    VoidCallback onTap,
    Color color,
  ) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
