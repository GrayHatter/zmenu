# ZMenu

A simple dynamic menu launcher for wayland which attempts to be the following,
in this order:

  * fast
  * useful
  * pretty


# Building

zmenu depends on [charcoal], included as a submodule until charcoal provides
tagged versions. `git clone [zmenu] --recursive` is suggested, `git submodule
update --init --remote` if it's missing.

[charcoal]: https://srctree.gr.ht/repo/charcoal

 The font file is builtin during the compile step, so you'll need to provide
 your own `font.ttf` in the root directory. Then you can try `zig build run`

If you want to install it `zig build --release=safe --prefix-exe-dir
$HOME/.bin` Please substitute your preferred path directory as needed!

An example `.zmenurc` is provided. Copy it to `$HOME/.zmenurc` to change the
default theme.
