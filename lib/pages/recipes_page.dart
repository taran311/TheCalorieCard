import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/pages/add_recipe_page.dart';
import 'package:namer_app/pages/home_page.dart';
import 'package:namer_app/pages/menu_page.dart';

class RecipesPage extends StatefulWidget {
  final bool hideNav;

  const RecipesPage({super.key, this.hideNav = false});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  bool _deleteMode = false;

  Future<void> _deleteRecipe(String recipeId) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Delete the recipe itself from the recipes collection
      await firestore.collection('recipes').doc(recipeId).delete();

      if (mounted) {
        setState(() {
          _deleteMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recipe deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting recipe: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('recipes')
            .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No recipes yet.'));
          }

          final recipes = snapshot.data!.docs;
          // Sort by created_at descending
          recipes.sort((a, b) {
            final timeA = a['created_at'] as Timestamp?;
            final timeB = b['created_at'] as Timestamp?;
            if (timeA == null || timeB == null) return 0;
            return timeB.compareTo(timeA);
          });

          return Column(
            children: [
              Container(
                color: Colors.grey.shade100,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recipe Name',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 80,
                      child: Text(
                        'Calories',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: recipes.length,
                  itemBuilder: (context, index) {
                    final recipe = recipes[index];
                    final totalCalories = recipe['total_calories'] as num? ?? 0;

                    return GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddRecipePage(recipeId: recipe.id),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                                color: Colors.grey.shade300, width: 1),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          recipe['name'] ?? 'Recipe',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                        if (recipe['serving_size'] != null &&
                                            (recipe['serving_size'] as String)
                                                .isNotEmpty)
                                          Text(
                                            '(${recipe['serving_size']})',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 80,
                                    child: Text(
                                      '${totalCalories.toStringAsFixed(0)} kcal',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF6366F1),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (_deleteMode)
                                    GestureDetector(
                                      onTap: () async {
                                        await _deleteRecipe(recipe.id);
                                      },
                                      child: Icon(
                                        Icons.delete_outline,
                                        color: Colors.red.shade400,
                                        size: 24,
                                      ),
                                    ),
                                  // Removed dropdown icon (no inline breakdown)
                                ],
                              ),
                              // No inline breakdown; tapping navigates to edit screen
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'recipes-add',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddRecipePage()),
              );
            },
            backgroundColor: Colors.green.shade400,
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'recipes-delete',
            onPressed: () {
              setState(() {
                _deleteMode = !_deleteMode;
              });
            },
            backgroundColor:
                _deleteMode ? Colors.red.shade600 : Colors.red.shade400,
            child: Icon(_deleteMode ? Icons.close : Icons.delete_outline),
          ),
        ],
      ),
      bottomNavigationBar: widget.hideNav
          ? null
          : Container(
              color: Colors.white,
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MenuPage(),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                                color: Colors.grey.shade200, width: 1),
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.person, size: 24),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const HomePage()),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                                color: Colors.grey.shade200, width: 1),
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.credit_card, size: 24),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      child: const Center(
                        child: Icon(Icons.restaurant,
                            size: 24, color: Color(0xFF6366F1)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
