#!/usr/bin/env node
'use strict';

const fs = require('fs-extra');
const path = require('path');
const Parser = require('tree-sitter');
const verilog = require('../bindings/node/index.js');

function walker (cb, root) {
  return function rec (dir) {
    fs.readdir(dir).then(subdirs => {
      Promise.all(subdirs.map(subdir => {
        const res = path.resolve(dir, subdir);
        fs.stat(res).then(e => {
          if (e.isDirectory()) {
            rec(res);
          } else {
            const short = path.relative(root, res);
            const ext = path.extname(short);
            if (ext === '.svh') {
              cb(short, res);
            }
          }
        });
      }));
    });
  };
}

function inspect (root) {
  let errors = 0;
  let missing = 0;
  const rec = node => {
    if (node.type === 'ERROR') {
      errors += 1;
    } else
    if (node.isMissing()) {
      missing += 1;
    }
    const childCount = node.childCount;
    for (let i = 0; i < childCount; i++) {
      rec(node.child(i));
    }
  };
  rec(root);
  return {
    errors: errors,
    missing: missing
  };
}

function main () {
  const parser = new Parser();
  parser.setLanguage(verilog);

  // const root = path.resolve(process.cwd(), 'uvm', '1800.2-2017-1.0', 'src');
  const root = path.resolve(process.cwd(), 'uvm', '1800.2-2020-1.1', 'src');

  fs.pathExists(root).then(exists => {
    let idx = 0;
    let errors = 0;
    let missing = 0;
    let time = 0;
    if (exists) {
      let inflight = 0;
      walker((short, full) => {
        inflight += 1;
        fs.readFile(full, 'utf8').then(source => {
          inflight -= 1;
          let t = Date.now();
          const tree = parser.parse(source);
          const res = inspect(tree.rootNode);
          t = Date.now() - t;
          errors += res.errors;
          missing += res.missing;
          time += t;
          console.log(`time: ${t.toString().padStart(5)
          } ms, errors: ${res.errors.toString().padStart(5)
          }, missing: ${res.missing.toString().padStart(5)
          }, name: ${short}`);
          idx += 1;
          if (inflight === 0) {
            console.log(`files: ${idx}, errors: ${errors}, missing: ${missing}, time: ${time} ms`);
          }
        });
      }, root)(root);
    }
  });
}

main();

/* eslint no-console: 0 */
