#!/bin/bash
cp -f $(ls [% paths.data.IMAGES %]/genesis_* | sort -rn | head -n 1) [% paths.data.ROOT %]/genesis.img.xz
xz -d [% paths.data.ROOT %]/genesis.img.xz  && chmod 400 [% paths.data.ROOT %]/genesis.img
mount [% paths.data.ROOT %]/genesis.img [% paths.psi.ROOT %] 
