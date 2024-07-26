<h1 align="center">Zine</h1>
<h3 align="center"><em>Fast, Scalable, Flexible Static Site Generator (SSG)</em></h3>
<p align="center">Zine is pronounced like in <a href="https://en.wikipedia.org/wiki/Zine">fan<em>zine</em></a></a>.</p>

## Development Status
Alpha stage, it's strongly recommended to first try Zine out on a small project to get a feeling of the limits of the current implementation.

## Getting Started

Go to https://zine-ssg.io to get started.


## Development

It is recommended to develop Zine against a site project (eg [kristoff-it/zine-ssg.io](https://github.com/kristoff-it/zine-ssg.io) by running `zig build` on the project and setting the Zine dependency to a local checkout in `build.zig.zon`:

`zine-ssg.io/build.zig.zon`
```zig
.{
    .name = "Zine Sample Site",
    .version = "0.0.0",
    .dependencies = .{
        .zine = .{
            .path = "../zine",
        },
    },
    .paths = .{"."},
}
```

Two flags that are going to help you develop Zine:

### `-Ddebug`
Builds Zine in debug mode, which means faster rebuilds and enabling debug logging. 

### `-Dlog=foo`
Enables logging only for the specified scope. Can be passed multiple times to enable more than one scope.

See at the top of each component what is the scope name in a declaration that looks like this:

`zine/server/main.zig`
```zig
const log = std.log.scoped(.server);
```

`super/src/sitter.zig`
```zig
const log = std.log.scoped(.sitter);
```
