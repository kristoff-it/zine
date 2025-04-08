let eqns = document.querySelectorAll("script[type='math/tex']");
for (let i=eqns.length-1; i>=0; i--) {
    let eqn = eqns[i];
    let src = eqn.text;
    let d = eqn.closest('p') == null; 
    eqn.outerHTML = temml.renderToString(src, { displayMode: d });
}

