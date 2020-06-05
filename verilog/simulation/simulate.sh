#!/bin/bash

rm -f a.out
rm -f dump.vcd

iverilog frame_buffer_tb.v ../src/frame_buffer.v
./a.out
gtkwave -g -a signals.gtkw dump.vcd
