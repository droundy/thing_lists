# Thing Lists

An app for lists of things.  This app is designed for "things" that
you want to choose regularly, and for which you would like to not keep
choosing the same ones in order to have some variety.  Examples are
books to reread, recipes to make for dinner, songs to sing to a baby,
or books of the Bible to read next.  As humans, we are not very good
at thinking of a random thing, because what we remember is what we
recently read/cooked/sang.  This can lead to getting into a rut.

Thing Lists, allows you to create a hierarchy of lists.  Each list can
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

## 0.0.5

- Make beautiful animations when moving things.

## 0.0.4

- Make menus work again.

## 0.0.3

- Use pastel colors for easier legibility.
- Postpone more aggressively.
- Fix bug in wrapping things with very long names.
