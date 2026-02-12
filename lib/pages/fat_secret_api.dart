import 'package:http/http.dart' as http;
import 'dart:convert';

class FatSecretApi {
  // Proxy URL
  final String proxyUrl = 'https://fatsecret-proxy.onrender.com';

  // Maximum number of retries for the IP error
  final int maxRetries = 3;

  // Autocomplete request using the proxy
  Future<Foods> foodsSearch(String query) async {
    int attempt = 0;

    while (attempt < maxRetries) {
      attempt++;
      try {
        // Build the request URL with query parameters
        final Uri requestUri = Uri.parse(
            '$proxyUrl/foods/search/v1?search_expression=$query&max_results=10&format=json');

        // Make the GET request to the proxy
        final response = await http.get(
          requestUri,
          headers: {
            'Content-Type': 'application/json', // Optional: Set content type
          },
        );

        // Check the response status
        if (response.statusCode == 200) {
          final Map<String, dynamic> jsonResponse = json.decode(response.body);
          return Foods.fromJson(
              jsonResponse['foods']); // Access the 'foods' key
        } else {
          // Parse the error response
          final errorResponse = json.decode(response.body);
          if (errorResponse['error']?['code'] == 21) {
            await Future.delayed(Duration(seconds: 1)); // Add a short delay
            continue; // Retry the request
          } else {
            throw Exception(
                'Failed to load data: ${response.statusCode} ${response.body}');
          }
        }
      } catch (e) {
        if (attempt >= maxRetries) {
          throw Exception('Maximum retries reached. Error: $e');
        }
        await Future.delayed(Duration(seconds: 1)); // Add a short delay
      }
    }

    throw Exception('Failed to load data after $maxRetries attempts.');
  }
}

class Foods {
  final List<Food> food;

  Foods({required this.food});

  factory Foods.fromJson(Map<String, dynamic> json) {
    var foodList = json['food'] as List;
    List<Food> foods = foodList.map((i) => Food.fromJson(i)).toList();

    return Foods(food: foods);
  }
}

class Food {
  final String foodId;
  final String foodName;
  final String foodDescription;
  final String foodType;
  final String foodUrl;
  final String? brandName; // Optional, as it may not always be present

  Food({
    required this.foodId,
    required this.foodName,
    required this.foodDescription,
    required this.foodType,
    required this.foodUrl,
    this.brandName,
  });

  factory Food.fromJson(Map<String, dynamic> json) {
    return Food(
      foodId: json['food_id'],
      foodName: json['food_name'],
      foodDescription: json['food_description'],
      foodType: json['food_type'],
      foodUrl: json['food_url'],
      brandName: json['brand_name'],
    );
  }
}
