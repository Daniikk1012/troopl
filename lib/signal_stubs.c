/* waitpid exposes OCaml's portable signal identifiers. Convert back using
   the runtime's platform table, not hard-coded Linux signal numbers. */
#define CAML_INTERNALS
#include <caml/mlvalues.h>
#include <caml/signals.h>

CAMLprim value troopl_signal_number(value signal)
{
  return Val_int(caml_convert_signal_number(Int_val(signal)));
}
