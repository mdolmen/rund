import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

const Map<String, int> dayNamesIndex = {
  'Monday': 0,
  'Tuesday': 1,
  'Wednesday': 2,
  'Thursday': 3,
  'Friday': 4,
  'Saturday': 5,
  'Sunday': 6,
};

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
    // 24 rue saint jacque, paris 5
    final lat = 48.85197352486211;
    final lng = 2.346265903974507;
    //final lat = 48.861887595139585;
    //final lng = 2.351825150146367;

    final response = await http.post(
      Uri.parse('http://127.0.0.1:8080/get-places'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode({
        'includedTypes': ['restaurant'],
        'rankPreference': 'distance',
        'locationRestriction': {
          'circle': {
            'center': {
              'latitude': lat,
              'longitude': lng,
            },
            'radius': 500.0,
          },
        },
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
  int _todayIdx = 0;

  PlaceListItem({
    required this.placeData,
  });

  @override
  void initState() {
    _todayIdx = dayNamesIndex[getDayName()] ?? -1;
  }

  String getDayName() {
    return DateFormat('EEEE').format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final String? currentOpeningHours =
            placeData.currentOpeningHours?.weekdayDescriptions[_todayIdx];
    final bool isOpen = placeData.currentOpeningHours?.openNow ?? false;
    final IconData isOpenIcon = isOpen ? Icons.check_circle : Icons.cancel;
    final Color isOpenColor = isOpen ? Colors.green : Colors.red;

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
                        style: TextStyle(
                          fontSize: 16,
                        ),
                      ),
                      Container(height: 5),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: "  ",
                            ),
                            WidgetSpan(
                              child: Icon(isOpenIcon, size: 14, color: isOpenColor),
                            ),
                            TextSpan(
                              text: " " + (currentOpeningHours ?? "No hours available"),
                              style: TextStyle(
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(height: 5),
                      Text(
                        "  " + placeData.primaryType,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    IconButton(
                      iconSize: 44,
                      icon: const Icon(Icons.assistant_navigation),
                      onPressed: () {
                        print("Open in maps");
                      },
                      padding: EdgeInsets.zero,
                    ),
                    Container(height: 5),
                    Text(
                      "100m",
                      style: TextStyle(
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
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

class Place {
  final String formattedAddress;
  final String googleMapsUri;
  final String primaryType;
  final String displayName;
  final Location location;
  final OpeningHours? currentOpeningHours;

  const Place({
    required this.formattedAddress,
    required this.googleMapsUri,
    required this.primaryType,
    required this.displayName,
    required this.location,
    required this.currentOpeningHours,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    //print(json);
    return Place(
      formattedAddress: json['formattedAddress'],
      googleMapsUri: json['googleMapsUri'],
      primaryType: json['primaryType'],
      displayName: json['displayName']['text'],
      location: Location.fromJson(json['location']),
      currentOpeningHours: json['currentOpeningHours'] != null
        ? OpeningHours.fromJson(json['currentOpeningHours'])
        : null,
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

class OpeningHours {
  final bool openNow;
  final List<Period> periods;
  final List<String> weekdayDescriptions;

  OpeningHours({
    required this.openNow,
    required this.periods,
    required this.weekdayDescriptions,
  });

  factory OpeningHours.fromJson(Map<String, dynamic> json) {
    print(json);
    final List<dynamic> periodsJson = json['periods'];
    return OpeningHours(
      openNow: json['openNow'],
      periods: periodsJson.map((period) => Period.fromJson(period)).toList(),
      weekdayDescriptions: List<String>.from(json['weekdayDescriptions']),
    );
  }
}

class Period {
  final Hour open;
  final Hour close;

  Period({
    required this.open,
    required this.close
  });

  factory Period.fromJson(Map<String, dynamic> json) {
    return Period(
      open: Hour.fromJson(json['open']),
      close: Hour.fromJson(json['close']),
    );
  }
}

class Hour {
  final int day;
  final int hour;
  final int minute;

  Hour({
    required this.day,
    required this.hour,
    required this.minute,
  });

  factory Hour.fromJson(Map<String, dynamic> json) {
    return Hour(
      day: json['day'],
      hour: json['hour'],
      minute: json['minute'],
    );
  }
}
