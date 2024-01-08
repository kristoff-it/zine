#!/usr/bin/bash

# curl https://www.accellera.org/images/downloads/standards/uvm/Accellera-1800.2-2017-1.0.tar.gz -o uvm.tar.gz
curl https://www.accellera.org/images/downloads/standards/uvm/UVM-18002-2020-11tar.gz -o uvm.tar.gz

mkdir uvm
tar -xvf uvm.tar.gz -C uvm
# verilator -E -P -Iuvm/1800.2-2017-1.0/src/ uvm/1800.2-2017-1.0/src/uvm_pkg.sv > uvm.prep.sv
