function log() {
  console.log("[Zine Reloader]", ...arguments);
}

function zineConnect() {
  let socket = new WebSocket("ws://" + window.location.host + "/__zine/ws");

  socket.addEventListener("open", (event) => {
   log("connected");
  });

  // Listen for messages
  socket.addEventListener("message", (event) => {
    const msg = JSON.parse(event.data);

    if (msg.command == "reload") {
      log("reload", msg.path);

      if (msg.path.endsWith(".html")) {
        let path = window.location.pathname;
        if (path.endsWith('/')) path = path + 'index.html';

        if (path == msg.path) {
          location.reload();
        }
      } else if (msg.path.endsWith(".css")) {
        const links = document.querySelectorAll("link");
        for (let i = 0; i < links.length; i++) {
          const link = links[i];
          if (link._zine_temp) continue;
          
          let url = new URL(link.href);
          if (url.pathname == msg.path) {
            const now = Date.now();
            url.search = now;
            let copy = link.cloneNode(false);
            copy.href = url;
            link._zine_temp = true;
            link.parentElement.appendChild(copy);
            setTimeout(function(){
              link.remove();
            }, 200);

            break;
          }
        }
      } else if (msg.path.match(/\.(jpe?g|png|gif|svg|webp)$/i)) {
        for (let i = 0; i < document.images.length; i++) {
          const img = document.images[i];
          let url = new URL(img.src);
          if (url.pathname == msg.path) {
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
    } else if (msg.command == "build"){
      const id = "__zine_build_box";
      if(msg.err != "") {
        let box = document.getElementById(id);
        if (box == null) {
          box = document.createElement("pre");
          box.style = "position: absolute; top: 0; left: 0; width: 100vw; height: 100vh;color: white; background-color: black;z-index:100; overflow-y: scroll; margin: 0; padding: 5px; font-family: monospace;";
          box.id = id;
          document.body.appendChild(box); 
        }
        box.innerHTML = "<h1 style=\"color: red\">ZINE BUILD ERROR</h1>" + msg.err;
      } else {
        let box = document.getElementById(id);
        if (box != null) box.remove();
      }
    } else {
      log("unknown command:", msg.command, msg);
    }
    
  });

  socket.addEventListener("close", (event) => {
    log("close", event);
    setTimeout(zineConnect, 3000);
  });
  
  socket.addEventListener("error", (event) => {
    log("error", event);
  });
}

zineConnect();
