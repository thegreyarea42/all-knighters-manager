import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/tournament_provider.dart';
import '../providers/settings_provider.dart';
import '../models/pairing.dart';
import '../models/player.dart';
import '../widgets/timer_widget.dart';
import '../logic/export_logic.dart';
import 'podium_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Ensure standings are shown if tournament is finished on entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<TournamentProvider>();
      if (!provider.isTournamentStarted && provider.rounds.isNotEmpty) {
        _tabController.animateTo(1);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md'],
    );
    if (result != null) {
      String content;
      if (result.files.single.path != null) {
        content = await File(result.files.single.path!).readAsString();
      } else if (result.files.single.bytes != null) {
        content = utf8.decode(result.files.single.bytes!);
      } else {
        return;
      }
      final data = ExportLogic.parseMarkdown(content);
      if (data != null && mounted) {
        _showImportTypeDialog(context, data);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid Tournament File.')),
        );
      }
    }
  }

  void _showImportTypeDialog(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Smart Import'),
        content: const Text(
          'How would you like to use this file?\n\n'
          'Resume: Continue the tournament as the active session.\n'
          'Start New: Start a fresh tournament with these players and auto-calculate new handicaps.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resumeTournament(data);
            },
            child: const Text('RESUME SESSION'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startNewTournamentFromImport(data);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('START NEW'),
          ),
        ],
      ),
    );
  }

  void _resumeTournament(Map<String, dynamic> data) {
    if (!mounted) return;
    context.read<TournamentProvider>().resumeFromData(data);
    if (data.containsKey('duration') && data.containsKey('totalRounds')) {
      context.read<SettingsProvider>().updateSettings(
        data['duration'],
        data['totalRounds'],
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tournament state resumed successfully!')),
    );
  }

  void _startNewTournamentFromImport(Map<String, dynamic> data) {
    if (!mounted) return;
    if (data.containsKey('players')) {
      context.read<TournamentProvider>().importNewTournament(data);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New tournament created with calculated handicaps!'),
          backgroundColor: Colors.green,
        ),
      );
      // Navigate or tab to the settings / check-in screen if possible
      // Assuming check-in screen automatically takes over because tournament isn't started
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No player data found in file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All Knighters',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              provider.tournamentName,
              style: const TextStyle(fontSize: 12, color: Colors.blueAccent),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'DASHBOARD'),
            Tab(text: 'STANDINGS'),
            Tab(text: 'HISTORY'),
          ],
          indicatorColor: Colors.blueAccent,
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'export_md':
                  await ExportLogic.exportToMarkdown(
                    tournamentName: provider.tournamentName,
                    players: provider.players,
                    rounds: provider.rounds,
                    totalRounds: settings.totalRounds,
                    duration: settings.roundDuration,
                  );
                  break;
                case 'import':
                  await _handleImport();
                  break;
                case 'finalize':
                  _confirmFinalize(context, provider);
                  break;
                case 'reset':
                  _showResetDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export_md',
                child: Text('Export Markdown (.md)'),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Text('Import/Resume Session'),
              ),
              const PopupMenuItem(
                value: 'finalize',
                child: Text('Finalize Tournament Early'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'reset',
                child: Text(
                  'Reset Tournament',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        color: provider.isTournamentStarted && provider.currentRound != null
            ? (provider.secondsRemaining == 0
                  ? Colors.red.shade900
                  : (provider.secondsRemaining <= 300
                        ? Colors.yellow.withValues(alpha: 0.2)
                        : Colors.transparent))
            : Colors.transparent,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildControlTab(),
            _buildStandingsTab(),
            _buildHistoryTab(),
          ],
        ),
      ),
    );
  }

  void _confirmFinalize(BuildContext context, TournamentProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalize Tournament?'),
        content: const Text(
          'This will end the tournament immediately based on current standings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              provider.finalizeTournament();
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PodiumScreen()),
              );
            },
            child: const Text(
              'FINALIZE',
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Tournament?'),
        content: const Text('This will delete all progress and players.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              context.read<TournamentProvider>().resetTournament();
              Navigator.pop(context);
            },
            child: const Text(
              'RESET',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlTab() {
    final provider = context.watch<TournamentProvider>();
    final settings = context.watch<SettingsProvider>();
    final round = provider.currentRound;

    if (!provider.isTournamentStarted) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.emoji_events_outlined,
              size: 80,
              color: Colors.blueAccent,
            ),
            const SizedBox(height: 16),
            const Text(
              'Tournament Completed',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => _tabController.animateTo(1),
              child: const Text('VIEW FINAL STANDINGS'),
            ),
          ],
        ),
      );
    }

    if (round == null) return const Center(child: Text('No active round.'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'ROUND ${round.number} (PLANNED: ${settings.totalRounds})',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
          const SizedBox(height: 16),
          const TournamentTimer(),
          const SizedBox(height: 24),
          ...List.generate(
            round.pairings.length,
            (i) => _buildPairingCard(round.pairings[i], i + 1),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (provider.currentRoundNumber < settings.totalRounds) {
                provider.submitRound();
                provider.startNextRound(settings.roundDuration);
              } else {
                _showRoundEndOptions(context, provider, settings);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              provider.currentRoundNumber < settings.totalRounds
                  ? 'CONTINUE TO NEXT ROUND'
                  : 'ROUND COMPLETE (FINALIZE?)',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRoundEndOptions(
    BuildContext context,
    TournamentProvider provider,
    SettingsProvider settings,
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
              'PLANNED ROUNDS COMPLETE',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                provider.submitRound();
                provider.startNextRound(settings.roundDuration);
                settings.updateSettings(
                  settings.roundDuration,
                  settings.totalRounds + 1,
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                foregroundColor: Colors.blueAccent,
                minimumSize: const Size(double.infinity, 56),
              ),
              child: Text(
                'ADD EXTRA ROUND (ROUND ${provider.currentRoundNumber + 1})',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                provider.submitRound();
                provider.finalizeTournament();
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PodiumScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.withValues(alpha: 0.1),
                foregroundColor: Colors.greenAccent,
                minimumSize: const Size(double.infinity, 56),
              ),
              child: const Text('SUBMIT & FINALIZE TOURNAMENT'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPairingCard(Pairing pairing, int boardNumber) {
    final provider = context.read<TournamentProvider>();
    final whitePlayer = provider.players.firstWhere(
      (p) => p.id == pairing.whitePlayerId,
    );
    final blackPlayer = pairing.isBye
        ? null
        : provider.players.firstWhere((p) => p.id == pairing.blackPlayerId);

    final isRound1 = provider.currentRoundNumber == 1;
    final diffText = (!pairing.isBye)
        ? '${whitePlayer.handicap > 0 ? '+' : ''}${whitePlayer.handicap.toStringAsFixed(1)} vs '
              '${blackPlayer!.handicap > 0 ? '+' : ''}${blackPlayer.handicap.toStringAsFixed(1)}'
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      pairing.isBye ? 'BYE SLOT' : 'BOARD $boardNumber',
                      style: TextStyle(
                        color: Colors.blueAccent.withValues(alpha: 0.7),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    if (isRound1 && !pairing.isBye)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.yellowAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Handicap Gap: ($diffText)',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.yellowAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                if (!pairing.isBye)
                  IconButton(
                    onPressed: () =>
                        _adjudicateBoard(context, provider, pairing),
                    icon: const Icon(
                      Icons.gavel_rounded,
                      size: 16,
                      color: Colors.grey,
                    ),
                    tooltip: 'Adjudicate (Force Result)',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildPlayerInfo(whitePlayer, true),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white24,
                      fontSize: 20,
                    ),
                  ),
                ),
                blackPlayer != null
                    ? _buildPlayerInfo(blackPlayer, false)
                    : _buildByeInfo(),
              ],
            ),
            if (!pairing.isBye) ...[
              const Divider(height: 32, color: Colors.white10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildResultButton(
                    context,
                    'WHITE WIN',
                    GameResult.whiteWin,
                    pairing,
                    null,
                  ),
                  _buildResultButton(
                    context,
                    'DRAW',
                    GameResult.draw,
                    pairing,
                    null,
                  ),
                  _buildResultButton(
                    context,
                    'BLACK WIN',
                    GameResult.blackWin,
                    pairing,
                    null,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _adjudicateBoard(
    BuildContext context,
    TournamentProvider provider,
    Pairing pairing,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual Adjudication'),
        content: const Text('Force a result for this board to proceed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              provider.updateResult(
                pairing.whitePlayerId,
                pairing.blackPlayerId,
                GameResult.draw,
              );
              Navigator.pop(context);
            },
            child: const Text(
              'FORCE DRAW',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerInfo(dynamic player, bool isWhite) {
    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: isWhite ? Colors.white : Colors.black,
            radius: 24,
            child: Text(
              player.name[0].toUpperCase(),
              style: TextStyle(
                color: isWhite ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            player.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${player.earnedPoints} pts',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildByeInfo() {
    return const Expanded(
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey,
            radius: 24,
            child: Icon(Icons.person_off),
          ),
          SizedBox(height: 8),
          Text(
            'BYE',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildResultButton(
    BuildContext context,
    String label,
    GameResult result,
    Pairing pairing,
    int? roundNumber,
  ) {
    final provider = context.read<TournamentProvider>();
    bool isSelected = pairing.result == result;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          onPressed: () {
            if (roundNumber == null) {
              provider.updateResult(
                pairing.whitePlayerId,
                pairing.blackPlayerId,
                result,
              );
            } else {
              provider.correctResult(
                roundNumber,
                pairing.whitePlayerId,
                pairing.blackPlayerId,
                result,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Score updated. Pairings for subsequent rounds remain fixed, but standings have been recalculated.',
                  ),
                  backgroundColor: Colors.blueAccent,
                  duration: Duration(seconds: 4),
                ),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected
                ? Colors.blueAccent
                : Colors.white.withValues(alpha: 0.05),
            foregroundColor: isSelected ? Colors.white : Colors.grey,
            elevation: isSelected ? 4 : 0,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildStandingsTab() {
    final provider = context.watch<TournamentProvider>();
    final settings = context.watch<SettingsProvider>();
    final rankedPlayers = provider.getRankedPlayers();
    final isFinished =
        !provider.isTournamentStarted && provider.rounds.isNotEmpty;

    return Column(
      children: [
        if (isFinished)
          Container(
            width: double.infinity,
            color: Colors.greenAccent.withValues(alpha: 0.1),
            padding: const EdgeInsets.all(12),
            child: const Text(
              'FINAL STANDINGS - TOURNAMENT COMPLETE',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rankedPlayers.length,
            itemBuilder: (context, index) {
              final player = rankedPlayers[index];
              final buchholz = provider.calculateBuchholz(player);
              return Card(
                elevation: index == 0 ? 8 : 1,
                shadowColor: index == 0
                    ? Colors.blueAccent.withValues(alpha: 0.5)
                    : Colors.transparent,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: index < 3 ? Colors.blueAccent : Colors.grey,
                    ),
                  ),
                  title: Text(
                    player.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Text(
                    '${player.earnedPoints} (+${player.handicap} Hcp)\nBuchholz: ${buchholz.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    player.totalScore.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (isFinished)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () => ExportLogic.exportToMarkdown(
                tournamentName: provider.tournamentName,
                players: provider.players,
                rounds: provider.rounds,
                totalRounds: settings.totalRounds,
                duration: settings.roundDuration,
              ),
              icon: const Icon(Icons.share_rounded),
              label: const Text(
                'EXPORT FINAL REPORT',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    final provider = context.watch<TournamentProvider>();
    if (provider.rounds.isEmpty) {
      return const Center(child: Text('No rounds played yet.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.rounds.length,
      itemBuilder: (context, index) {
        final round = provider.rounds[index];
        return ExpansionTile(
          initiallyExpanded: index == provider.rounds.length - 1,
          title: Text(
            'ROUND ${round.number}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
          subtitle: Text(
            round.isCompleted ? 'COMPLETED' : 'IN PROGRESS',
            style: TextStyle(
              fontSize: 12,
              color: round.isCompleted ? Colors.grey : Colors.greenAccent,
            ),
          ),
          children: round.pairings
              .map(
                (p) => _buildHistoryPairing(
                  context,
                  p,
                  round.number,
                  provider.players,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildHistoryPairing(
    BuildContext context,
    Pairing pairing,
    int roundNumber,
    List<Player> allPlayers,
  ) {
    final white = allPlayers.firstWhere((p) => p.id == pairing.whitePlayerId);
    final black = pairing.isBye
        ? null
        : allPlayers.firstWhere((p) => p.id == pairing.blackPlayerId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  white.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'VS',
                  style: TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
              Expanded(
                child: Text(
                  black?.name ?? 'BYE',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          if (!pairing.isBye) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _buildResultButton(
                  context,
                  'W',
                  GameResult.whiteWin,
                  pairing,
                  roundNumber,
                ),
                _buildResultButton(
                  context,
                  'D',
                  GameResult.draw,
                  pairing,
                  roundNumber,
                ),
                _buildResultButton(
                  context,
                  'B',
                  GameResult.blackWin,
                  pairing,
                  roundNumber,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
