import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:http/http.dart' as http;

class AutourScreen extends StatefulWidget {
  const AutourScreen({super.key});

  @override
  State<AutourScreen> createState() => _AutourScreen();
}

class _AutourScreen extends State<AutourScreen> with TickerProviderStateMixin {
  late PageController _pageViewController;
  late TabController _tabController;
  int _currentPageIndex = 0;
  bool _searchOngoing = false;
  List<Place> _places = [];

  @override
  void initState() {
    super.initState();
    _pageViewController = PageController();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    super.dispose();
    _pageViewController.dispose();
    _tabController.dispose();
  }

  void searchAround() async {
    print("[+] Getting places around...");
    List<Place> places = await getPlaces();

    setState(() {
      int len = places.length;
      _places = places;
    });
  }

  /// Call the backend to get the list of places
  /// Returns JSON data parseable into Place objects.
  Future<List<Place>> getPlaces() async {
    List<Place> places = [];

    final response = await http.post(
      Uri.parse('http://127.0.0.1:8080/get-places'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'address': '123 somewhere',
      }),
    );

    if (response.statusCode == 200) {
      // Parse JSON to Place object
      final List<dynamic> placesJson =
              json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      places = placesJson.map((json) => Place.fromJson(json)).toList();
    } else {
      throw Exception('[-] Failed to get places.');
    }
    print(places.length);

    return places;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final nbItems = 10;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: ElevatedButton(
              onPressed: () => searchAround(),
              child: Text('Autour'),
            ),
          ),
          pinned: true,
        ),

        SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              return PlaceListItem(placeData: _places[index]);
            },
            childCount: _places.length,
          ),
        ),

        if (_searchOngoing)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: LoadingAnimationWidget.threeRotatingDots(
                color: Colors.deepPurple.shade100,
                size: 50,
              ),
            ),
          ),
      ]
    );
  }
}

class PlaceListItem extends StatelessWidget {
  final Place placeData;

  const PlaceListItem({
    required this.placeData,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                //Image.asset(
                //  "assets/images/flutter_logo.png",
                //  height: 100,
                //  width: 100,
                //  fit: BoxFit.cover,
                //),

                // Spacing between the image and the text
                Container(width: 20),

                // Take the rest of the space
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(height: 5),
                      Text(
                        placeData.displayName,
                        //style: MyTextSample.title(context)!.copyWith(
                        //  color: MyColorsSample.grey_80,
                        //),
                      ),
                      Container(height: 5),
                      Text(
                        "Sub title",
                        //style: MyTextSample.body1(context)!.copyWith(
                        //  color: Colors.grey[500],
                        //),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

  }
}

class Place {
  final String formattedAddress;
  final String googleMapsUri;
  final String primaryType;
  final String displayName;
  final Location location;

  const Place({
    required this.formattedAddress,
    required this.googleMapsUri,
    required this.primaryType,
    required this.displayName,
    required this.location,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    print(json);
    return Place(
      formattedAddress: json['formattedAddress'],
      googleMapsUri: json['googleMapsUri'],
      primaryType: json['primaryType'],
      displayName: json['displayName']['text'],
      location: Location.fromJson(json['location']),
    );
  }
}

class Location {
  final double lat;
  final double lng;

  Location({required this.lat, required this.lng});

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      lat: json['latitude'],
      lng: json['longitude'],
    );
  }

  @override
  String toString() {
    return 'Location(lat: $lat, lng: $lng)';
  }
}
