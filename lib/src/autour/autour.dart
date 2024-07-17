import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:geolocator/geolocator.dart';

import 'database_helper.dart';

const String BACKEND_URL = "http://vps-433a4dd6.vps.ovh.net:8080";
const String API_KEY_GEOCODE = "";

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
  final dbHelper = DatabaseHelper();

  late PageController _pageViewController;
  late TabController _tabController;
  int _currentPageIndex = 0;
  bool _searchOngoing = false;
  List<Place> _places = [];
  String _lastKnownPosition = "";

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

  Future<List<Place>> _searchNearby(String filters) async {
    print("[+] Getting places around...");

    Map<String, dynamic> filtersJson = _formatFilters(filters);

    // TODO: don't call the backend if on offline mode

    List<Place> places = await _getPlaces();

    // Add all the places to the local db
    for (final place in places) {
      String loc = place.location.toString();
      print("[+] Adding place with location: $loc");
      _insertPlace(place);
    }

    // TODO: apply filter to places from local db, return only places to display

    return places;
  }

  /// Call the backend to get the list of places
  /// Returns JSON data parseable into Place objects.
  Future<List<Place>> _getPlaces() async {
    List<Place> places = [];
    // 24 rue saint jacque, paris 5
    final lat = 48.85197352486211;
    final lng = 2.346265903974507;
    //final lat = 48.861887595139585;
    //final lng = 2.351825150146367;

    final response = await http.post(
      Uri.parse(BACKEND_URL+'/get-places-dev'),
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

    return places;
  }

  /// Convert coordinates to human-readable address
  Future<String> _reverseGeocode(Location currentPosition) async {
    String address;

    final url = Uri.https(
      'geocode.maps.co',
      '/reverse',
      {
        'lat': currentPosition.lat.toString(),
        'lon': currentPosition.lng.toString(),
        'api_key': API_KEY_GEOCODE,
      },
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      // Parse JSON to Place object
      final Map<String, dynamic> jsonResponse =
              json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      address = jsonResponse['display_name'];
    } else {
      String coords = currentPosition.toString();
      throw Exception('[-] Failed to reverse geocode: $coords');
    }

    return address;
  }

  /// Determine the current position of the device.
  ///
  /// When the location services are not enabled or permissions
  /// are denied the `Future` will return an error.
  Future<Location> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    // Check permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.');
    }

    Position pos = await Geolocator.getCurrentPosition();

    Location currentPos = Location(
      lat: pos.latitude,
      lng: pos.longitude,
    );

    return currentPos;
  }

  /// Formats a string to a valide json string and returns a json object.
  Map<String, dynamic> _formatFilters(String filters) {
    // Put double quotes around keys
    String jsonString = filters.replaceAllMapped(RegExp(r'(\w+):'), (match) => '"${match[1]}":');

    // Put double quotes around values inside arrays
    jsonString = jsonString.replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (match) {
      String content = match[1] ?? "{}";
      List<String> values = content.split(',').map((v) => v.trim()).toList();
      String quotedValues = values.map((v) => '"$v"').join(', ');
      return '[$quotedValues]';
    });

    Map<String, dynamic> filtersJson = json.decode(jsonString);

    return filtersJson;
  }

  void _showFilters(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AutourFilters(
          searchBtnCallback: (filters) async {
            List<Place> places = await _searchNearby(filters);
            setState(() {
              _places = places;
            });
          }
        );
      }
    );
  }

  Future<String> _getCurrentAddress() async {
    Location currentPosition = await _determinePosition();
    String currentAddress = await _reverseGeocode(currentPosition);

    return currentAddress;
  }

  /// Open a dialogbox to show the address for the current position.
  void _showCurrentPosition(BuildContext context) async {
    if (_lastKnownPosition == "") {
      String currentAddress = await _getCurrentAddress();
      _lastKnownPosition = currentAddress;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Last known position'),
          content: Text(_lastKnownPosition),
          actions: <Widget>[
            TextButton(
              child: const Text('Update'),
              onPressed: () {
                _getCurrentAddress().then((value) {
                  setState(() {
                    _lastKnownPosition = value;
                  });
                });
              },
            ),
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      }
    );
  }

  Future<void> _insertPlace(Place place) async {
    await dbHelper.insertPlace({
      'formatted_address': place.formattedAddress,
      'google_maps_uri': place.googleMapsUri,
      'primary_type': place.primaryType,
      'display_name': place.displayName,
      'location': json.encode(place.location.toJson()),
      'current_opening_hours': json.encode(place.currentOpeningHours?.toJson()),
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final nbItems = 10;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Container(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    iconSize: 30,
                    icon: const Icon(Icons.pin_drop),
                    onPressed: () => _showCurrentPosition(context),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),

              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  child: ElevatedButton(
                    onPressed: () => _showFilters(context),
                    child: Text('Autour'),
                  ),
                ),
              ),

              Expanded(
                child: Container(
                  alignment: Alignment.center,
                ),
              ),

            ],
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
                          fontWeight: FontWeight.bold,
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
    return Place(
      formattedAddress: json['formattedAddress'] ?? "Unknown address",
      googleMapsUri: json['googleMapsUri'] ?? "Unknown Google Maps Uri",
      primaryType: json['primaryType'] ?? "Unknown primary type",
      displayName: json['displayName']['text'] ?? "displayName",
      location: json['location'] != null
        ? Location.fromJson(json['location'])
        : Location(lat: -360, lng: -360),
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

  Map<String, dynamic> toJson() {
    return {
      'latitude': lat,
      'longitude': lng
    };
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
    final List<dynamic> periodsJson = json['periods'];
    return OpeningHours(
      openNow: json['openNow'],
      periods: periodsJson.map((period) => Period.fromJson(period)).toList(),
      weekdayDescriptions: List<String>.from(json['weekdayDescriptions']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'openNow': openNow,
      'periods': periods.map((period) => period.toJson()).toList(),
      'weekdayDescriptions': weekdayDescriptions
    };
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

  Map<String, dynamic> toJson() {
    return {
      'open': open.toJson(),
      'close': close.toJson()
    };
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

  Map<String, dynamic> toJson() {
    return {
      'day': day,
      'hour': hour,
      'minute': minute
    };
  }
}

class AutourFilters extends StatelessWidget {
  final _formKey = GlobalKey<FormBuilderState>();
  final Function(String) searchBtnCallback;

  AutourFilters({
    required this.searchBtnCallback,
  });

  List<String> _days = ['M', 'T', 'W', 'Th', 'F', 'S', 'Su'];
  List<String> _hours = [
    "00:00", "00:30", "01:00", "01:30", "02:00", "02:30", "03:00", "03:30",
    "04:00", "04:30", "05:00", "05:30", "06:00", "06:30", "07:00", "07:30",
    "08:00", "08:30", "09:00", "09:30", "10:00", "10:30", "11:00", "11:30",
    "12:00", "12:30", "13:00", "13:30", "14:00", "14:30", "15:00", "15:30",
    "16:00", "16:30", "17:00", "17:30", "18:00", "18:30", "19:00", "19:30",
    "20:00", "20:30", "21:00", "21:30", "22:00", "22:30", "23:00", "23:30",
  ];

  void _handleButtonPressed() {
    _formKey.currentState?.validate();
    String? filters = _formKey.currentState?.instantValue.toString();
    searchBtnCallback(filters ?? "{}");
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Filters"),
      content: FormBuilder(
        key: _formKey,
        child: Column(
          children: [
            // Display current location
            Text("Current location goes here"),

            // Open on
            FormBuilderCheckboxGroup<String>(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                  labelText: 'Open on'),
              name: 'days',
              initialValue: ['M', 'T', 'W', 'Th', 'F', 'S', 'Su'],
              options: _days
                  .map(
                    (day) => FormBuilderFieldOption(value: day)
                  ).toList(),
              //onChanged: _onChanged,
              separator: const VerticalDivider(
                width: 10,
                thickness: 5,
                color: Colors.red,
              ),
            ),

            // Open before
            FormBuilderDropdown<String>(
              name: 'open_before',
              decoration: InputDecoration(
                labelText: 'Open before',
              ),
              items: _hours
                  .map((hour) => DropdownMenuItem(
                        value: hour,
                        child: Text(hour),
                      ))
                  .toList(),
            ),

            // Open after
            FormBuilderDropdown<String>(
              name: 'open_after',
              decoration: InputDecoration(
                labelText: 'Open after',
              ),
              items: _hours
                  .map((hour) => DropdownMenuItem(
                        value: hour,
                        child: Text(hour),
                      ))
                  .toList(),
            ),

            // Open now
            FormBuilderCheckbox(
              name: 'open_now',
              title: const Text('Open now'),
              initialValue: false,
            ),

            // TODO: allow to set the radius of the search

          ]
        )
      ),

      actions: <Widget>[
        TextButton(
          style: TextButton.styleFrom(
            textStyle: Theme.of(context).textTheme.labelLarge,
          ),
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          style: TextButton.styleFrom(
            textStyle: Theme.of(context).textTheme.labelLarge,
          ),
          child: const Text('Search'),
          onPressed: () {
            _handleButtonPressed();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
