import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_launcher/map_launcher.dart';

import 'database_helper.dart';
import 'place_types.dart';

const String BACKEND_URL = "http://vps-433a4dd6.vps.ovh.net:8080";
//const String BACKEND_URL = "http://127.0.0.1:8080";

const Map<String, int> dayNamesIndex = {
  'Sunday': 0,
  'Monday': 1,
  'Tuesday': 2,
  'Wednesday': 3,
  'Thursday': 4,
  'Friday': 5,
  'Saturday': 6,
};

const Map<String, int> dayNamesShortIndex = {
  'Su': 0,
  'M': 1,
  'T': 2,
  'W': 3,
  'Th': 4,
  'F': 5,
  'S': 6,
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
  List<Place> _placesShown = [];
  Location _lastKnownCoords = Location(lat:-360, lng:-360); // unvalid gps coords
  String _lastKnownPosition = "";
  bool _positionHasChanged = true;
  bool _online = true;

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

  int _timeStrToMinutes(String time) {
    List<String> parts = time.split(':');
    int hours = int.parse(parts[0]);
    int minutes = int.parse(parts[1]);
    return hours * 60 + minutes;
  }

  bool _applyFilters(String today, String filters, Place place) {
    Map<String, dynamic> filtersJson = _formatStrToJson(filters, true);
    print(filtersJson);
    bool f_open_on = true;
    bool f_open_before = true;
    bool f_open_after = true;
    bool f_open_today = true;
    bool f_open_now = true;
    List<String> days = [];
    int todayIdx = dayNamesIndex[today] ?? -1;
    DateTime now = DateTime.now();
    int currentTime = now.hour * 60 + now.minute;
    List<Period> periods = place.currentOpeningHours?.periods ?? [];
    print(periods);

    // Get today short version
    String todayShort = "";
    if (today == "Thursday" || today == "Sunday") {
      todayShort = today.substring(0, 2);
    }
    else {
      todayShort = today[0];
    }

    // days might be used by multiple filter, get them once here
    if (filtersJson["days"] != null) {
      f_open_on = false;
      days = filtersJson['days'].cast<String>();
    }

    // Open on
    for (final day in days) {
      if (f_open_on)
        break;

      int dayIdx = dayNamesShortIndex[day] ?? -1;

      for (final p in periods) {

        // If there is a period for this day, then the place is open at some
        // point on this day.
        if (p.open.day == dayIdx) {
          f_open_on = true;
          break;
        }
      }
    }

    // Open before
    if (filtersJson['open_before'] != null) {
      f_open_before = false;

      int open_before = _timeStrToMinutes(filtersJson['open_before']);

      for (final period in periods) {
        if (f_open_before)
          break;

        for (final day in days) {
          // day is in list of selected days
          int dayIdx = dayNamesShortIndex[day] ?? -1;

          if (period.open.day == dayIdx) {
            int openAt = period.open.hour * 60 + period.open.minute;
            if (openAt <= open_before) {
              f_open_before = true;
              break;
            }
          }
        }

        if (filtersJson["open_today"] != null && period.open.day == todayIdx) {
          // day is today
          int openAt = period.open.hour * 60 + period.open.minute;
          if (openAt <= open_before) {
            f_open_before = true;
            break;
          }
        }
        else if (filtersJson['days'] == null) {
          // neither days nor today filter are selected, apply on all days
          int openAt = period.open.hour * 60 + period.open.minute;
          if (openAt <= open_before) {
            f_open_before = true;
            break;
          }
        }
      }
    }

    // Open after
    if (filtersJson['open_after'] != null) {
      f_open_after = false;

      int open_after = _timeStrToMinutes(filtersJson['open_after']);

      for (final period in periods) {
        if (f_open_after)
          break;

        for (final day in days) {
          // day is in list of selected days
          int dayIdx = dayNamesShortIndex[day] ?? -1;

          if (period.open.day == dayIdx) {
            int closeAt = period.close.hour * 60 + period.close.minute;
            if (closeAt >= open_after) {
              f_open_after = true;
              break;
            }
          }
        }

        if (filtersJson["open_today"] != null && period.open.day == todayIdx) {
          // day is today
          int closeAt = period.close.hour * 60 + period.close.minute;
          if (closeAt >= open_after) {
            f_open_after = true;
            break;
          }
        }
        else if (filtersJson['days'] == null) {
          // neither days nor today filters are selected, apply on all days
          int closeAt = period.close.hour * 60 + period.close.minute;
          if (closeAt >= open_after) {
            f_open_after = true;
            break;
          }
        }
      }
    }

    // Open today
    if (filtersJson["open_today"] != null) {
      f_open_today = false;

      for (final period in periods) {
        if (period.open.day == todayIdx) {
          f_open_today = true;
          break;
        }
      }
    }

    // Open now
    if (filtersJson["open_now"] != null) {
      f_open_now = false;

      for (final period in periods) {
        if (period.open.day == todayIdx) {
          int openAt = period.open.hour * 60 + period.open.minute;
          int closeAt = period.close.hour * 60 + period.close.minute;
          if (currentTime > openAt && currentTime < closeAt) {
            f_open_now = true;
            break;
          }
        }
      }
    }

    print("DEBUG: f_open_on: $f_open_on, f_open_today: $f_open_today, f_open_now: $f_open_now, f_open_before: $f_open_before, f_open_after: $f_open_after;\n");
    print("\n");
    return f_open_on && f_open_today && f_open_now && f_open_before && f_open_after;
  }

  Future<List<Place>> _searchNearby(String today, String filters) async {
    print("[+] Getting places around...");
    Map<String, dynamic> filtersJson = _formatStrToJson(filters, false);

    String type = filtersJson["types"] ?? "";
    print("DEBUG: (_searchNearby) type = $type");

    _searchOngoing = true;
    setState(() {});

    List<Place> places = [];

    // TODO: don't call the backend if on offline mode

    places = await _getPlaces(type);
    // TODO: requires adding a function to get places from local db
    //if (_positionHasChanged) {
    //  places = await _getPlaces();
    //  _positionHasChanged = false;
    //  print("DEBUG: getting places");
    //}
    //else {
    //  print("DEBUG: already got places for that position");
    //  print("DEBUG: len(_places) = ${_places.length}");
    //  places = _places;
    //}

    // Add all the places to the local db
    for (final place in places) {
      // TODO: don't insert if offline mode is on
      _insertPlace(place);

      //if (_applyFilters(today, filters, place) == true)
      //  filteredPlaces.add(place);
    }

    _searchOngoing = false;
    setState(() {});

    return places;
  }

  /// Call the backend to get the list of places
  /// Returns JSON data parseable into Place objects.
  Future<List<Place>> _getPlaces(String type) async {
    List<Place> places = [];

    if (type == "") {
      print("[-] (_getPlaces) Error: empty type when getting places");
    }

    List<String> subtypes = placeTypes[type] ?? [];
    print("DEBUG: (_getPlaces) $subtypes");

    // TODO:
    //  - pass positionHasChanged in parameter
    //  - if not positionHasChanged, do the same as offline mode, aka get places
    //  from local db (don't call the backend API)

    if (_lastKnownCoords.lat == -360 && _lastKnownCoords.lng == -360) {
      String currentAddress = await _getCurrentAddress();
      _lastKnownPosition = currentAddress;
    }

    final response = await http.post(
      Uri.parse(BACKEND_URL+'/get-places'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode({
        'includedTypes': subtypes,
        'rankPreference': 'distance',
        'locationRestriction': {
          'circle': {
            'center': {
              'latitude': _lastKnownCoords.lat,
              'longitude': _lastKnownCoords.lng,
            },
            'radius': 500.0,
          },
        },
        'placesType': type,
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

  List<Place> _filterPlaces(String today, String filters) {
    List<Place> filteredPlaces = [];

    print("DEBUG: (_filterPlaces) today = $today, filters = $filters");
    print("DEBUG: (_filterPlaces) len _places = ${_places.length}");

    for (final place in _places) {
      if (_applyFilters(today, filters, place) == true)
        filteredPlaces.add(place);
    }

    print("DEBUG: (_filterPlaces) len fp = ${filteredPlaces.length}");

    return filteredPlaces;
  }

  /// Convert coordinates to human-readable address
  Future<String> _reverseGeocode(Location currentPosition) async {
    String address = "";

    final response = await http.post(
      Uri.parse(BACKEND_URL+'/reverse-geocode'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode({
        'latitude': currentPosition.lat.toString(),
        'longitude': currentPosition.lng.toString(),
      }),
    );

    if (response.statusCode == 200) {
      // Parse JSON to Place object
      final Map<String, dynamic> jsonResponse =
              json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      address = jsonResponse['display_name'] ?? 'Unknown address';
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

  /// Formats a string to a valid json string and returns a json object.
  Map<String, dynamic> _formatStrToJson(String filters, bool isFilters) {
    String jsonString = filters;

    // Put double quotes around unquoted keys
    jsonString = jsonString.replaceAllMapped(
      RegExp(r'(?<!")([a-zA-Z_]\w*)(?=\s*:)'),
      (match) => '"${match[1]}"'
    );

    // Do this to fully transform the string. In the case of the filters we
    // don't want to add double quotes around 'null' string to keep it a boolean
    // instead of making it a string.
    if (isFilters == false) {
      // Put double quotes around unquoted string values
      jsonString = jsonString.replaceAllMapped(
        RegExp(r'(?<=:\s?)([a-zA-Z][a-zA-Z\s]*)(?=[,\}\]])'),
        (match) => '"${match[1]}"'
      );
    }

    // Put double quotes around strings in arrays
    jsonString = jsonString.replaceAllMapped(
      RegExp(r'(?<=\[)([^"\]]+)(?=\])'),
      (match) {
        // Split the array contents, trim, and quote each value
        String content = match[1] ?? "";
        List<String> values = content.split(',').map((v) => v.trim()).toList();
        String quotedValues = values.map((v) => '"$v"').join(', ');
        return quotedValues;
      }
    );

    // Put double quotes around time values (e.g., 03:30)
    jsonString = jsonString.replaceAllMapped(
      RegExp(r'(?<=:\s?)(\d{2}:\d{2})(?=[,\}\]])'),
      (match) => '"${match[1]}"'
    );

    print(jsonString);
    Map<String, dynamic> filtersJson = json.decode(jsonString);
    print("DEBUG: $jsonString");

    return filtersJson;
  }

  void _showFilters(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AutourFilters(
          searchBtnCallback: (today, filters) async {
            //List<Place> places = await _searchNearby(today, filters);
            List<Place> places = await _filterPlaces(today, filters);
            setState(() {
              print("DEBUG: _filterPlaces has returned, setting places, ${places.length}");
              _placesShown = places;
            });
          }
        );
      }
    );
  }

  Future<String> _getCurrentAddress() async {
    Location currentPosition = await _determinePosition();
    String currentAddress = await _reverseGeocode(currentPosition);
    _lastKnownCoords = currentPosition;

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
                    _positionHasChanged = true;
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
      'place_id': place.id,
      'place_formatted_address': place.formattedAddress,
      'place_google_maps_uri': place.googleMapsUri,
      'place_primary_type': place.primaryType,
      'place_display_name': place.displayName,
      'place_longitude': place.location.lng,
      'place_latitude': place.location.lat,
      'place_current_opening_hours': json.encode(place.currentOpeningHours?.toJson()),
      'place_country': place.countryId,
      'place_area_id': place.areaId,
      'last_updated': place.lastUpdated.toIso8601String(),
    });
  }

  void _showPlaceDetails(BuildContext context, int index) async {
    List<String> weekdayDesc = _placesShown[index].currentOpeningHours?.weekdayDescriptions ?? [];

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return PlaceDetails(weekdayDesc: weekdayDesc);
      }
    );
  }

  void _showPlaceTypeFilter(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return PlaceTypeFilter(
          searchBtnCallback: (today, filters) async {
            print("DEBUG: (_showPlaceTypeFilters)");
            List<Place> places = await _searchNearby(today, filters);
            setState(() {
              print("DEBUG: searchNearby has returned, setting places, ${places.length}");
              _places = places;
              _placesShown = places;
            });
          }
        );
      }
    );
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
                    onPressed: () => _showPlaceTypeFilter(context),
                    child: Text('Autour'),
                  ),
                ),
              ),

              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  child: Row(
                    children: [
                      IconButton(
                        iconSize: 30,
                        icon: const Icon(Icons.filter_list_rounded),
                        onPressed: () => _showFilters(context),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),

            ],
          ),
          pinned: true,
        ),

        if (!_searchOngoing)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                return GestureDetector(
                  onTap: () {
                    _showPlaceDetails(context, index);
                  },
                  child: Container(
                    child: PlaceListItem(userPosition: _lastKnownCoords, placeData: _placesShown[index]),
                  ),
                );
              },
              childCount: _placesShown.length,
            ),
          ),

        if (_searchOngoing)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: LoadingAnimationWidget.beat(
                color: Colors.blue.shade100,
                size: 50,
              ),
            ),
          ),
      ]
    );
  }
}

class PlaceListItem extends StatelessWidget {
  final Location userPosition;
  final Place placeData;
  int _todayIdx = 0;

  PlaceListItem({
    required this.userPosition,
    required this.placeData,
  });

  String _getDayName() {
    return DateFormat('EEEE').format(DateTime.now());
  }

  String _computeDistance(double lat, double lng) {
      double distance = 0.0;
      String distanceStr = "";

      distance = Geolocator.distanceBetween(userPosition.lat, userPosition.lng,
          lat, lng);
      if (distance >= 1000) {
          distanceStr = "${(distance / 1000).toStringAsFixed(1)} km";
      }
      else {
          distanceStr = "${distance.round()} m";
      }

      return distanceStr;
  }

  Future<void> _openInMaps(String name, double lat, double lon) async {
    final availableMaps = await MapLauncher.installedMaps;

    await availableMaps.first.showMarker(
      coords: Coords(lat, lon),
      title: name,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get today's index
    _todayIdx = dayNamesIndex[_getDayName()] ?? -1;

    // In the 'openingHours' 'day' starts at 0 for sunday but in the
    // 'weekdayDescritions' the array starts at monday...
    final String? currentOpeningHours =
            placeData.currentOpeningHours?.weekdayDescriptions[(_todayIdx-1) % 7];

    final open = placeData.isOpen();
    final IconData isOpenIcon = open ? Icons.check_circle : Icons.cancel;
    final Color isOpenColor = placeData.isOpen() ? Colors.green : Colors.red;

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
                        _openInMaps(placeData.displayName,
                            placeData.location.lat,
                            placeData.location.lng
                        );
                      },
                      padding: EdgeInsets.zero,
                    ),
                    Container(height: 5),
                    Text(
                      _computeDistance(placeData.location.lat,
                          placeData.location.lng),
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
  final int id;
  final String formattedAddress;
  final String googleMapsUri;
  final String primaryType;
  final String displayName;
  final Location location;
  final OpeningHours? currentOpeningHours;
  final int countryId;
  final int areaId;
  final DateTime lastUpdated;

  const Place({
    required this.id,
    required this.formattedAddress,
    required this.googleMapsUri,
    required this.primaryType,
    required this.displayName,
    required this.location,
    required this.currentOpeningHours,
    required this.countryId,
    required this.areaId,
    required this.lastUpdated,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['place_id'] ?? 0,
      formattedAddress: json['place_formatted_address'] ?? "Unknown address",
      googleMapsUri: json['place_google_maps_uri'] ?? "Unknown Google Maps Uri",
      primaryType: json['place_primary_type'] ?? "Unknown primary type",
      displayName: json['place_display_name'] ?? "displayName",
      location: json['place_longitude'] != null && json['place_latitude'] != null
        ? Location(lat: json['place_latitude'], lng: json['place_longitude'])
        : Location(lat: -360, lng: -360),
      currentOpeningHours: json['place_current_opening_hours'] != null
        && json['place_current_opening_hours'] != "\"Unknown\""
        ? OpeningHours.fromJson(jsonDecode(json['place_current_opening_hours']))
        : null,
      countryId: json['place_country'] ?? 0,
      areaId: json['place_area_id'] ?? 0,
      lastUpdated: json['last_updated'] != null
        ? DateTime.parse(json['last_updated'])
        : DateTime(1970, 1, 1),
    );
  }

  bool isOpen() {
    DateTime now = DateTime.now();
    int currentTime = now.hour * 60 + now.minute;
    String today = _getDayName();
    int todayIdx = dayNamesIndex[today] ?? -1;
    List<Period> periods = this.currentOpeningHours?.periods ?? [];
    bool isOpenNow = false;

    for (final period in periods) {
      if (period.open.day == todayIdx || period.close.day == todayIdx) {
        int openAt = period.open.hour * 60 + period.open.minute;
        int closeAt = period.close.hour * 60 + period.close.minute;
        if (currentTime > openAt && currentTime < closeAt)
          isOpenNow = true;
      }
    }

    return isOpenNow;
  }

  String _getDayName() {
    return DateFormat('EEEE').format(DateTime.now());
  }
}

class Location {
  final double lat;
  final double lng;

  Location({required this.lat, required this.lng});

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      lat: json['place_latitude'],
      lng: json['place_longitude'],
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
  final Function(String, String) searchBtnCallback;

  AutourFilters({
    required this.searchBtnCallback,
  });

  String _getDayName() {
    return DateFormat('EEEE').format(DateTime.now());
  }

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
    searchBtnCallback(_getDayName(), filters ?? "{}");
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Filters"),
      content: FormBuilder(
        key: _formKey,
        child: Column(
          children: [
            // Open on
            FormBuilderFilterChip<String>(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(labelText: 'Open on'),
              name: 'days',
              //selectedColor: Colors.red,
              options: _days
                  .map(
                    (day) => FormBuilderChipOption(value: day)
                  ).toList(),
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

            // Open today
            FormBuilderFilterChip<String>(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              name: 'open_today',
              options: const [
                FormBuilderChipOption(
                  value: 'Open today',
                ),
              ],
            ),

            // Open now
            FormBuilderFilterChip<String>(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              name: 'open_now',
              options: const [
                FormBuilderChipOption(
                  value: 'Open now',
                ),
              ],
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

class PlaceDetails extends StatelessWidget {
  final List<String> weekdayDesc;

  PlaceDetails({
    required this.weekdayDesc,
  });

  Widget _showDesc(String day) {
    int dayLength = 10;
    int splitIndex = day.indexOf(':');

    // Craft day of week text with padding to align the time that comes next
    String dayPart = day.substring(0, splitIndex).trim();
    String padding = List.filled(dayLength - dayPart.length, ' ').join();
    String dayPartFormatted = dayPart + padding;

    // Craft hours text
    String timePart = day.substring(splitIndex + 1).trim();
    String timePartFormatted = "";
    List<String> hours = timePart.split(',');
    bool first = true;
    for (final hour in hours) {
      if (first == false)
        timePartFormatted += "\n" + List.filled(dayLength - 1, ' ').join();
      if (first)
        first = false;
      timePartFormatted += hour;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: RichText(
            text: TextSpan(
              // Main text style
              style: TextStyle(
                fontSize: 16.0,
                color: Colors.black,
                fontFamily: 'Courier',
              ),
              children: [
                TextSpan(
                  text: dayPartFormatted,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: timePartFormatted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Opening hours"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: weekdayDesc.map((day) => _showDesc(day)).toList(),
      ),
    );
  }
}

class PlaceTypeFilter extends StatelessWidget {
  final _formKey = GlobalKey<FormBuilderState>();
  final Function(String, String) searchBtnCallback;

  PlaceTypeFilter({
    required this.searchBtnCallback,
  });

  List<String> types = [
    'Automotive',
    'Business',
    'Culture',
    'Education',
    'Entertainment and Recreation',
    'Finance',
    'Food and Drink',
    'Geographical Areas',
    'Government',
    'Health and Wellness',
    'Lodging',
    'Places of Worship',
    'Services',
    'Shopping',
    'Sports',
    'Transportation',
  ];


  bool _handleButtonPressed() {
    _formKey.currentState?.validate();
    String filters = _formKey.currentState?.instantValue.toString() ?? "";

    // Ensure a type has been selected
    if (filters.contains("null")) {
      return false;
    }

    searchBtnCallback("Wednesday", filters ?? "{}");
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Select type"),
      content: SingleChildScrollView(
        child: FormBuilder(
          key: _formKey,
          child: Column(
            children: [
              // List of types
              FormBuilderChoiceChip<String>(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(labelText: 'Select the type of place to get'),
                name: 'types',
                options: types
                    .map(
                      (type) => FormBuilderChipOption(
                        value: type,
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(type),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
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
            if (_handleButtonPressed()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }
}
