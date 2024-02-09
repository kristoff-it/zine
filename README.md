# Zine
Fast, Scalable, Flexible Static Site Generator (SSG)

Zine is pronounced like in fan*zine*.

## Development Status
Super alpha stage, using Zine now means participating to its development work.

## Getting Started

Go to https://zine-ssg.io to get started.


## Development

It is recommended to develop Zine against a site project (eg zine-sample-site) by running `zig build` on the project and setting the Zine dependency to a local checkout in `build.zig.zon`:

`zine-sample-site/build.zig.zon`
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
Enables logging only for the specified scopes. Can be passed multiple times to enable more than one scope.

See at the top of each component what is the scope name in a declaration that looks like this:

`zine/server/main.zig`
```zig
const log = std.log.scoped(.server);
```

`super/src/sitter.zig`
```zig
const log = std.log.scoped(.sitter);
```
