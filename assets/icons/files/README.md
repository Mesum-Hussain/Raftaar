# Explorer file icons

The explorer shows each file with the glyph of its language or type. The glyphs are from
[Seti UI](https://github.com/jesseweed/seti-ui) by Jesse Weed, MIT licensed
([LICENSE-Seti.md](LICENSE-Seti.md)), copied from commit
`2d6c5e68b4ded73c92dac291845ee44e1182d511` (2025-10-28). They are unchanged but for `zip.svg`, whose
zipper teeth stop at its stem: white shapes cut out what they cover, and must not overlap. `code.svg`
is raftaar's own, for languages Seti has no glyph for. Names and marks of languages and tools belong to
their owners.

A language's icon is the `icon` key of its grammar in `runtime/syntax` (`icon = rust orange`);
[types.txt](types.txt) maps the other files, and names that beat their grammar's icon. The color is
a name, which each theme turns into one of its own colors.

To add an icon, put its SVG here and use its name, then regenerate:

```sh
python3 tools/file-icons.py
python3 tools/icons.py
```

`file-icons.py` flattens the SVGs into `contours.json` (Python standard library only), and
`icons.py` writes the icon programs and tables into `src/gfx/icondata.s` and the icon numbers into
`src/raftaar.inc`. Builds use the generated files.
