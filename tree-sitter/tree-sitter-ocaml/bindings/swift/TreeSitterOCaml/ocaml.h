#ifndef TREE_SITTER_OCAML_H_
#define TREE_SITTER_OCAML_H_

typedef struct TSLanguage TSLanguage;

#ifdef __cplusplus
extern "C" {
#endif

extern TSLanguage *tree_sitter_ocaml();
extern TSLanguage *tree_sitter_ocaml_interface();

#ifdef __cplusplus
}
#endif

#endif  // TREE_SITTER_OCAML_H_
