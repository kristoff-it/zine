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












### Design considerations

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

Here are some examples:


#### HTML syntax errors
`page.html`
```html
<h1>Oops!<h1>   
```
output:
```
$ zig build

---------- ELEMENT MISSING CLOSING TAG ----------
While it is technically correct in HTML to have a non-void element 
that doesn't have a closing tag, it's much more probable for
it to be a programming error than to be intended. For this
reason, this is a syntax error.

[closing_tag_missing]
(page.html) /home/kristoff/zine-sample-site/layouts/page.html:19:5:
    <h1>Oops!<h1>
     ^^
trace:
    layout `page.html`,
    content `_index.md`.
```

`page.html`
```html
<div id="foo" id="oops"></div>
```
output:
```
$ zig build


---------- DUPLICATE ATTRIBUTE ----------
HTML elements cannot contain duplicate attributes.

[duplicate_attr]
(page.html) /home/kristoff/zine-sample-site/layouts/page.html:19:18:
    <div id="foo" id="oops"></div>
                  ^^

node: previous instance was here:
(page.html) /home/kristoff/zine-sample-site/layouts/page.html:19:9:
    <div id="foo" id="oops"></div>
         ^^
trace:
    layout `page.html`,
    content `_index.md`.
```

