// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'package:share/share.dart';

final GoogleSignIn _googleSignIn = new GoogleSignIn();
FirebaseUser _user = null;
DatabaseReference _root = null;
final FirebaseAuth _auth = FirebaseAuth.instance;
final _random = new Random(); // generates a new Random object

bool _have_signed_in_yet = false;

Widget _signInPage(BuildContext context) {
  Future<Null> _signMeInWithGoogle() async {
    print('I am signing in with google.');
    final GoogleSignInAccount googleUser = await _googleSignIn.signIn();
    print('I have signed in...');
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    _user = await _auth.signInWithGoogle(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken);
    print('I have signed in with Firebase...');
    assert(_user.email != null);
    assert(_user.displayName != null);
    assert(_user.uid != null);
    assert(!_user.isAnonymous);
    _root = FirebaseDatabase.instance.reference().child(_user.uid);
    _root.keepSynced(true);
    print('I am going to the lists!');
    Navigator.of(context).pushNamed('/_');
  }
  if (!_have_signed_in_yet) {
    _have_signed_in_yet = true;
    _signMeInWithGoogle();
  }
  return new Scaffold(
      appBar: new AppBar(
          title: const Text('Thing Lists'),
          actions: <Widget>[
          ],
                         ),
      body: new Center(
          child: new FlatButton(
              child: new Text('Sign in with Google'),
              onPressed: _signMeInWithGoogle)));
}

Route ListRoute(RouteSettings settings) {
  print('creating route for ${settings.name}');
  final String _listname = settings.name.substring(1);
  final DatabaseReference _ref = _root.child(_listname);
  return new MaterialPageRoute(
      settings: settings,
      builder: (context) => new ListPage(listname: _listname));
}

class ListPage extends StatefulWidget {
  final String listname;
  ListPage({Key key, this.listname}) : super(key: key);

  @override
  _ListPageState createState() => new _ListPageState(listname: listname);
}

class _ListPageState extends State<ListPage> {
  final String listname;
  DatabaseReference _ref;
  List<String> _items = [];
  final GlobalKey<AnimatedListState> listKey = new GlobalKey<AnimatedListState>();

  _ListPageState({this.listname}) {
    _ref = _root.child(listname);
    _ref.onValue.listen((Event event) {
      setState(() {
        final iteminfo = event.snapshot.value;
        _items = [];
        if (iteminfo != null) {
          iteminfo.forEach((i,info) {
            _items.add(i);
          });
        }
      });
    });
  }

  @override
  void initState() {
    FirebaseDatabase.instance.setPersistenceEnabled(true);
    FirebaseDatabase.instance.setPersistenceCacheSizeBytes(1000000);
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> xx = [];
    _items.forEach((i) {
          xx.add(new Text(i));
        });
    return new Scaffold(
        appBar: new AppBar(
            title: new Text('$listname'),
            actions: <Widget>[
            ],
                           ),
        body: new ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(20.0),
            children: xx),
        floatingActionButton: new FloatingActionButton(
            onPressed: () {
          print('pressed button');
        },
            tooltip: 'Increment',
            child: new Icon(Icons.add),
                                                       ));
  }
}

void main() {
  runApp(new MaterialApp(
          onGenerateRoute: ListRoute,
          routes: <String, WidgetBuilder>{
            '/': _signInPage,
          }));
}
