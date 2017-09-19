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
DatabaseReference _root = null;
final FirebaseAuth _auth = FirebaseAuth.instance;
final _random = new Random(); // generates a new Random object

// The following *should* enable concurrent calls to ensureSignedIn without
// doing excess work.
Future<GoogleSignInAccount> _googleUser = null;
FirebaseUser _user = null;
Future<FirebaseUser> _userFuture = null;

Future<Null> ensureSignedIn() async {
  _user = await _auth.currentUser();
  if (_user == null) {
    if (_googleUser == null) {
      print('I am signing in with google.');
      _googleUser = _googleSignIn.signIn();
    }
    final GoogleSignInAccount googleUser = await _googleUser;
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    if (_userFuture == null) {
      _userFuture = _auth.signInWithGoogle(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken);
      print('I have signed in with Firebase...');
    }
    _user = await _userFuture;
  }
  if (_root == null) {
    _root = FirebaseDatabase.instance.reference().child(_user.uid);
    _root.keepSynced(true);
    FirebaseDatabase.instance.setPersistenceEnabled(true);
  }
}

Route ListRoute(RouteSettings settings) {
  String _listname = settings.name.substring(1);
  while (_listname.startsWith('/')) {
    _listname = _listname.substring(1);
  }
  print('creating route for ${settings.name} with listname "$_listname"');
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
  DatabaseReference _ref = null;
  List<String> _items = [];
  Map _keys = {};
  Map _colors = {};
  final GlobalKey<AnimatedListState> listKey = new GlobalKey<AnimatedListState>();

  _set_myself_up() {
    if (_root != null && _ref == null) {
      _ref = _root.child(listname);
      _ref.onValue.listen((Event event) {
        setState(() {
          final iteminfo = event.snapshot.value;
          _items = [];
          List<Map> things = [];
          if (iteminfo != null) {
            iteminfo.forEach((i,info) {
              if (info is Map && info.containsKey('_next') && info.containsKey('_chosen')) {
                info['name'] = i;
                things.add(info);
              }
            });
            things.sort((a,b) => a['_chosen'].compareTo(b['_chosen']));
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
  }

  _ListPageState({this.listname}) {
    _set_myself_up();
  }

  Color _color(String i) {
    if (_colors.containsKey(i)) {
      return _colors[i];
    }
    return const Color(0xffffffff);
  }

  @override
  void initState() {
  }

  @override
  Widget build(BuildContext context) {
    ensureSignedIn().then((x) {
      setState(() {
        _set_myself_up();
      });
    });
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
                            Navigator.of(context).pushNamed('/$listname/$i'); // nesting!
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
                    final int oldchosen = data[i]['_chosen'];
                    if (direction == DismissDirection.startToEnd) {
                      data[i]['_chosen'] = new DateTime.now().millisecondsSinceEpoch;
                      final int offset = data[i]['_chosen'] - oldchosen;
                      data[i]['_next'] = data[i]['_chosen'] + _random.nextInt(offset);
                    } else {
                      data[i]['_ignored'] = new DateTime.now().millisecondsSinceEpoch;
                      final int offset = data[i]['_ignored'] - oldchosen;
                      data[i]['_next'] = oldchosen + _random.nextInt(4*offset);
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
                final int now = new DateTime.now().millisecondsSinceEpoch;
                const int day = 24*60*60*1000;
                data[newitem] = {
                  '_chosen': now,
                  '_ignored': 0,
                  '_next': now+_random.nextInt(2*day),
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
  runApp(new MaterialApp(onGenerateRoute: ListRoute));
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
