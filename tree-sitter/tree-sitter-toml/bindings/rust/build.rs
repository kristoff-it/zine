fn main() {
    let src_dir = std::path::Path::new("src");
    let parser_path = src_dir.join("parser.c");
    let scanner_path = src_dir.join("scanner.c");

    cc::Build::new()
        .include(&src_dir)
        .flag_if_supported("-Wno-unused-parameter")
        .flag_if_supported("-Wno-unused-but-set-variable")
        .flag_if_supported("-Wno-trigraphs")
        .file(&parser_path)
        .file(&scanner_path)
        .compile("parser");

    println!("cargo:rerun-if-changed={}", scanner_path.to_str().unwrap());
    println!("cargo:rerun-if-changed={}", parser_path.to_str().unwrap());
}
