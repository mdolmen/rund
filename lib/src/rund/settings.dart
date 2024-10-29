// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'globals.dart';
import 'consumable_store.dart';
import 'database_helper.dart';

// Auto-consume must be true on iOS.
// To try without auto-consume on another platform, change `true` to `false` here.
final bool _kAutoConsume = Platform.isIOS || true;

const String _kCredits20Id = 'com.rund.credits.20';
const String _kCredits50Id = 'com.rund.credits.50';
const String _kCredits200Id = 'com.rund.credits.200';
const List<String> _kProductIds = <String>[
  _kCredits20Id,
  _kCredits50Id,
  _kCredits200Id,
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> with ChangeNotifier {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _newCredits;
  List<String> _notFoundIds = <String>[];
  List<ProductDetails> _products = <ProductDetails>[];
  List<PurchaseDetails> _purchases = <PurchaseDetails>[];
  bool _isAvailable = false;
  bool _purchasePending = false;
  bool _loading = true;
  String? _queryProductError;
  int _credits = 0;

  void updateCreditsUI() {
    setState(() {
      _setCreditsGlobal();
    });
    notifyListeners();
  }

  @override
  void initState() {
    final Stream<List<PurchaseDetails>> purchaseUpdated =
        _inAppPurchase.purchaseStream;
    _newCredits =
        purchaseUpdated.listen((List<PurchaseDetails> purchaseDetailsList) {
          _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _newCredits.cancel();
    }, onError: (Object error) {
    });
    _initStoreInfo();
    _setCreditsGlobal();
    super.initState();
  }

  void _sortProductsByPrice() {
    _products.sort((a, b) {
      double priceA = _convertPriceToDouble(a.price);
      double priceB = _convertPriceToDouble(b.price);
      return priceA.compareTo(priceB);
    });
  }

  // Helper function to convert price String to a double
  double _convertPriceToDouble(String priceString) {
    // Remove the currency symbol either at the beginning or the end and
    // convert to double.
    return double.tryParse(priceString.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
  }

  Future<void> _setCreditsGlobal() async {
    while (USER_ID.isEmpty) {
      await Future.delayed(Duration(milliseconds: 50));
    }
    final String url = BACKEND_URL + '/get-credits';
    int credits = 0;
  
    // Get credits from backend
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({
          'userId': USER_ID,
        }),
      );
  
      // Check if the response is successful (status code 200)
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        credits = data['credits'] as int;
      }
      else {
        print('[-] Failed to load credits. Status code: ${response.statusCode}');
      }
    } catch (error) {
      print('[-] Error occurred while fetching credits: $error');
    }
  
    setState(() {
      _credits = credits;
    });
  }

  Future<void> _initStoreInfo() async {
    final bool isAvailable = await _inAppPurchase.isAvailable();

    if (!isAvailable) {
      setState(() {
        _isAvailable = isAvailable;
        _products = <ProductDetails>[];
        _purchases = <PurchaseDetails>[];
        _notFoundIds = <String>[];
        _purchasePending = false;
        _loading = false;
      });
      return;
    }

    if (Platform.isIOS) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition =
          _inAppPurchase
              .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await iosPlatformAddition.setDelegate(ExamplePaymentQueueDelegate());
    }

    // Get available products
    final ProductDetailsResponse productDetailResponse =
        await _inAppPurchase.queryProductDetails(_kProductIds.toSet());

    if (productDetailResponse.error != null) {
      setState(() {
        _queryProductError = productDetailResponse.error!.message;
        _isAvailable = isAvailable;
        _products = productDetailResponse.productDetails;
        _purchases = <PurchaseDetails>[];
        _notFoundIds = productDetailResponse.notFoundIDs;
        _purchasePending = false;
        _loading = false;
      });
      return;
    }

    if (productDetailResponse.productDetails.isEmpty) {
      setState(() {
        _queryProductError = null;
        _isAvailable = isAvailable;
        _products = productDetailResponse.productDetails;
        _sortProductsByPrice();
        _purchases = <PurchaseDetails>[];
        _notFoundIds = productDetailResponse.notFoundIDs;
        _purchasePending = false;
        _loading = false;
      });
      return;
    }

    setState(() {
      _isAvailable = isAvailable;
      _products = productDetailResponse.productDetails;
      _sortProductsByPrice();
      _notFoundIds = productDetailResponse.notFoundIDs;
      _purchasePending = false;
      _loading = false;
    });
  }

  @override
  void dispose() {
    if (Platform.isIOS) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition =
          _inAppPurchase
              .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      iosPlatformAddition.setDelegate(null);
    }
    _newCredits.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> stack = <Widget>[];

    if (_queryProductError == null) {
      stack.add(
        ListView(
          children: <Widget>[
            _buildProductList(),
            Card(
              child: ListTile(
                title: Text("Credits: $_credits"),
              ),
            ),
          ],
        ),
      );

      stack.add(
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Card(
            child: ListTile(
              title: Text("Info"),
              subtitle: Text("The data source is OpenStreetMap which for now lacks information on some places regarding opening hours."),
            ),
          )
        ),
      );
    }
    else {
      stack.add(
        Center(
          child: Text(_queryProductError!),
        )
      );
    }

    if (_purchasePending) {
      stack.add(
        const Stack(
          children: <Widget>[
            Opacity(
              opacity: 0.3,
              child: ModalBarrier(dismissible: false, color: Colors.grey),
            ),
            Center(
              child: CircularProgressIndicator(),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: stack,
    );
  }

  Card _buildProductList() {
    final List<ListTile> productList = <ListTile>[];

    if (_loading) {
      return const Card(
        child: ListTile(
            leading: CircularProgressIndicator(),
            title: Text('Fetching products...')));
    }
    if (!_isAvailable) {
      return const Card();
    }

    if (_notFoundIds.isNotEmpty) {
      productList.add(ListTile(
        title: Text('[${_notFoundIds.join(", ")}] not found',
          style: TextStyle(color: ThemeData.light().colorScheme.error)),
        )
      );
    }

    // This loading previous purchases code is just a demo. Please do not use this as it is.
    final Map<String, PurchaseDetails> purchases =
        Map<String, PurchaseDetails>.fromEntries(
            _purchases.map((PurchaseDetails purchase) {
      if (purchase.pendingCompletePurchase) {
        _inAppPurchase.completePurchase(purchase);
      }
      return MapEntry<String, PurchaseDetails>(purchase.productID, purchase);
    }));

    productList.addAll(_products.map(
      (ProductDetails productDetails) {
        final PurchaseDetails? previousPurchase = purchases[productDetails.id];

        return ListTile(
          title: Text(
            "Buy " + productDetails.title,
          ),
          trailing:TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  late PurchaseParam purchaseParam;

                  if (Platform.isAndroid) {
                    purchaseParam = GooglePlayPurchaseParam(
                      productDetails: productDetails,
                    );
                  }
                  else {
                    purchaseParam = PurchaseParam(
                      productDetails: productDetails,
                    );
                  }

                  // Trigger purchase
                  if (productDetails.id == _kCredits20Id ||
                      productDetails.id == _kCredits50Id ||
                      productDetails.id == _kCredits200Id)
                  {
                    _inAppPurchase.buyConsumable(
                      purchaseParam: purchaseParam,
                      autoConsume: _kAutoConsume
                    );
                  }
                },
                child: Text(productDetails.price),
              ),
        );
      },
    ));

    return Card(
      child: Column(
        children: productList
      )
    );
  }

  void showPendingUI() {
    setState(() {
      _purchasePending = true;
    });
  }

  Future<void> deliverProduct(PurchaseDetails purchaseDetails) async {
    setState(() {
      _purchases.add(purchaseDetails);
      _purchasePending = false;
    });
  }

  void handleError(IAPError error) {
    setState(() {
      _purchasePending = false;
    });
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    // Extract verification data
    final String verificationData = purchaseDetails.verificationData.localVerificationData;

    // Send the verification data to the backend
    final response = await http.post(
      Uri.parse(BACKEND_URL + '/verify-purchase'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'verificationData': verificationData,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'productId': purchaseDetails.productID,
        'userId': USER_ID,
      }),
    );

    if (response.statusCode != 200) {
      print('Server verification failed with status code ${response.statusCode}');
      return Future<bool>.value(false);
    }

    final responseData = jsonDecode(response.body);

    // Handle the response from your server (e.g., unlock features or credits)
    if (responseData['status'] == 'success') {
      print('[+] Purchase successful!');
      _setCreditsGlobal();
    }
    else {
      print('[-] Purchase verification failed.');
      return Future<bool>.value(false);
    }

    return Future<bool>.value(true);
  }

  void _handleInvalidPurchase(PurchaseDetails purchaseDetails) {
    // TODO: proper logging
    print("[-] Purchase failed...");
    _purchasePending = false;
  }

  Future<void> _listenToPurchaseUpdated(
      List<PurchaseDetails> purchaseDetailsList) async {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        showPendingUI();
        continue;
      }

      if (purchaseDetails.status == PurchaseStatus.error) {
        handleError(purchaseDetails.error!);
        continue;
      }

      if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        final bool valid = await _verifyPurchase(purchaseDetails);

        if (valid) {
          unawaited(deliverProduct(purchaseDetails));
        }
        else {
          _handleInvalidPurchase(purchaseDetails);
          return;
        }
      }

      if (Platform.isAndroid) {
        if (!_kAutoConsume && purchaseDetails.productID == _kCredits20Id) {
          final InAppPurchaseAndroidPlatformAddition androidAddition =
              _inAppPurchase.getPlatformAddition<
                  InAppPurchaseAndroidPlatformAddition>();
          await androidAddition.consumePurchase(purchaseDetails);
        }
      }
      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }
}

/// Example implementation of the
/// [`SKPaymentQueueDelegate`](https://developer.apple.com/documentation/storekit/skpaymentqueuedelegate?language=objc).
///
/// The payment queue delegate can be implementated to provide information
/// needed to complete transactions.
class ExamplePaymentQueueDelegate implements SKPaymentQueueDelegateWrapper {
  @override
  bool shouldContinueTransaction(
      SKPaymentTransactionWrapper transaction, SKStorefrontWrapper storefront) {
    return true;
  }

  @override
  bool shouldShowPriceConsent() {
    return false;
  }
}
