import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/tournament_provider.dart';
import '../providers/settings_provider.dart';
import '../logic/export_logic.dart';
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _handicapController = TextEditingController(
    text: '0.0',
  );
  late TextEditingController _tournamentNameController;

  @override
  void initState() {
    super.initState();
    final initialName = context.read<TournamentProvider>().tournamentName;
    _tournamentNameController = TextEditingController(text: initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _handicapController.dispose();
    _tournamentNameController.dispose();
    super.dispose();
  }

  void _addPlayer() {
    if (_nameController.text.trim().isNotEmpty) {
      final handicap = double.tryParse(_handicapController.text) ?? 0.0;
      context.read<TournamentProvider>().addPlayer(
        _nameController.text.trim(),
        handicap,
      );
      _nameController.clear();
      _handicapController.text = '0.0';
    }
  }

  void _showSettings(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final provider = context.read<TournamentProvider>();
    final durationController = TextEditingController(
      text: settings.roundDuration.toString(),
    );
    final roundsController = TextEditingController(
      text: settings.totalRounds.toString(),
    );

    showDialog(
      context: context,
      builder: (context) {
        String r1Mode = settings.round1PairingMode;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Tournament Settings'),
            backgroundColor: const Color(0xFF1A1A1A),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: durationController,
                  decoration: const InputDecoration(
                    labelText: 'Round Duration (mins)',
                    labelStyle: TextStyle(color: Colors.grey),
                  ),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: roundsController,
                  decoration: const InputDecoration(
                    labelText: 'Total Rounds',
                    labelStyle: TextStyle(color: Colors.grey),
                  ),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: r1Mode,
                  decoration: const InputDecoration(
                    labelText: 'Round 1 Pairing',
                    labelStyle: TextStyle(color: Colors.grey),
                  ),
                  dropdownColor: const Color(0xFF1E1E1E),
                  style: const TextStyle(color: Colors.white),
                  items: ['Parity', 'Random', 'Seeded']
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => r1Mode = val);
                    }
                  },
                ),
              ],
            ),
            actions: [
          const Divider(),
          ListTile(
            title: const Text(
              'Export Current Tournament',
              style: TextStyle(fontSize: 14),
            ),
            leading: const Icon(Icons.share, color: Colors.blueAccent),
            onTap: () async {
              await ExportLogic.exportToMarkdown(
                tournamentName: provider.tournamentName,
                players: provider.players,
                rounds: provider.rounds,
                totalRounds: settings.totalRounds,
                duration: settings.roundDuration,
              );
            },
          ),
          ListTile(
            title: const Text(
              'Import Tournament File',
              style: TextStyle(fontSize: 14),
            ),
            leading: const Icon(Icons.file_open, color: Colors.greenAccent),
            onTap: () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['md'],
              );
              if (result != null) {
                String content;
                if (result.files.single.path != null) {
                  content = await File(
                    result.files.single.path!,
                  ).readAsString();
                } else {
                  content = utf8.decode(result.files.single.bytes!);
                }
                final data = ExportLogic.parseMarkdown(content);
                if (data != null) {
                  if (!context.mounted) return;
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
                            provider.resumeFromData(data);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Resumed ${provider.tournamentName}')),
                            );
                          },
                          child: const Text('RESUME SESSION'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            provider.importNewTournament(data);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('New tournament created with calculated handicaps!')),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('START NEW'),
                        ),
                      ],
                    ),
                  ).then((_) {
                    if (context.mounted) Navigator.pop(context);
                  });
                } else {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid Tournament File.')),
                  );
                }
              }
            },
          ),
          const Divider(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final d = int.tryParse(durationController.text) ?? 20;
              final r = int.tryParse(roundsController.text) ?? 4;
              settings.updateSettings(d, r, r1PairingMode: r1Mode);
              Navigator.pop(context);
            },
            child: const Text(
              'SAVE',
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final settings = context.watch<SettingsProvider>();
    final players = provider.players;

    // Sync controller if provider value changes externally (e.g. via import)
    if (_tournamentNameController.text != provider.tournamentName) {
      _tournamentNameController.text = provider.tournamentName;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tournament Check-in',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'All Knighters Chess Club',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _showSettings(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Tournament Name',
                labelStyle: const TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              controller: _tournamentNameController,
              onChanged: (val) => provider.setTournamentName(val),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Player Name',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _addPlayer(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _handicapController,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: 'Hcp',
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _addPlayer,
                  child: Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: players.length,
              itemBuilder: (context, index) {
                final player = players[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blueAccent.withValues(
                          alpha: 0.1,
                        ),
                        child: Text(
                          player.name[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              player.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (player.handicap != 0)
                              GestureDetector(
                                onTap: () {
                                  final ctrl = TextEditingController(text: player.handicap.toString());
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text('Edit Handicap for ${player.name}'),
                                      content: TextField(
                                        controller: ctrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(labelText: 'Handicap (+/-)'),
                                        autofocus: true,
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('CANCEL'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            final hcp = double.tryParse(ctrl.text) ?? player.handicap;
                                            provider.updatePlayerHandicap(player.id, hcp);
                                            Navigator.pop(ctx);
                                          },
                                          child: const Text('SAVE', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: Text(
                                  'Handicap: ${player.handicap > 0 ? '+' : ''}${player.handicap.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.blueAccent,
                                    fontSize: 12,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_sweep_outlined,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        onPressed: () => provider.removePlayer(player.id),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D0D),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOURNAMENT READY',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${players.length} Players Registered',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (players.length >= 2)
                      ElevatedButton(
                        onPressed: () =>
                            provider.startTournament(settings.roundDuration, r1pMode: settings.round1PairingMode),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'PROCEED',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      const Text(
                        'Min 2 to start',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
