#|
In episodes 7_ and 8_ I discussed a few techniques to process
lists; however, there is much more to say on the topic. In this
episode and in the next one I will show a few tricks to work on lists
in a functional way. There are two hidden goals behind those
exercises: discuss a few common functional idioms and to pave the way
for part IV of this series, i.e. advanced macro programming. After
all, macro programming is nothing else than manipulation of code seen
as a nested list of expressions.

.. _7: http://www.artima.com/weblogs/viewpost.jsp?thread=240781
.. _8: http://www.artima.com/weblogs/viewpost.jsp?thread=240793
.. _9: http://www.artima.com/weblogs/viewpost.jsp?thread=240804
.. _11: http://www.artima.com/weblogs/viewpost.jsp?thread=240833

The APS library
-----------------------------------------------------------------

The R6RS standard library provides a few list utilities and the SRFI-1
provides a few others, however they are by no means complete.
You will likely need a few other list processing utilities when working 
with lists. Therefore I have decided to provide an utility library
which will be useful even for future episodes of my *Adventures*.

With a remarkable lack of fantasy, I have decided to call the library
``list-utils`` and to put it in a package called ``aps`` (*aps* of
course stands for *Adventures of a Pythonista in Schemeland*).
That means that I am contributing to the entropy and littering the world
with my own versions of utilities that should be more or less standard,
but this cannot be helped.

For you convenience, I have added in the library the Python-style utilities
``range``, ``zip``, ``transpose``, ``enumerate`` I did discuss in episodes 7_
and 8_, as well as the ``let+`` list destructuring
macro I introduced recently, and other things. Moreover, the ``aps`` package
contains the testing framework discussed in episode 11_, renamed as
``(aps test-utils)`` and slightly improved.
The ``aps`` library includes a more recent version of ``sweet-macros``
than the one I discussed in episode 9_, so you should replace the
old one if you have it.

You can download the package from here: http://www.phyast.pitt.edu/~micheles/scheme/aps.zip

Just unzip the archive and put the files somewhere in your path::

 $ cd <DIRECTORY-IN-YOUR-SCHEME-PATH>
 $ unzip aps.zip
 inflating: sweet-macros.sls
 inflating: aps/cut.sls
 inflating: aps/test-utils.sls      
 inflating: aps/list-utils.sls
 ...

You can test the library as follows::

 $ ikarus --r6rs-script aps/test-all.ss
 .........................
 Run 25 tests. 25 passed, 0 failed

Currently all the tests pass with the latest development version of Ikarus.
They also pass with the latest development version of Ypsilon and with
PLT Scheme version 4, except for
the test "zip-with-error". However, this is an expected failure, since the
error messages are different between Ikarus, Ypsilon and PLT Scheme.

PLT Scheme is not supported as well as I would, and I will accept patches
from PLT experts willing to help me; the nontrivial part is supporting
``sweet-macros`` fully.

Larceny Scheme is not supported since it does not support the ``.IMPL.sls``
convention. When it does, it could be supported as well, expecially if I
get some help from my readers.

Notice that you should consider the ``aps`` libraries as
experimental and subject
to changes and evolution, at least until I finish the series, in an
indetermined and far away future ;)

You can try the ``(aps list-utils)`` library as follows::

 > (import (aps list-utils))
 > (enumerate '(a b c))
 ((0 a) (1 b) (2 c))

The most important facility in the library is a syntax for
list comprehension. Perhaps list comprehension is not the greatest discovery
in computer science since sliced bread, but I find them 
enormously more readable than ``map`` and ``filter``,
which I use only in the simplest case. Nowadays, a lot
of languages are adopting them, including Haskell,
Python, Javascript and C#.

Implementing list comprehension
-----------------------------------------------------

Scheme does not provide a list comprehension syntax out of the box,
but obviously it is a simple exercise in macrology to implement them.
Actually there are many available implementations of list comprehension
in Scheme. There is even an SRFI (SRFI-42 `Eager
Comprehensions`_) which however I do not like at all since
it provides too much functionality and an ugly syntax.

Therefore, here I will pursue a different approach to
list comprehension, which is shamelessly copied from
the work of `Phil Bewig`_, with minor simplifications, and
the usage of ``let+`` instead of regular ``let``.

Here is the implementation

$$list-utils:LIST-OF

We see here the usage of an helper macro ``list-of-aux`` and the
usual accumulator trick to collect the arguments of the macro.
Here are a few test cases:

$$TESTS

The macro is able to define nested list comprehensions at any
level of nesting; the rightmost variables corresponds to the inner
loops and its is even possible to implement constraints and destructuring:
basically, we have the same power of Python list comprehensions, except
that that the objects in the ``in`` clause must be true lists, whereas
in Python they can be generic iterables (including infinite ones).

.. _Eager Comprehensions: http://srfi.schemers.org/srfi-42/srfi-42.html
.. _Phil Bewig: http://schemephil.googlepages.com/

A tricky point
-----------------------------------------------

On the surface, the ``list-of`` macro looks the same as Python
*list comprehension*; however, there a few subtle differences under
the hood, since the loop variables are treated differently.
You can see the different once you consider a list comprehension
containing closures.
In Scheme a list comprehensions of closures works as you would expect::

 > (define three-thunks (list-of (lambda () i) (i in '(0 1 2))))
 > (list-of (t) (t in three-thunks))
 (0 1 2)

In Python instead you get a surprising result (unless you really know
how ``for`` loops work)::
 
 >>> three_thunks = [(lambda : i) for i in [0, 1, 2]]
 >>> [f() for f in three_thunks]
 [2, 2, 2]

The reason is that Python is not really a functional language,
so that the ``for`` loop works by *mutating* the loop variable ``i``:
since the thunk is called after the end at the loop, it sees the
latest value of ``i``, i.e. 2. The same is true in Common Lisp
if you use the LOOP macro. In Scheme instead (and in Haskell,
the language that invented list comprehension) there is
*no mutation* of the loop variable: at each iteration a new 
fresh ``i`` is created. You can emulate in Python what Scheme does
for free by using two lambdas::

 >>> three_thunks = [(lambda x : (lambda : x))(i) for i in [0, 1, 2]]
 >>> [f() for f in three_thunks]
 [0, 1, 2]

(another way of course is to use the well know default argument trick,
with a single ``lambda i=i: i``, but that is not a direct translation
of how Scheme of Haskell work by introducing a new scope at each
iteration).

On the other hand, Python wins on Scheme for what concern polymorphism:
in Python is it possible to iterate on any iterable without any effort,
whereas in Scheme you need to specify the data structure you are
iterating over. For instance, if you want to iterate on vectors you
need to define a ``vector-of`` macro for vector comprehension; if
you want to interate on hash table you need to define an hash-table
comprehension macro ``hash-table-of``, and so on. Alternatively, you
must convert you data structure into a list and use ``list-of``.
This is annoying. In Python on the contrary there is a common
protocol for all iterable objects so that the same ``for`` syntax
can be used everywhere.

The list comprehension defined here only works for finite iterables;
Python however has also a generator comprehension that works on
potentially infinite iterables. Scheme too allows to define infinite
iterables, the so called *streams*, which however are a functional
data structure quite different from Python generators, which are
imperative. Discussing *streams* will need a whole episode, and we
will consider them in the future. For the moment, have patience!

|#

(import (rnrs) (aps list-utils) (aps test-utils))

(run
;;TESTS
   
   (test "simple comprehension"
         (list-of (* 2 x) (x in (range 3))) '(0 2 4))
   
   (test "double comprehension"
         (list-of (list x y) (x in '(a b c)) (y in '(1 2)))
         '((a 1) (a 2) (b 1) (b 2) (c 1) (c 2)))


   (test "double comprehension with constraint"
         (list-of (list x y) (x in (range 3)) (y in (range 3)) (= x y)) 
         '((0 0) (1 1) (2 2)))

   (test "comprehension plus destructuring"
         (list-of (+ x y) ((x y) in '((1 2)(3 4))))
         '(3 7))

 ;;END
   )