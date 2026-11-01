# Opt-in scoped escape and cleanup

`control escape Body` calls Body's run/1 with an escape object exposing
`return Value`. It only handles that boundary's generative exception. The
escape expires at exit and rejects other threads/domains. Fatal runtime errors
are not caught as user exceptions.

`control ensure Body Cleanup` calls run/0 on both, cleanup exactly once on
normal completion or unwinding. Cleanup uses the environment at ensure's call.
The body's error/escape takes precedence if both body and cleanup fail.
A cleanup failure after normal body completion is propagated. Successful
handling restores caller diagnostics; existing Runtime.Error positions survive.
No cleanup guarantee is possible after process termination or resource exhaustion.

One escape around a tail-recursive loop has constant handler depth.
Repeatedly creating nested boundaries is not zero-cost. This implements the
non-local-escape alternative from proposal 7.4, not multi-shot call/cc.
Default v0.2 semantics remain unchanged without --experimental.
