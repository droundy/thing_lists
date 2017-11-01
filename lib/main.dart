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

import 'flingable.dart';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'package:flutter_color_picker/flutter_color_picker.dart';

const int second = 1000;
const int minute = 60 * second;
const int hour = 60 * minute;
const int day = 24 * hour;
const int month = 30 * day;
const int year = 365 * day;

String prettyDuration(int t) {
  if (t.abs() > 2.5 * year) {
    return '${t ~/ year} year';
  }
  if (t.abs() > 2.5 * month) {
    return '${t ~/ month} month';
  }
  if (t.abs() > 2.5 * day) {
    return '${t ~/ day} days';
  }
  if (t.abs() > 2.5 * hour) {
    return '${t ~/ hour} hours';
  }
  if (t.abs() > 2.5 * minute) {
    return '${t ~/ minute} min';
  }
  if (t.abs() > 2.5 * second) {
    return '${t ~/ second} s';
  }
  return '$t ms';
}

String prettyTime(int t) {
  final int now = new DateTime.now().millisecondsSinceEpoch;
  if (t < now) {
    return '${prettyDuration(now-t)} ago';
  }
  return 'in ${prettyDuration(t-now)}';
}

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
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    if (_userFuture == null) {
      _userFuture = _auth.signInWithGoogle(
          accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
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

class ThingInfo {
  final String name;
  final Map data;
  List<ThingInfo> _children;

  ThingInfo({this.name, this.data}) {
    if (!data.containsKey('_next')) {
      data['_next'] = now;
    }
    if (!data.containsKey('_chosen_count')) {
      data['_chosen_count'] = 0;
    }
  }

  int get now => new DateTime.now().millisecondsSinceEpoch;

  int get chosen => data['_chosen'];
  int get firstChosen => data['_first_chosen'];
  int get next => data['_next'];
  int get count => data['_chosen_count'];
  String get follows => data['_follows'];
  Color get color {
    if (data.containsKey('color')) {
      return new Color(data['color']);
    }
    return null;
  }

  List<ThingInfo> get children {
    if (_children != null) return _children;
    _children = [];
    data.forEach((i, info) {
      if (info is Map && info.containsKey('_next')) {
        _children.add(new ThingInfo(name: i, data: info));
      }
    });
    return _children;
  }

  ThingInfo child(String name) {
    if (data.containsKey(name)) {
      return new ThingInfo(name: name, data: data[name]);
    }
    return null;
  }

  int get meanInterval {
    if (count < 2) {
      return 1 * day;
    }
    return (chosen - firstChosen) ~/ (count - 1);
  }

  int get meanChildInterval {
    int totalcount = 0;
    int totaltime = 0;
    children.forEach((ch) {
      if (ch.count > 1) {
        totalcount += ch.count - 1;
        totaltime += (ch.chosen - ch.firstChosen);
      }
    });
    if (totalcount == 0) {
      int firstChosenChild = 0;
      children.forEach((ch) {
        if (ch.count > 0 &&
            (ch.firstChosen < firstChosenChild || firstChosenChild == 0)) {
          firstChosenChild = ch.firstChosen;
        }
      });
      if (firstChosenChild > 0) {
        return now - firstChosenChild;
      }
      return 1 * day;
    }
    return totaltime ~/ totalcount;
  }

  void choose(final int meanIntervalList) {
    print(
        'choosing: ${prettyTime(chosen)}  and  ${prettyDuration(meanInterval)}  and  ${prettyDuration(meanIntervalList)}');
    if (count > 1) {
      data['_next'] = now +
          pow((now - chosen) * meanInterval * meanIntervalList, 1.0 / 3)
              .round();
    } else if (count == 1) {
      data['_next'] = now + pow((now - chosen) * meanIntervalList, 0.5).round();
    } else {
      data['_next'] = now + meanIntervalList;
    }
    data['_chosen'] = now;
    data['_chosen_count'] += 1;
    if (firstChosen == null) {
      data['_chosen_count'] = 1;
      data['_first_chosen'] = chosen;
    }
  }

  void sooner() {
    // move it back closer to now by half.
    data['_next'] = now + (next - now) ~/ 2;
  }

  void ignore(int nextone) {
    final int thisnow = now;
    int offset = 1000 + thisnow - chosen;
    if (offset < 1000 + nextone - chosen) {
      offset = 1000 + nextone - chosen;
    }
    if (offset < day ~/ 24) {
      offset = day ~/ 24;
    }
    print('offset is $offset... 2*offset is ${2*offset}');
    if (next < thisnow) {
      data['_next'] = thisnow + offset + myrand(2 * offset);
    } else {
      data['_next'] = next + offset + myrand(2 * offset);
    }
  }
}

class _ListPageState extends State<ListPage> {
  final String listname;
  DatabaseReference _ref;
  ThingInfo _info;
  List<String> _items = [];
  Map _follows = {};
  Map _colors = {};
  Map _keys = {};
  Color myColor = const Color(0xFF555555);
  String searching;
  final GlobalKey<AnimatedListState> listKey =
      new GlobalKey<AnimatedListState>();

  _orderItems(Map iteminfo) {
    _items = [];
    List<ThingInfo> things = [];
    if (iteminfo != null) {
      setState(() {
        _info = new ThingInfo(name: listname, data: iteminfo);
        if (iteminfo.containsKey('color')) {
          myColor = darkColor(_info.color);
        }
        _info.children.forEach((ch) {
          if (searching == null || matches(searching, {ch.name: ch.data})) {
            things.add(ch);
          }
        });
        things.sort((a, b) => a.next.compareTo(b.next));
        _follows = {};
        things.forEach((thing) {
          String t = thing.name;
          _items.add(t);
          if (thing.color != null) {
            _colors[t] = thing.color;
          }
          if (thing.follows != null) {
            _follows[t] = thing.follows;
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
      PopupMenuItem<String> followItem = const PopupMenuItem<String>(
          value: 'follows', child: const Text('follows...'));
      if (_follows.containsKey(i)) {
        followItem = new PopupMenuItem<String>(
            value: 'follows', child: new Text('follows ${_follows[i]}'));
      }
      Widget menu = new PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (BuildContext context) => [
                new PopupMenuItem<String>(
                    value: 'color', child: const Text('color')),
                new PopupMenuItem<String>(
                    value: 'info', child: const Text('info...')),
                followItem,
                new PopupMenuItem<String>(
                    value: 'rename', child: const Text('rename')),
                new PopupMenuItem<String>(
                    value: 'delete', child: const Text('delete')),
              ],
          onSelected: (selected) async {
            if (selected == 'color') {
              Color color = await showDialog(
                  context: context, child: pastelPicker(context));
              if (color != null) {
                print('color: ${color.value}');
                await _ref.child(i).child('color').set(color.value);
              }
            } else if (selected == 'rename') {
              String newname =
                  await textInputDialog(context, 'Rename $listname thing?', i);
              if (newname != null && newname != i) {
                Map data = (await _ref.child(i).once()).value;
                _ref.child(newname).set(data);
                _ref.child(i).remove();
              }
            } else if (selected == 'info') {
              String countInfo;
              if (_info.child(i).count == 1) {
                countInfo =
                    'Chosen once\nChosen: ${prettyTime(_info.child(i).chosen)}';
              } else if (_info.child(i).count > 0) {
                countInfo =
                    'Chosen ${_info.child(i).count} times\nChosen: ${prettyTime(_info.child(i).chosen)}';
              } else {
                countInfo = 'Never chosen';
              }
              ThingInfo childI = _info.child(i);
              final int now = childI.now;
              final int family = _info.meanChildInterval;
              String currentStr = '-';
              String meanStr = '-';
              int v = family;
              if (childI.count > 1) {
                int current = now - childI.chosen;
                int mean = childI.meanInterval;
                v = pow(current * mean * family, 1.0 / 3).round();
                currentStr = '${prettyDuration(current)}';
                meanStr = '${prettyDuration(mean)}';
              } else if (childI.count == 1) {
                int current = now - childI.chosen;
                v = pow(current * family, 0.5).round();
                currentStr = 'Interval: ${prettyDuration(current)}';
              }
              await infoDialog(context, '$i information', '''
$countInfo
Next: ${prettyTime(_info.child(i).next)}
Interval: $currentStr/$meanStr/${prettyDuration(family)} = ${prettyDuration(v)}
''');
            } else if (selected == 'delete') {
              final bool confirmed =
                  await confirmDialog(context, 'Really delete $i?', 'DELETE');
              print('confirmed is $confirmed');
              if (confirmed) {
                print('am deleting $i');
                _ref.child(i).remove();
              }
            } else if (selected == 'follows') {
              List<String> options = [];
              _items.forEach((xx) {
                if (xx != i) {
                  options.add(xx);
                }
              });
              String newfollows =
                  await stringSelectDialog(context, '$i follows:', options);
              if (newfollows != null) {
                if (newfollows == '__none__') {
                  await _ref.child(i).child('_follows').remove();
                } else {
                  await _ref.child(i).child('_follows').set(newfollows);
                }
              }
            }
          });

      if (!_keys.containsKey(i)) {
        _keys[i] = new GlobalKey();
      }
      xx.add(new Flingable(
        child: new Card(
            color: _color(i),
            child: new Row(children: <Widget>[
              menu,
              new Expanded(
                  child: new InkWell(
                      child: new Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10.0),
                          child: new Text(i)),
                      onTap: () async {
                        print('selected $i');
                        Navigator.of(context).pushNamed('/$listname/$i');
                      })),
            ])),
        key: _keys[i],
        resizeDuration: const Duration(milliseconds: 1000),
        background:
            new Card(child: new ListTile(leading: doneIcon), color: doneColor),
        secondaryBackground: new Card(
            child: new ListTile(trailing: scheduleIcon), color: scheduleColor),
        onFlinged: (direction) async {
          final int now = new DateTime.now().millisecondsSinceEpoch;
          // First: make none of the scheduled next times be in the past.  That
          // would be just silly!
          int mostNegativeNext = 0;
          _info.children.forEach((ch) {
            if (ch.next - now < mostNegativeNext) {
              mostNegativeNext = ch.next - now;
            }
          });
          _info.children.forEach((ch) {
            ch.data['_next'] -= mostNegativeNext;
          });
          ThingInfo info = _info.child(i);
          final int oldnext = info.next;
          int nextone = oldnext + 1000 * day;
          _info.children.forEach((ch) {
            if (ch.next > oldnext && ch.next < nextone) {
              nextone = ch.next;
            }
          });
          if (nextone == oldnext + 1000 * day) {
            nextone = now;
          }
          int meanInterval = _info.meanChildInterval;
          if (direction == FlingDirection.startToEnd) {
            info.choose(meanInterval);
            if (nextone > info.next && nextone != now) {
              // We haven't moved back in sequence! Presumably because all our
              // options are too far into the future... so let them be sooner.
              _info.children.forEach((ch) {
                if (ch.next > info.next) {
                  ch.sooner();
                }
              });
            }
          } else {
            info.ignore(nextone);
          }
          // Now we fix up "follows" relationship.  This is pretty hokey, we
          // just do the swaps seven times, which is probaly enough to percolate
          // the ordering down.
          for (int ii = 0; ii < 7; ii++) {
            _info.children.forEach((ch) {
              if (ch.follows != null) {
                ThingInfo earlier = _info.child(ch.follows);
                if (earlier != null &&
                    earlier.chosen < ch.chosen &&
                    earlier.next > ch.next) {
                  int oldchnext = ch.next;
                  ch.data['_next'] = earlier.next;
                  earlier.data['_next'] = oldchnext;
                }
              }
            });
          }
          _ref.set(_info.data);
        },
      ));
    });
    AppBar appbar = new AppBar(
        title: new Text('$listname'),
        backgroundColor: myColor,
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
          backgroundColor: myColor,
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
        body: new ListView(key: new ValueKey(listname), children: xx),
        floatingActionButton: new FloatingActionButton(
          backgroundColor: myColor,
          onPressed: () async {
            String newitem =
                await textInputDialog(context, 'New $listname thing?');
            if (newitem != null) {
              Map data = {};
              DataSnapshot old = await _ref.once();
              if (old.value != null) {
                data = old.value;
              }
              final int now = new DateTime.now().millisecondsSinceEpoch;
              data[newitem] = {
                '_chosen': now,
                '_next': now + myrand(2 * _info.meanChildInterval),
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

Future<String> textInputDialog(BuildContext context, String title,
    [String value]) async {
  String foo;
  return showDialog(
    context: context,
    child: new AlertDialog(
        title: new Text(title),
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
              }),
          new FlatButton(
              child: new Text('ADD'),
              onPressed: () {
                Navigator.pop(context, foo);
              }),
        ]),
  );
}

Future<bool> confirmDialog(
    BuildContext context, String title, String action) async {
  return showDialog(
      context: context,
      child: new AlertDialog(title: new Text(title), actions: <Widget>[
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

infoDialog(BuildContext context, String title, String info) async {
  return showDialog(
      context: context,
      child: new AlertDialog(
          title: new Text(title),
          content: new Text(info),
          actions: <Widget>[]));
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

Color darkColor(Color c) {
  Color dark = const Color(0xFF666666);
  Colors.primaries.forEach((p) {
    if (p[200] == c) {
      dark = p[700];
    }
  });
  return dark;
}

ColorPickerDialog pastelPicker(BuildContext context) {
  List<MaterialColor> primaries = Colors.primaries;
  List<Color> cs = new List.from(Colors.primaries);
  for (int i = 0; i < cs.length; i++) {
    cs[i] = primaries[i][200];
  }
  cs.add(const Color(0xFFdddddd));
  print('cs length ${cs.length}');
  ColorPickerGrid grid = new ColorPickerGrid(
      colors: cs,
      onTap: (Color color) {
        Navigator.pop(context, color);
      },
      rounded: false);
  return new ColorPickerDialog(body: grid);
}

int mymax(int a, int b) {
  if (a > b) return a;
  return b;
}

int myrand(int mx) {
  if (mx < 0) return 0;
  if (mx > 4294967296) {
    print('mx is too big: $mx');
    return (_random.nextDouble() * mx).toInt();
  }
  return _random.nextInt(mx);
}

class StringSelectDialog extends StatefulWidget {
  final String title;
  final List<String> options;
  StringSelectDialog({Key key, this.title, this.options}) : super(key: key);

  @override
  _StringSelectState createState() =>
      new _StringSelectState(title: title, options: options);
}

class _StringSelectState extends State<StringSelectDialog> {
  final String title;
  final List<String> options;
  String _filter = '';
  _StringSelectState({this.title, this.options});

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> buttons = [
      new TextField(
          autofocus: true,
          onChanged: (String newval) {
            setState(() {
              _filter = newval;
            });
          })
    ];
    if (options.length < 6) {
      buttons = [];
    }
    options.forEach((o) {
      if (buttons.length < 6 && matchesString(_filter, o)) {
        buttons.add(new FlatButton(
            child: new Text(o),
            onPressed: () {
              Navigator.pop(context, o);
            }));
      }
    });
    return new AlertDialog(
        title: new Text(title),
        content: new Column(children: buttons, mainAxisSize: MainAxisSize.min),
        actions: <Widget>[
          new FlatButton(
              child: const Text('CANCEL'),
              onPressed: () {
                Navigator.pop(context, null);
              }),
          new FlatButton(
              child: const Text('NONE'),
              onPressed: () {
                Navigator.pop(context, '__none__');
              }),
        ]);
  }
}

Future<String> stringSelectDialog(
    BuildContext context, String title, List<String> options) async {
  return showDialog(
      context: context,
      child: new StringSelectDialog(title: title, options: options));
}
