import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HiscoresPage extends StatefulWidget {
  const HiscoresPage({Key? key}) : super(key: key);

  @override
  State<HiscoresPage> createState() => _HiscoresPageState();
}

class _HiscoresPageState extends State<HiscoresPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<String, int>> _getDaysLoggedThisMonth(
      List<String> friendIds) async {
    final Map<String, int> leaderboard = {};
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return leaderboard;

    // Include current user
    final allUserIds = [currentUser.uid, ...friendIds];

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    for (final userId in allUserIds) {
      // Get user email
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final email = userDoc.data()?['email'] as String? ?? 'Unknown';

      // Count days logged this month (only finished logs)
      int daysLogged = 0;
      DateTime checkDate = DateTime(now.year, now.month, now.day);

      while (
          checkDate.isAfter(startOfMonth.subtract(const Duration(days: 1)))) {
        final key =
            '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
        final docSnapshot = await FirebaseFirestore.instance
            .collection('daily_logs')
            .doc('${userId}_$key')
            .get();

        if (docSnapshot.exists) {
          final data = docSnapshot.data();
          final finished = data?['finished'] as bool? ?? false;
          if (finished) {
            daysLogged++;
          }
        }

        checkDate = checkDate.subtract(const Duration(days: 1));
        if (daysLogged > 31) break; // Safety limit
      }

      leaderboard[email] = daysLogged;
    }

    return leaderboard;
  }

  Future<Map<String, double>> _getHighestProteinThisWeek(
      List<String> friendIds) async {
    final Map<String, double> leaderboard = {};
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return leaderboard;

    // Include current user
    final allUserIds = [currentUser.uid, ...friendIds];

    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfWeekDay =
        DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final endOfWeek = startOfWeekDay.add(const Duration(days: 7));

    for (final userId in allUserIds) {
      // Get user email
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final email = userDoc.data()?['email'] as String? ?? 'Unknown';

      // Get all food items this week
      final foodDocs = await FirebaseFirestore.instance
          .collection('user_food')
          .where('user_id', isEqualTo: userId)
          .get();

      double totalProtein = 0;
      for (final doc in foodDocs.docs) {
        final data = doc.data();
        DateTime? docDate;

        final timeAdded = data['time_added'];
        final createdAt = data['created_at'];

        if (timeAdded is Timestamp) {
          docDate = timeAdded.toDate();
        } else if (timeAdded is DateTime) {
          docDate = timeAdded;
        } else if (createdAt is Timestamp) {
          docDate = createdAt.toDate();
        } else if (createdAt is DateTime) {
          docDate = createdAt;
        }

        if (docDate != null &&
            !docDate.isBefore(startOfWeekDay) &&
            docDate.isBefore(endOfWeek)) {
          totalProtein += (data['food_protein'] as num?)?.toDouble() ?? 0;
        }
      }

      leaderboard[email] = totalProtein;
    }

    return leaderboard;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view hiscores')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          '🏆 Hiscores',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.6),
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.calendar_month, size: 20),
              text: 'Days Logged',
            ),
            Tab(
              icon: Icon(Icons.fitness_center, size: 20),
              text: 'Protein This Week',
            ),
          ],
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final List<dynamic> friends = userData?['friends'] ?? [];
          final List<String> friendIds = friends.cast<String>();

          if (friendIds.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.group_off,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Friends Yet',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add friends to see leaderboards!',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // Days Logged This Month Tab
              _buildDaysLoggedLeaderboard(friendIds),
              // Highest Protein This Week Tab
              _buildProteinLeaderboard(friendIds),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDaysLoggedLeaderboard(List<String> friendIds) {
    return FutureBuilder<Map<String, int>>(
      future: _getDaysLoggedThisMonth(friendIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        final sortedEntries = data.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.orange.shade400,
                  Colors.deepOrange.shade600,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.calendar_month, color: Colors.white, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Days Logged This Month',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...sortedEntries.map((entry) {
                  final rank = sortedEntries.indexOf(entry) + 1;
                  final maxValue = sortedEntries.first.value;
                  final percentage =
                      maxValue > 0 ? entry.value / maxValue : 0.0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: rank <= 3
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.7),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '$rank',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: rank == 1
                                        ? Colors.amber.shade700
                                        : rank == 2
                                            ? Colors.grey.shade700
                                            : rank == 3
                                                ? Colors.brown.shade700
                                                : Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.key.split('@')[0],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: percentage,
                                            backgroundColor:
                                                Colors.white.withOpacity(0.3),
                                            valueColor:
                                                const AlwaysStoppedAnimation<
                                                    Color>(Colors.white),
                                            minHeight: 8,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '${entry.value}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProteinLeaderboard(List<String> friendIds) {
    return FutureBuilder<Map<String, double>>(
      future: _getHighestProteinThisWeek(friendIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        final sortedEntries = data.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.red.shade400,
                  Colors.pink.shade600,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.fitness_center, color: Colors.white, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Highest Protein This Week',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...sortedEntries.map((entry) {
                  final rank = sortedEntries.indexOf(entry) + 1;
                  final maxValue = sortedEntries.first.value;
                  final percentage =
                      maxValue > 0 ? entry.value / maxValue : 0.0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: rank <= 3
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.7),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '$rank',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: rank == 1
                                        ? Colors.amber.shade700
                                        : rank == 2
                                            ? Colors.grey.shade700
                                            : rank == 3
                                                ? Colors.brown.shade700
                                                : Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.key.split('@')[0],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: percentage,
                                            backgroundColor:
                                                Colors.white.withOpacity(0.3),
                                            valueColor:
                                                const AlwaysStoppedAnimation<
                                                    Color>(Colors.white),
                                            minHeight: 8,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '${entry.value.toStringAsFixed(0)}g',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }
}
