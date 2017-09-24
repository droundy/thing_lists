/* Student Pairs
   Copyright (C) 2017 David Roundy

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License as
   published by the Free Software Foundation; either version 2 of the
   License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
   02110-1301 USA */

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'package:flutter_color_picker/flutter_color_picker.dart';

// import 'package:share/share.dart';

final GoogleSignIn _googleSignIn = new GoogleSignIn();
DatabaseReference _root;
final FirebaseAuth _auth = FirebaseAuth.instance;
final _random = new Random(); // generates a new Random object

// The following *should* enable concurrent calls to ensureSignedIn without
// doing excess work.
Future<GoogleSignInAccount> _googleUser;
FirebaseUser _user;
Future<FirebaseUser> _userFuture;

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

Route listRoute(RouteSettings settings) {
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

const doneIcon = const Icon(Icons.done, color: const Color(0xFFFFFFFF));
const scheduleIcon = const Icon(Icons.schedule, color: const Color(0xFFFFFFFF));
const doneColor = const Color(0xFF0f9d58);
const scheduleColor = const Color(0xFFef6c00);

class _ListPageState extends State<ListPage> {
  final String listname;
  DatabaseReference _ref;
  List<String> _items = [];
  Map _keys = {};
  Map _colors = {};
  String searching ;
  final GlobalKey<AnimatedListState> listKey = new GlobalKey<AnimatedListState>();

  _orderItems(Map iteminfo) {
    _items = [];
    List<Map> things = [];
    if (iteminfo != null) {
      setState(() {
        iteminfo.forEach((i,info) {
          if (info is Map && info.containsKey('_next') && info.containsKey('_chosen')) {
            if (searching == null || matches(searching, {i: info})) {
              info['name'] = i;
              things.add(info);
            }
          }
        });
        things.sort((a,b) => a['_next'].compareTo(b['_next']));
        things.forEach((thing) {
              String t = thing['name'];
              _items.add(t);
              _keys[t] = new ValueKey(thing);
              if (thing.containsKey('color')) {
                _colors[t] = new Color(thing['color']);
              }
            });
      });
    }
  }

  _setMyselfUp() {
    if (_root != null && _ref == null) {
      _ref = _root.child(listname);
      _ref.onValue.listen((Event event) {
        if (mounted) {
          final iteminfo = event.snapshot.value;
          _orderItems(iteminfo);
        } else {
          _ref = null;
        }
      });
    }
  }

  _ListPageState({this.listname}) {
    _setMyselfUp();
  }

  Color _color(String i) {
    if (_colors.containsKey(i)) {
      return _colors[i];
    }
    return const Color(0xffffffff);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    ensureSignedIn().then((x) {
          _setMyselfUp();
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
                      child: pastelPicker(context));
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
                  child: new Card(
                      color: _color(i),
                      child: new Row(
                          children: <Widget>[
                            menu,
                            new Expanded(child:
                            new SizedBox(
                                height: 30 + 0.35*i.length,
                                child: new FlatButton(
                                    // child: new FittedBox(
                                    //     fit: BoxFit.contain,
                                    //     child: new Text(i, maxLines: 30)),
                                    child: new Text(i, maxLines: 30),
                                    onPressed: () async {
                                      print('selected $i');
                                      Navigator.of(context).pushNamed('/$listname/$i'); // nesting!
                                    }))),
                            new IconButton(
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
                          ])),
                  key: _keys[i],
                  background: new Card(
                      child: new ListTile(leading: doneIcon),
                      color: doneColor),
                  secondaryBackground: new Card(
                      child: new ListTile(trailing: scheduleIcon),
                      color: scheduleColor),
                  onDismissed: (direction) async {
                    setState(() {
                      _items.remove(i);
                    });
                    Map data = (await _ref.once()).value;
                    final int oldchosen = data[i]['_chosen'];
                    final int oldnext = data[i]['_next'];
                    final int now = new DateTime.now().millisecondsSinceEpoch;
                    const int day = 24*60*60*1000;
                    int nextone = oldnext + 1000*day;
                    data.forEach((k,v) {
                      if (v is Map && v.containsKey('_next') &&
                          v['_next'] > oldnext && v['_next'] < nextone) {
                        nextone = v['_next'];
                      }
                    });
                    if (nextone == oldnext + 1000*day) {
                      nextone = now;
                    }
                    if (direction == DismissDirection.startToEnd) {
                      data[i]['_chosen'] = now;
                      final int offset = data[i]['_chosen'] - oldchosen;
                      data[i]['_next'] = data[i]['_chosen'] + _random.nextInt(offset);
                    } else {
                      data[i]['_ignored'] = now;
                      final int offset = max(now - oldchosen, nextone - oldchosen);
                      if (data[i]['_next'] < now) {
                        data[i]['_next'] = now + offset + _random.nextInt(2*offset);
                      } else {
                        data[i]['_next'] = data[i]['_next'] + offset + _random.nextInt(2*offset);
                      }
                    }
                    _ref.set(data);
                  },
                                 ));
        });
    AppBar appbar = new AppBar(
        title: new Text('$listname'),
        actions: <Widget>[
          new IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              onPressed: () {
            print('should search here');
            setState(() {
              searching = '';
            });
          })
        ]);
    if (searching != null) {
      appbar = new AppBar(
          leading: new BackButton(),
          title: new TextField(
              keyboardType: TextInputType.text,
              style: new TextStyle(fontSize: 16.0),
              decoration: new InputDecoration(
                  hintText: 'Search $listname things',
                  hintStyle: new TextStyle(fontSize: 16.0),
                  hideDivider: true),
              onChanged: (String val) async {
            // print('search for $val compare $searching');
                if (val != null && val != searching && val != '') {
                  searching = val;
                  final iteminfo = (await _ref.once()).value;
                  _orderItems(iteminfo);
                }
              },
              autofocus: true),
          actions: <Widget>[
            new IconButton(
                icon: new Icon(Icons.cancel),
                onPressed: () {
              setState(() {
                searching = null;
                _ref.once().then((xx) {
                      _orderItems(xx.value);
                    });
              });
            })
          ]);
    }
    return new Scaffold(
        appBar: appbar,
        // body: new FirebaseAnimatedList(
        //     itemBuilder: (BuildContext context, DataSnapshot snapshot, Animation<double> animation) {
        //   return new Text('item');
        // },
        //     query: _ref),
        body: new ListView(
            key: new UniqueKey(),
            shrinkWrap: true,
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
  runApp(new MaterialApp(onGenerateRoute: listRoute));
}

Future<String> textInputDialog(BuildContext context, String title, [String value]) async {
  String foo;
  return showDialog(context: context,
      child: new AlertDialog(title: new Text(title),
          content: new TextField(
              controller: new TextEditingController(text: value),
              autofocus: true,
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

bool matchesString(String searching, String data) {
  if (!data.startsWith('_') && data.toLowerCase().contains(searching)) {
    // print(' "$searching" matches "$data"');
    return true;
  }
  return false;
}

bool matches(String searching, data) {
  if (data is! Map) return false;
  searching = searching.toLowerCase();
  if (data.keys.any((k) => data[k] is Map && matchesString(searching, k))) {
    return true;
  }
  return data.values.any((v) => matches(searching, v));
}

ColorPickerDialog pastelPicker(BuildContext context) {
  List<MaterialColor> primaries = Colors.primaries;
  List<Color> cs = new List.from(Colors.primaries);
  for (int i=0; i<cs.length; i++) {
    cs[i] = primaries[i][200];
  }
  cs.add(const Color(0xFFdddddd));
  print('cs length ${cs.length}');
  ColorPickerGrid grid = new ColorPickerGrid(
      colors: cs,
      onTap: (Color color) { Navigator.pop(context, color); },
      rounded: false);
  return new ColorPickerDialog(body: grid);
}
