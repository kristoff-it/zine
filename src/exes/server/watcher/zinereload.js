function log() {
  console.log("[Zine Reloader]", ...arguments);
}

let socket = new EventSource("http://" + window.location.host + "/__zine/sse");

socket.onopen = (event) => {
  log("connected", event);
};

// Listen for custom event
socket.addEventListener("reload", (event) => {
  log("reload", event.data);

  if (event.data.endsWith(".html")) {
    let path = window.location.pathname;
    if (path.endsWith('/')) path = path + 'index.html';

    if (path == event.data) {
      location.reload();
    }
  } else if (event.data.endsWith(".css")) {
    const links = document.querySelectorAll("link");
    for (let i = 0; i < links.length; i++) {
      const link = links[i];
      if (link._zine_temp) continue;

      let url = new URL(link.href);
      if (url.pathname == event.data) {
        const now = Date.now();
        url.search = now;
        let copy = link.cloneNode(false);
        copy.href = url;
        link._zine_temp = true;
        link.parentElement.appendChild(copy);
        setTimeout(function () {
          link.remove();
        }, 200);

        break;
      }
    }
  } else if (event.data.match(/\.(jpe?g|png|gif|svg|webp)$/i)) {
    for (let i = 0; i < document.images.length; i++) {
      const img = document.images[i];
      let url = new URL(img.src);
      if (url.pathname == event.data) {
        const now = Date.now();
        url.search = now;
        img.src = url;
      }
    }

    for (let i = 0; i < document.styleSheets.length; i++) {
      const style = document.styleSheets[i];
      log("TODO: implement image reload in stylesheets");
    }

    const inlines = this.document.querySelectorAll("[style*=background]");
    for (let i = 0; i < inlines.length; i++) {
      const style = inlines[i];
      log("TODO: implement image reload in inline stylesheets");
    }
  }
});

socket.addEventListener("build", (event) => {
  log("build", event.data);
  const id = "__zine_build_box";
  if (event.data != "") {
    let box = document.getElementById(id);
    if (box == null) {
      box = document.createElement("pre");
      box.style = "position: absolute; top: 0; left: 0; width: 100vw; height: 100vh;color: white; background-color: black;z-index:100; overflow-y: scroll; margin: 0; padding: 5px; font-family: monospace;";
      box.id = id;
      document.body.appendChild(box);
    }
    box.innerHTML = "<h1 style=\"color: red\">ZINE BUILD ERROR</h1>" + event.data;
  } else {
    let box = document.getElementById(id);
    if (box != null) box.remove();
  }
});

// just in case..
socket.addEventListener("close", (event) => {
  log("close", event);
  socket.close();
});

socket.onmessage = function (event) {
  log("New message", event.data);
};

socket.onerror = (err) => {
  log("error", err);
};

