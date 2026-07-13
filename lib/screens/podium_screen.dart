import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tournament_provider.dart';
import '../providers/settings_provider.dart';
import '../logic/export_logic.dart';

import 'package:confetti/confetti.dart';

class PodiumScreen extends StatefulWidget {
  const PodiumScreen({super.key});

  @override
  State<PodiumScreen> createState() => _PodiumScreenState();
}

class _PodiumScreenState extends State<PodiumScreen> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confettiController.play();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final settings = context.watch<SettingsProvider>();
    final ranked = provider.getRankedPlayers();

    final gold = ranked.isNotEmpty ? ranked[0] : null;
    final silver = ranked.length > 1 ? ranked[1] : null;
    final bronze = ranked.length > 2 ? ranked[2] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_pin, color: Colors.blueAccent),
            SizedBox(width: 12),
            Text(
              'All Knighters',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.home_rounded),
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text(
                  'ALL KNIGHTERS CHESS CLUB',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '🏆 TOURNAMENT COMPLETE',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(height: 40),

                // Podium
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 2nd Place
                      Expanded(
                        child: _buildPodiumMember(
                          context,
                          silver,
                          2,
                          Colors.grey.shade400,
                          120,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 1st Place
                      Expanded(
                        child: _buildPodiumMember(
                          context,
                          gold,
                          1,
                          Colors.yellow.shade700,
                          180,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 3rd Place
                      Expanded(
                        child: _buildPodiumMember(
                          context,
                          bronze,
                          3,
                          Colors.orange.shade800,
                          90,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
                const Divider(
                  color: Colors.white10,
                  thickness: 1,
                  indent: 40,
                  endIndent: 40,
                ),
                const SizedBox(height: 20),

                // Remainder List
                if (ranked.length > 3)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      children: List.generate(ranked.length - 3, (index) {
                        final p = ranked[index + 3];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.white10,
                            radius: 14,
                            child: Text(
                              '${index + 4}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          trailing: Text(
                            '${p.totalScore.toStringAsFixed(1)} pts',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ElevatedButton.icon(
                    onPressed: () => ExportLogic.exportToMarkdown(
                      tournamentName: provider.tournamentName,
                      players: provider.players,
                      rounds: provider.rounds,
                      totalRounds: settings.totalRounds,
                      duration: settings.roundDuration,
                    ),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('SHARE FINAL REPORT'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [
                Colors.blue,
                Colors.yellow,
                Colors.green,
                Colors.orange,
                Colors.purple,
              ],
              maxBlastForce: 20,
              minBlastForce: 5,
              emissionFrequency: 0.05,
              numberOfParticles: 50,
              gravity: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumMember(
    BuildContext context,
    dynamic player,
    int rank,
    Color color,
    double height,
  ) {
    if (player == null) return const SizedBox();
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(
          rank == 1
              ? Icons.emoji_events
              : (rank == 2 ? Icons.military_tech : Icons.workspace_premium),
          color: color,
          size: rank == 1 ? 40 : 32,
        ),
        const SizedBox(height: 8),
        Text(
          player.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        Text(
          '${player.totalScore.toStringAsFixed(1)} (+${player.handicap})',
          style: const TextStyle(fontSize: 8, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.8),
                color.withValues(alpha: 0.3),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Center(
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
