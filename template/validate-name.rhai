// cargo-generate's pre hook (cargo-generate.toml's [hooks]): the project name, `-` as `_`, is
// the crate's name in Rust code. Refused here, before a file is written -- past here only cargo
// and rustc would say so -- a name that is:
//   - no ASCII identifier: `3d-tool` (cargo: "the name cannot start with a digit");
//   - a keyword, strict or reserved, edition 2024 (the reference's list) or `_`: `fn`, `self`,
//     `gen` -- the binary's `use <name>::...` would not parse.
// cargo-generate runs the hook from the template and does not copy it into the project.
let name = variable::get("crate_name");
let keywords = [
    "_", "Self", "abstract", "as", "async", "await", "become", "box", "break", "const", "continue",
    "crate", "do", "dyn", "else", "enum", "extern", "false", "final", "fn", "for", "gen", "if",
    "impl", "in", "let", "loop", "macro", "match", "mod", "move", "mut", "override", "priv", "pub",
    "ref", "return", "self", "static", "struct", "super", "trait", "true", "try", "type", "typeof",
    "unsafe", "unsized", "use", "virtual", "where", "while", "yield",
];
let identifier = name.len() > 0;
for (c, i) in name.chars() {
    let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
    if !(letter || (i > 0 && c >= '0' && c <= '9')) {
        identifier = false;
    }
}
if !identifier || keywords.contains(name) {
    abort(`crate name "${name}": no Rust identifier, or a keyword -- choose another name`);
}
