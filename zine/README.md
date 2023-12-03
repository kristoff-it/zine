# Zine

An SSG: Static Stuff Generator (stuff=website for most people).

Zine is pronounced like in magazine.

## Development Status
Alpha stage, come back in a while.


## Design
**NOTE: this section contains design ideas phrased as documentation. The actual
implementation of what is described in this section might or (most probably) 
might not be there yet.**

### Templating Language

The Zine templating language differs from other common templating languages in 
order to fullfill the following goals:

#### Introduction to Layouts
In Zine a "layout" is an html file used to style content.

This is how a simple Zine project looks like:
```
.
├── build.zig
├── build.zig.zon
├── content
│   └── index.md
└── layouts
    └── page.html
```

All markdown files must declare the layout they intend to use.

*content/index.md*
```md
---
  ...
  "title": "Homepage",
  "layout": "page.html",
  ...
---
Hello World!
```

*layouts/page.html*
```html
<!DOCTYPE html>
<html>
  <head>
    <title zine-var="$page.title"></title>
  </head>
  <body zine-var="$page.content"></body>
</html>
```

*output*
```html
<!DOCTYPE html>
<html>
  <head>
     <title>Homepage</title>
  </head>
  <body>
    <p>Hello World!</p>
  </body>
</html>
```

#### Templated Layouts

It's common for Zine project to have more than one layout, and it's also common
for layouts to share common boilerplate (eg the doctype, the <html> tag, etc).

Like other similar templating systems, Zine gives you the ability to create
extension chains between your layouts.

While the names of top-level directories can be customized as you please, inside
the layout directory, all template files must be placed inside the `templates`
directory.

In Zine lingo, a "template" is a layout that has unresolved definitions.

Here's an example:

```
.
├── build.zig
├── build.zig.zon
├── content
│   └── index.md
└── layouts
    ├── page.html
    └── templates
        └── base.html
```

*layouts/templates/base.html*
```html
<!DOCTYPE html>
<html>
  <head zine-define="head">
    <title zine-define="title"> - website.com</title>
    <meta name="description" content="official website for website.com">
  </head>
  <body zine-define="main"></body>
</html>
```

*layouts/page.html*
```html
<super template="base.html">
  <head zine-block="head">
    <super>
      <title zine-block="title">
        <span zine-inline-var="$page.title"></span> - <super/>
      </title>
    </super>
  </head>
  <body zine-block="main" zine-var="$page.content"></body>
</super>
```


Let's unpack what we're seeing here.

While previously `page.html` was a complete layout, it now implements `base.html`.

`base.html` is the tail of the extension chain (we'll see later more complex examples)
and as such it looks like a normal HTML file with just some inner parts missing.

The inner parts that are missing are defined using the `zine-define` attribute.

**Looking at the `zine-define`s of a template will tell you what the interface 
of the template is.**

All layouts and templates that intend to implement a given template must fullfill
its interface.

In this example `base.html` defines `"head"`, `"title"`, and `"main"`.

To be more precise, `base.html` defines a `<head>` named "head", a `<title>` named "title", 
and a `<body>` named "main". 

We'll see why this matters in just a moment.

#### Resolving a template's definitions

To fullfill a definition in a template, a layout must use the `zine-block` attribute 
in the same type of element that the parent template exposes.

For example, `base.html` defines a `<body>` named "main" and so `page.html` must
fullfill it using the same tag:

```html
<body zine-block="main" zine-var="$page.content"></body>
```

Using a different tag results in a compilation error:


```html
<div zine-block="main" zine-var="$page.content"></div>
```

```
layouts/page.html:10:0: error: block "main" expected to be a `<body>` element.
   <div zine-block="main" zine-var="$page.content"></div>
    ^^^

layouts/templates/base.html:4:1 note: "main" block defined here
    <body zine-define="main"></body>
```

This might seem a bit verbose but it gives us a lightweight form of *typed* 
templating: in Zine we always know what is the container element that our
layout is going to fill in.

Contrast this with Hugo (and similar systems):

```
{{ define "main" }}
   <p> Hello World </p>
{{ end }}
```

Where is the parent template going to put our content? In a div nested inside
of `<body>`? Directly under `<body>`? What if we are meant to specify our own 
container element?

This last situation can actually happen fairly easily even by mistake. All it 
takes is for `baseof.html` to look like this:

```html
<!DOCTYPE html>
<html lang="{{$lang}}">
    <head></head>
    {{- block "main" . }}{{- end }}
</html>
```
That's easy to notice and fix once:
 
```html
<!DOCTYPE html>
<html lang="{{$lang}}">
    <head></head>
    <body>
        <div id="content">
        {{- block "main" . }}{{- end }}
        </div>
    </body>
</html>
```

But even when done correctly it's easy to forget which is going to be the 
container element, and end up with unwanted `<body><div><div>` situations, 
which in turn make it harder to get CSS styling right.

Using HTML tags as the block unit, we drive the templating logic to be more 
typed and well-behaved. It's virtuous redundancy.

Later we'll see that it's still possible to use the Zine templating language
to perfrom arbitrary text replacement, but the main extension system tries 
to steer you towards the right path.

#### The `super` keyword

In the previous example, `base.html` defined "title" as such:
```html
<title zine-define="title"> - website.com</title>
```

As you can see the template has some text inside the title definition.

That text is meant to be used as a suffix, in order to create titles like these:
```
Homepage - website.com
About - website.com
Page Foo - website.com
```

This is another common feature of templating languages, and in Zine this is done
by using `<super>` when fullfilling the definition in a `zine-block`:

```html
<title zine-block="title">
  <span zine-inline-var="$page.title"></span> - <super/>
</title>

```
In this example we are placing the page's title to the left of `<super/>` in
order to obtain the intended effect.

In case we don't care about what the parent template is offering us, we can 
discard it simply by not using `<super>`:

```html
<title zine-block="title">whatever</title>
```

#### Inheriting attributes using `super`

This section calls `super` a keyword and not a tag because it can also
be used as an attribute.

```html
<footer zine-define="footer" style="font-size:0.5em;font-style:italic;">
 All rights reserved.
</footer>
```

```html
<footer zine-block="footer" super>
  CC-3.0-BY
</footer>

```

In this example we declined to inherit the parent template's `<footer>` contents
but we still wanted to inherit the `style` attribute (and any other non-zine-prefixed
attributes).

Note that duplicate attributes will cause a compile error. 

#### A more complex usage of `super`

Let's take a look at the templating example from before one last time.

*layouts/templates/base.html*
```html
<!DOCTYPE html>
<html>
  <head zine-define="head">
    <title zine-define="title"> - website.com</title>
    <meta name="description" content="official website for website.com">
  </head>
  <body zine-define="main"></body>
</html>
```

*layouts/page.html*
```html
<super template="base.html">
  <head zine-block="head">
    <super>
      <title zine-block="title">
        <span zine-inline-var="$page.title"></span> - <super/>
      </title>
    </super>
  </head>
  <body zine-block="main" zine-var="$page.content"></body>
</super>
```

As you can see in this example, `base.html` has two definitions netsted into 
one another.

In the previous section we analyzed what was happening with regards to the 
"title" definition, but ignored the fact that it's nested inside "head". This 
is a more complex example, but it's solution is fundamentally the same as it 
was before when looking just at "title".

If one wants to fully re-define the entire "head" block, one can simply avoid
using `super` altogether:

```html
<head zine-block="head">
   <title>website.com</title>
</head>
```

If instead one wants to inherit the contents of "head", then they must fullfill
all the definitions contained therein:

```html
<head zine-block="head">
  <super>
    <title zine-block="title">website.com</title>
  </super>
</head>
```

And, recursively, one can make the same choice for any nested definition. In
this last example we opted for dropping the inherited content for "title", but
we could also have kept it like we did in a previous section.

When the content inherited from a definition doesn't contain any nested 
`zine-define`, you can use the short form `<super/>`, while in the opposite 
case you must use the full tag pair `<super></super>` because you have to 
fullfill all defines with a corresponding `zine-block` child.

Lastly, when a layout implements a template, it must declare it's doing so by using
a top-level `<super>` tag with a `template` attribute pointing at the 
corresponding template inside `templates/`.

This file structure is hard-coded because Zine expects all layouts outside of 
`templates/` to be leaf nodes that evaluate to a final layout (ie a layout 
without any unfulfilled definitions).

For your convenience you are allowed to create nested directories inside both 
the layout directory and `templates/`.

#### Interpreting `super` visually

When you're looking at a layout that implements a template, you are looking at 
two different things, depending on the context:

- a concrete list of html elements that will show up as-is in the final output.
- a list of blocks that will then be interpolated with whatever else the parent
  template adds on top.

*layouts/templates/base.html*
```html
<!DOCTYPE html>
<html>
  <head>
    <title zine-define="title"></title>
    <meta name="description" content="official website for website.com">
  </head>
  <body zine-define="main"></body>
</html>
```
*layouts/page.html*
```html
<super template="base.html">
  <title zine-block="title">another-website.com</title>
  <body zine-block="main">
    <p>foo</p>
    <p>bar</p>
    <p>baz</p>
  </body>
</super>
```

For example, in this case "foo", "bar" and "baz" are a list of elements that 
will appear verbatim in the final output, while "title" and "body" won't even
be siblings in the final output.

To more easily find your bearings, keep in mind that what you're seeing is *not*
what you'll get only when looking at the direct chindren of a `<super>` element.

To increase visibility of which-is-what, you can add empty lines and HTML 
comments between blocks:

```html
<super template="base.html">

  <!-- template also includes meta tags -->
  <title zine-block="title">another-website.com</title>

  <!-- main content -->
  <body zine-block="main">
    <p>foo</p>
    <p>bar</p>
    <p>baz</p>
  </body>
  
</super>
```

Note that only HTML comments are allowed between block definitions. Anything 
else will result in a compile error. HTML comments placed between blocks will
not be present in the final output.

#### Templates extending templates

In all examples until now, we always had a layout implement a template without
any intermediate links, but it's fairly common to want to have a template extend
another (and have the final layout implement that one).

*layouts/templates/base.html*
```html
<!DOCTYPE html>
<html>
  <head zine-define="head">
    <title zine-define="title"> - website.com</title>
    <meta name="description" content="official website for website.com">
  </head>
  <body zine-define="main"></body>
</html>
```

*layouts/templates/with-menu.html*
```html
<super template="base.html">

  <!-- adds some totally necessary JS -->
  <head zine-extend="head">
    <super>
      <title zine-extend="title"><super/></title>
    </super>
    <script>
      console.log("Hello world");
    </script>
  </head>

  <!-- adds a menu and pushes the main content into a div -->
  <body zine-block="main">
    <nav zine-define="menu" style="font-style=bold;">
      <a href="/">Home</a>
    </nav>
    <div zine-define="main"></div>
  </body>
  
</super>
```

*layouts/page.html*
```html
<!-- this time we're implementing a different template -->
<super template="with-menu.html">

  <!-- comments are allowed between definitions inside a super element -->
  <head zine-block="head">
    <super>
      <!-- same is true for nested <super> elements -->
      <title zine-block="title">
        <span zine-inline-var="$page.title"></span> - <super/>
      </title>
    </super>
  </head>
  
  <!-- the next block also inherits all attributes defined in the parent's nav tag -->
  <nav zine-block="menu" super>
    <super/>
    - <span zine-var="$page.title"></span> 
  </nav>
  
  <!-- in this template "main" is a div, not <body> -->
  <!-- maybe not a great idea, but at least we know -->
  <div zine-block="main" zine-var="$page.content"></div>
  
</super>
```

The concept is truly straingt-forward once you think about it: to extend a 
template you must fullfill its definitions, and in turn you must expose new
definitions of your own so that a final layout can fullfill those instead.

Interface exposed by `base.html`:
```
base.html  
├── "head"
│   └── "title"
└── "main"
```

Interface exposed by `with-menu.html`:
```
with-menu.html  
├── "head"
│   └── "title"
├── "menu"
└── "main"
```

A slightly involved, but ultimately very clear example is what `with-menu.html` 
is doing with "main". In `base.html` "main" is defined as a simple `<body>` 
element, but `with-menu.html` wants to hardcode in there a `<nav>` element and 
have the final layout place its "main" content next to it.

To achieve that, `with-menu.html` fulfills "main" from `base.html` and exposes its
own version of "main". Note that here the intent is to force the consumer layout 
to include the navigation menu, without any way of avoiding it. We'll see later
a more flexible take on this general idea.

```html
<body zine-block="main">
  <nav zine-define="menu" style="font-style=bold;">
    <a href="/">Home</a>
  </nav>
  <div zine-define="main"></div>
</body>
```

It's up for debate whether `with-menu.html` should have given a different name 
to its new definition of "main" or not, since what was before a `<body>` block 
has now become a div. In any case the final layout will know which is going to 
be the container element for the block, since it has to use the correct tag 
anyway.

When a template wants to "re-export" a definition from the template it's 
extending, it can use `zine-extend`:

```html
<head zine-extend="head">
  <super>
    <title zine-extend="title"><super/></title>
  </super>
  <script>
    console.log("Hello world");
  </script>
</head>
```
Here `with-menu.html` wants to offer the same interface for "head" (and "title")
as `base.html`. To do so it has to both fullfill the definition and expose it 
again, and that's what `zig-extend` does all at once.

In a sense `zig-extend` is like doing both `zig-block` and `zig-define` on the
same element.

```html
<title zine-block="title" zine-define="title"><super/></title>
```
Note that the above is only meant to show the concept and it's actually a 
compile error (what will tell you to use `zig-extend` instead).

That said you are allowed to use both attributes to rename a definition, if 
that's what you want.

```html
<!-- this is actually ok -->
<title zine-block="title" zine-define="cool-title"> ⚡ <super/></title>
```

#### For, if and other operators

TODO
