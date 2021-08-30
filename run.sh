#!/bin/bash

meson setup build --prefix=/usr --wipe
# ninja -C build -v com.github.tudo75.xed-codecomment-plugin-pot
# ninja -C build -v com.github.tudo75.xed-codecomment-plugin-update-po
ninja -C build -v com.github.tudo75.xed-codecomment-plugin-gmo
ninja -v -C build
ninja -v -C build install
