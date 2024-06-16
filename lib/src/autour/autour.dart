import 'package:flutter/material.dart';

import 'package:loading_animation_widget/loading_animation_widget.dart';

class AutourScreen extends StatefulWidget {
  const AutourScreen({super.key});

  @override
  State<AutourScreen> createState() => _AutourScreen();
}

class _AutourScreen extends State<AutourScreen> {
  bool _searchOngoing = false;

  void searchAround() {
    print("Autour Button pressed");
  }

  @override
  Widget build(BuildContext context) {
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
