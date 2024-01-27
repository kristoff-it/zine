# Zine

A Static Site generator (SSG).

Zine is pronounced like in fan*zine*.

## Development Status
Super alpha stage, using Zine now means participating to its development work.


## Feature Highlights
- Compile errors for malformed HTML
- Surgical dependency tracking for minimal rebuilds

## Getting Started
Clone https://github.com/kristoff-it/zine-sample-site/ and run `zig build`. 

Depends on the Zig compiler (currently tracking master branch so get an unstable
build from the official website).

## Templating Language
Zine doesn't use any of the {{ curly brace }} languages like Mustache or Jinja,
instead it features it's own language called Super.

### Templating Quickstart

`layouts/templates/base.html`
```html
<html>
  <head>
    <title id="title"><super/> - My Blog</title>
  </head>
  <body id="body">
    <super/>
  </body>
</html>
```

`base.html` defines two extension points that other templates ("super templates" in Zine lingo) can define: one is inside `<title>` and the other is inside `<body>`, each marked by the presence of `<super/>`.

Here's how a super template could extend `base.html`:

`layouts/page.html`
```html
<extend template="base.html"/>

<title id="title">A Page</title>

<body id="body">
  <h1>Hello World!</h1>
</body>
```
Extension chains can also include intermediate templates:

`layouts/templates/with-menu.html`
```html
<extend template="base.html"/>

<!-- this template doesn't care about the title so it just re-exports it as is -->
<title id="title"><super/></title>

<body id="body">
  <nav id="menu"> foo bar baz <super/> </nav>
  <super/>
</body>
```
This is how `with-menu.html` could be used by a full layout:

`layouts/page-with-menu.html`
```html
<extend "with-menu.html"/>

<title id="title">Page</title>

<nav id="menu">
  <a href="/page">Page</a>
</nav> 

<body id="hello">
  <h1>Hello World</h1>
</body>
```
### Logic
This is how you can do branching and manipulate the frontmatter metadata of your content:

`layouts/post.html`
```html
<extend "base.html"/>

<title id="title" var="$page.title"></title>

<body id="body">
  <h1 var="$page.title"></h1>
  <div loop="$page.tags" id="tags">
    <span var="$loop.it"></span>
    <span if="$loop.last.not()"> - </span>
  </div>
  <div var="$page.content"></div>
</body>
```

Logic scripts always start from a global variable (identifiers that start with a `$`) and then progress by navigating their properties and calling their builtin functions.

Currently there is no documentation for the available variables and builtins, 
but you can find them in the source code here: 

https://github.com/kristoff-it/zine/blob/main/zine/src/contexts.zig
















**NOTE: this section contains design ideas phrased as documentation. The actual
implementation of what is described in this section might or (most probably) 
might not be there yet.**

### Templating Language

The Zine templating language is designed to integrate with HTML, instead of being
a completely separate `{{ language }}`.

This is why:

- normal html syntax highlighting should not break because of the templating language
- template composition should naturally align with HTML elements; in other words
  the templating language should discourage using it to perform free-form text
  manipulation (ie macros) of this kind:
  ```html
    <a href="bar">
    {% if foo %}
      </a><a href="baz">
    {% end %}
    </a>
  ```

Parsing the templating language requires also parsing HTML, which is more 
complicated than just treating the templating language as a layer above, but 
since our goal is to output valid HTML, parsing it at compile time allows us to 
**catch syntax errors immediately, instead of outputting completely broken HTML** 
that then gets interpreted in creative ways by the browser as it attempts to make 
sense of it.

  
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
  "title": "Home",
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
     <title>Home</title>
  </head>
  <body>
    <p>Hello World!</p>
  </body>
</html>
```

#### Templated Layouts

It's common for Zine projects to have more than one layout, and it's also common
for layouts to share common boilerplate (eg the doctype, the <html> tag, etc).

Like other similar templating systems, Zine gives you the ability to create
extension chains between your layouts.

While the names of top-level directories can be customized as you please, inside
the layout directory, all template files must be placed inside the `templates/`
directory.

In Zine lingo, a "template" is a layout that has undefined block declarations.

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
  <head zine-block="head">
    <title zine-block="title"> - website.com</title>
    <meta name="description" content="official website for website.com">
  </head>
  <body zine-block="main"></body>
</html>
```

*layouts/page.html*
```html
<super template="base.html">
  <head zine-define="head">
    <super>
      <title zine-define="title">
        <span zine-inline-var="$page.title"></span> - <super/>
      </title>
    </super>
  </head>
  <body zine-define="main" zine-var="$page.content"></body>
</super>
```

Let's unpack what we're seeing here. While previously `page.html` was a 
complete layout, it now completes `base.html`.

`base.html` is the tail of the extension chain (which is very short in this 
case, we'll see later more complex examples) and as such it looks like a normal 
HTML file with just some inner parts missing.

The inner parts that are missing are defined using the `zine-block` attribute.

**Looking at the `zine-block`s of a template will tell you what the interface 
of the template is.**

All layouts that intend to complete a given template must fullfill
its interface. In this example `base.html` declares `"head"`, `"title"`, and `"main"`.

To be more precise, `base.html` declares a `<head>` named "head", a `<title>` named "title", 
and a `<body>` named "main". 

We'll see why this matters in just a moment.

#### Defining blocks

In a layout, to define a block definition from a template, the layout must use the 
`zine-define` attribute in the same type of element that the parent template 
exposes.

For example, `base.html` declares a `<body>` named "main" and so `page.html` must
define it using the same tag:

*layout*
```html
<body zine-define="main" zine-var="$page.content"></body>
```

Using a different tag results in a compilation error:

*layout*
```html
<div zine-define="main" zine-var="$page.content"></div>
```

```
layouts/page.html:10:0: error: block "main" expected to be a `<body>` element.
   <div zine-define="main" zine-var="$page.content"></div>
    ^^^

layouts/templates/base.html:4:1 note: "main" block declared here
    <body zine-block="main"></body>
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
    {{ block "main" . }}{{ end }}
</html>
```
That's easy to notice and fix once:
 
```html
<!DOCTYPE html>
<html lang="{{$lang}}">
    <head></head>
    <body>
        <div id="content">
        {{ block "main" . }}{{ end }}
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

In the previous example, `base.html` declared "title" this way:

*template*
```html
<title zine-block="title"> - website.com</title>
```

As you can see the template has some text inside the title element. That text 
is meant to be used as a suffix, in order to create titles like these:
```
Homepage - website.com
About - website.com
Page Foo - website.com
```

This is another common feature of templating languages, and in Zine this is done
by using `<super>` when defining a block:

*layout*
```html
<title zine-define="title">
  <span zine-inline-var="$page.title"></span> - <super/>
</title>

```
In this example we are placing the page's title to the left of `<super/>` in
order to obtain the intended effect.

In case we don't care about what the parent template is offering us, we can 
discard it simply by not using `<super>`:

*layout*
```html
<title zine-define="title">whatever</title>
```

#### Inheriting attributes using `super`

`super` is a keyword and not (just) a tag because it can also be used as an 
attribute.

*template*
```html
<footer zine-block="footer" style="font-size:0.5em;font-style:italic;">
 All rights reserved.
</footer>
```

*layout*
```html
<footer zine-define="footer" super>
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
  <head zine-block="head">
    <title zine-block="title"> - website.com</title>
    <meta name="description" content="official website for website.com">
  </head>
  <body zine-block="main"></body>
</html>
```

*layouts/page.html*
```html
<super template="base.html">
  <head zine-define="head">
    <super>
      <title zine-define="title">
        <span zine-inline-var="$page.title"></span> - <super/>
      </title>
    </super>
  </head>
  <body zine-define="main" zine-var="$page.content"></body>
</super>
```

As you can see in this example, `base.html` has two block declarations netsted 
into one another.

In the previous section we analyzed what was happening with regards to the 
"title" block, but ignored the fact that it's nested inside "head". This 
is a more complex example, but the solution is fundamentally the same as it 
was before when looking just at "title".

To fully re-define the entire "head" block, one can simply avoid using `super` 
altogether:

*layout*
```html
<head zine-define="head">
   <title>website.com</title>
</head>
```

To inherit the contents of "head" instead, one must define all the block 
declarations contained therein:

*layout*
```html
<head zine-define="head">
  <super>
    <title zine-define="title">website.com</title>
  </super>
</head>
```

And, recursively, one can make the same choice for any nested block declaration. 
In this last example we opted for dropping the inherited content for "title", 
but we could also have kept it like we did in a previous section.

When the content inherited from a block declaration doesn't contain any nested 
`zine-block`s, you can use the short form `<super/>` while, in the opposite 
case, you must use the full tag pair `<super></super>` because you have to 
define all nested blocks as well.

Lastly, when a layout completes a template, it must declare it's doing so by 
using a top-level `<super>` tag with a `template` attribute pointing at the 
corresponding template inside `templates/`.

This file structure is hard-coded because Zine expects all layouts outside of 
`templates/` to be leaf nodes that evaluate to a final layout (ie a layout 
without any undefined blocks).

For your convenience you are allowed to create nested directories inside both 
the layout directory and `templates/`.

#### Interpreting `super` visually

When you're looking at a layout that completes a template, you are looking at 
two different things, depending on the context:

- a concrete list of html elements that will show up as-is in the final output.
- a list of block definitions that will then be interpolated with whatever else 
  the parent template adds on top.

*layouts/templates/base.html*
```html
<!DOCTYPE html>
<html>
  <head>
    <title zine-block="title"></title>
    <meta name="description" content="official website for website.com">
  </head>
  <body zine-block="main"></body>
</html>
```
*layouts/page.html*
```html
<super template="base.html">
  <title zine-define="title">another-website.com</title>
  <body zine-define="main">
    <p>foo</p>
    <p>bar</p>
    <p>baz</p>
  </body>
</super>
```

For example, in this case "foo", "bar" and "baz" are a list of elements that 
will appear verbatim in the final output, while "title" and "main" won't even
be siblings in the final output.

To find your bearings more easily, keep in mind that what you're seeing is *not*
what you'll get only when looking at the direct chindren of a `<super>` element.

To increase visibility of which-is-what, you can add empty lines and HTML 
comments between block definitions:

*layout*
```html
<super template="base.html">

  <!-- template also includes meta tags -->
  <title zine-define="title">another-website.com</title>

  <!-- main content -->
  <body zine-define="main">
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

In all examples until now, we always had a layout complete a template without
any intermediate links, but it's fairly common to want to have a template extend
another.

*layouts/templates/base.html*
```html
<!DOCTYPE html>
<html>
  <head zine-block="head">
    <title zine-block="title"> - website.com</title>
    <meta name="description" content="official website for website.com">
  </head>
  <body zine-block="main"></body>
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
  <body zine-define="main">
    <nav zine-block="menu" style="font-style=bold;">
      <a href="/">Home</a>
    </nav>
    <div zine-block="main"></div>
  </body>
  
</super>
```

*layouts/page.html*
```html
<!-- this time we're completing a different template -->
<super template="with-menu.html">

  <!-- comments are allowed between definitions inside a super element -->
  <head zine-define="head">
    <super>
      <!-- same is true for nested <super> elements -->
      <title zine-define="title">
        <span zine-inline-var="$page.title"></span> - <super/>
      </title>
    </super>
  </head>
  
  <!-- the next block also inherits all attributes defined in the parent's nav tag -->
  <nav zine-define="menu" super>
    <super/>
    - <span zine-var="$page.title"></span> 
  </nav>
  
  <!-- in this template "main" is a div, not <body> -->
  <!-- maybe not a great idea, but at least we know -->
  <div zine-define="main" zine-var="$page.content"></div>
  
</super>
```

The concept is truly straight-forward once you think about it: to extend a 
template you must define its blocks, and in turn expose new block declarations
of your own so that a final layout can define those instead.

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
is doing with "main". In `base.html` "main" is declared as a simple `<body>` 
element, but `with-menu.html` wants to hardcode in there a `<nav>` element and 
have consumer layouts place their "main" content next to it.

To achieve that, `with-menu.html` defines "main" from `base.html` and exposes its
own version of "main". Note that here the intent is to force the consumer layout 
to include the navigation menu, without any way of avoiding it. We'll see later
a less forceful version this idea.

*template*
```html
<body zine-define="main">
  <nav zine-block="menu" style="font-style=bold;">
    <a href="/">Home</a>
  </nav>
  <div zine-block="main"></div>
</body>
```

It's up for debate whether `with-menu.html` should have given a different name 
to its new "main" block or not, since what was before a `<body>` block has now 
become a div. In any case, the final layout will know which is going to be the 
container element for the block, since it has to use the correct element anyway.

When a template wants to "re-export" a block declaration from the template it's 
extending, it can use `zine-extend`:

*template*
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
as `base.html`. To do so it has to both define and expose it again, and that's 
what `zine-extend` does all at once.

In a sense `zine-extend` is like doing both `zine-define` and `zine-block` on the
same element, using the same name twice.

*template*
```html
<title zine-define="title" zine-block="title"><super/></title>
```
Note that the above is only meant to show the concept and it's actually a 
compile error (what will tell you to use `zine-extend` instead).

That said, you are allowed to use both attributes to rename a definition, if 
that's what you want.

*template*
```html
<!-- this is actually ok -->
<title zine-define="title" zine-block="cool-title"> ⚡ <super/></title>
```

If `with-menu.html` wanted to give consumers the option of removing the 
navigation menu, then it could have used `zine-extend` instead, like so:

*template*
```html
<body zine-extend="main">
  <nav zine-block="menu" style="font-style=bold;">
    <a href="/">Home</a>
  </nav>
</body>
```

That's definitely more permissive and flexible than before, but it's also more
open to misuse, like moving the navigation menu below the main content by mistake.

*layout*
```html
<body zine-define="main">
  <div> Hello World </div>
  <super>
    <nav zine-define="menu"><super/></nav>
  </super>
</body>
```


#### For, if and other operators

TODO
