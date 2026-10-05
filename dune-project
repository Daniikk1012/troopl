(lang dune 3.24)

(name troopl)

(generate_opam_files true)

(source (github Daniikk1012/troopl))

(authors "Daniyar Sarbassov"
         "Nazar Tasmulayev"
         "Bogdan Ichshenko")

; (maintainers "Name <maintainer@email.com>") ; TODO maintainer

; (license LICENSE) ; TODO choose licence

; (documentation https://url/to/documentation) ; TODO docs?

(package
 (name troopl)
 (synopsis "A powerful minimal OO language with object capability system")
 (description "TrOOPL is a minimal object-oriented programming language with a purely functional core, where dependency injection, mutability, and capabilities like I/O and file system access are managed through explicitly passed and constructed environment objects.")
 (depends ocaml uucp))
