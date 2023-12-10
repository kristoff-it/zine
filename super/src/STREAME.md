
const std = @import("std");


# TODO: Write a parser for the language

I'm working on a static website generator called Zine.
It leverages the Zig build system and features it's own templating language.
The templating language also comes with a scripting language that you can
put inside HTML attributes.

This is the language:
"$post.draft.and($post.date.isFuture().or($post.author.is('loris-cro')))"

I use it in my templating language to do this kind of stuff:
<nav id="menu" loop="$site.sections">
   <a href="$loop.it.path" var="$loop.it.name" if="$loop.it.is($page).not()"></a>
   <span var="$loop.it.name" else></span>
</nav>

I just finished writing the tokenizer, so the parser is next.

BRB lunch


