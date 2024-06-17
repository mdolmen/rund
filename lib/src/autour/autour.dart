import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:loading_animation_widget/loading_animation_widget.dart';

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

  static void searchAround() {
    print("Autour Button pressed");
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
              return PlaceListItem();
            },
            childCount: 10,
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
                Image.asset(
                  "assets/images/flutter_logo.png",
                  height: 100,
                  width: 100,
                  fit: BoxFit.cover,
                ),

                // Spacing between the image and the text
                Container(width: 20),

                // Take the rest of the space
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(height: 5),
                      Text(
                        "Cards Title 1",
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
