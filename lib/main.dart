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

import 'package:flutter_color_picker/flutter_color_picker.dart';

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
  Map _keys = {};
  Map _colors = {};
  final GlobalKey<AnimatedListState> listKey = new GlobalKey<AnimatedListState>();

  _ListPageState({this.listname}) {
    _ref = _root.child(listname);
    _ref.onValue.listen((Event event) {
      setState(() {
        final iteminfo = event.snapshot.value;
        _items = [];
        List<Map> things = [];
        if (iteminfo != null) {
          iteminfo.forEach((i,info) {
            info['name'] = i;
            things.add(info);
          });
          things.sort((a,b) => a['chosen'].compareTo(b['chosen']));
          things.forEach((thing) {
                String t = thing['name'];
                _items.add(t);
                _keys[t] = new ValueKey(thing);
                if (thing.containsKey('color')) {
                  _colors[t] = new Color(thing['color']);
                }
              });
        }
      });
    });
  }

  Color _color(String i) {
    if (_colors.containsKey(i)) {
      return _colors[i];
    }
    return const Color(0xffffffff);
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
          Widget menu = new PopupMenuButton<String>(
              child: const Icon(Icons.more_vert),
              itemBuilder: (BuildContext context) => [
                new PopupMenuItem<String>(
                    value: 'color',
                    child: const Text('color')),
                new PopupMenuItem<String>(
                    value: 'rename',
                    child: const Text('rename')),
              ],
              onSelected: (selected) async {
                if (selected == 'color') {
                  Color color = await showDialog(
                      context: context,
                      child: new PrimaryColorPickerDialog());
                  if (color != null) {
                    print('color: ${color.value}');
                    await _ref.child(i).child('color').set(color.value);
                  }
                } else if (selected == 'rename') {
                  String newname = await textInputDialog(context,
                      'Rename $listname thing?', i);
                  if (newname != null && newname != i) {
                    Map data = (await _ref.child(i).once()).value;
                    _ref.child(newname).set(data);
                    _ref.child(i).remove();
                    DataSnapshot xx = (await _root.child(i).once());
                    if (xx != null && xx.value != null) {
                      _root.child(newname).set(xx.value);
                      _root.child(i).remove();
                    }
                  }
                }
              });

          xx.add(new Dismissible(
                  child: new Hero(key: new ValueKey(i), child: new Card(
                      color: _color(i),
                      child: new ListTile(
                          title: new Text(i),
                          leading: menu, // const Icon(Icons.more_vert),
                          // trailing: const Icon(Icons.delete),
                          trailing: new IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () async {
                                final bool confirmed = await confirmDialog(context,
                                    'Really delete $i?', 'DELETE');
                                print('confirmed is $confirmed');
                                if (confirmed) {
                                  print('am deleting $i');
                                  _ref.child(i).remove();
                                  _root.child(i).remove();
                                }
                              }),
                          onLongPress: () async {
                            print('selected $i');
                            Navigator.of(context).pushNamed('/$i');
                          }))),
                  key: _keys[i],
                  background: new Card(
                      child: new ListTile(title: new Text('')),
                      color: const Color(0xFF005f00)),
                  secondaryBackground: new Card(
                      child: new ListTile(title: new Text('')),
                      color: const Color(0xFF8f7f00)),
                  onDismissed: (direction) async {
                    print('dismissed $i in $direction');
                    Map data = (await _ref.once()).value;
                    if (direction == DismissDirection.startToEnd) {
                      data[i]['chosen'] = new DateTime.now().millisecondsSinceEpoch;
                    } else {
                      data[i]['ignored'] = new DateTime.now().millisecondsSinceEpoch;
                    }
                    _ref.set(data);
                  },
                                 ));
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
            onPressed: () async {
              String newitem = await textInputDialog(context, 'New $listname thing?');
              if (newitem != null) {
                Map data = {};
                DataSnapshot old = await _ref.once();
                if (old.value != null) {
                  data = old.value;
                }
                data[newitem] = {
                  'chosen': new DateTime.now().millisecondsSinceEpoch,
                  'ignored': 0,
                };
                _ref.set(data);
                print('got $newitem');
              }
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

Future<String> textInputDialog(BuildContext context, String title, [String value]) async {
  String foo;
  return showDialog(context: context,
      child: new AlertDialog(title: new Text(title),
          content: new TextField(
              controller: new TextEditingController(text: value),
              onChanged: (String newval) {
            foo = newval;
          },
              onSubmitted: (String newval) {
            Navigator.pop(context, newval);
          }),
          actions: <Widget>[
            new FlatButton(
                child: new Text('CANCEL'),
                onPressed: () {
              Navigator.pop(context, null);
            }
                           ),
            new FlatButton(
                child: new Text('ADD'),
                onPressed: () {
              Navigator.pop(context, foo);
            }
                           ),
          ]),
                    );
}

Future<bool> confirmDialog(BuildContext context, String title, String action) async {
  return showDialog(context: context,
      child: new AlertDialog(title: new Text(title),
          actions: <Widget>[
            new FlatButton(
                child: new Text('CANCEL'),
                onPressed: () {
              Navigator.pop(context, false);
            }),
            new FlatButton(
                child: new Text(action),
                onPressed: () {
              Navigator.pop(context, true);
            }),
          ]));
}
