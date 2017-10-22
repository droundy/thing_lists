# Thing Lists

Thing Lists keeps track of lists of "things", such as recipes, books,
or music.  In particular, its specialty is on things that you want to
choose one of from time to time, and you don't want to keep picking
the same one.  You can "select" a given item (swipe right) to indicate
that you have chosen that one, or you can "postpone" it (swipe left) to
say you'd rather see it later.

Thing Lists allows you to create a hierarchy of lists.  Each list can
have a bunch of elements, and you can color those elements as you
like, or rename or delete them.  So far, Thing Lists is like any of
the other hundred thousand list apps.

The distinctive dynamic of thing lists is that you can swipe right to
"select" a thing, or swipe left to "postpone" a thing.  The things are
sorted in rough order of what to do next.  Postponing a thing moves it
further down the list.  Selecting it will also move it down the list,
but will do so using a different heuristic.  Thing List keeps track of
when you last selected each thing, and assumes that you are likely to
want to select it with similar frequency.  Thus Thing Lists at a very
simple level will learn how often you would prefer to choose each
thing and will make its recommendations accordingly.  If you make
tacos every week, but only make sushi every few months, Thing Lists
will learn and suggest you make tacos more often than it suggests
sushi.

## ChangeLog

## 0.0.8

- Make search bar color match the thing list color.
- Make scheduling after choosing an item revert to the mean.
- Add menu item to view historical information about an item.

## 0.0.7

- Use item color to set theme color, so each list can have a different
  theme color.
- Make scheduling of things after an item is selected nonrandom.
- Enable input of dependencies between things, as in books within a
  sequence, which should be read in that order through a "follows"
  menu.

## 0.0.6

- Make menu easier to select.
- Better behavior when the thing you selected is expected to be
  re-selected very soon.

## 0.0.5

- Make beautiful animations when moving things.

## 0.0.4

- Make menus work again.

## 0.0.3

- Use pastel colors for easier legibility.
- Postpone more aggressively.
- Fix bug in wrapping things with very long names.
