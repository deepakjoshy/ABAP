
TYPES: ty_numbers TYPE STANDARD TABLE OF i WITH EMPTY KEY.
DATA: lt_numbers TYPE ty_numbers.


* VALUE FOR Loop
lt_numbers = VALUE ty_numbers( FOR  i = 1 THEN i + 1  WHILE i LE 10 ( i ) ).


* REDUCE FOR Loop - Variation 1
DATA(sum1) = REDUCE i( INIT sum = 0 FOR n = 1  UNTIL n GT 10 NEXT sum = sum + lt_numbers[ n ] ).


* REDUCE FOR Loop - Variation 2
DATA(sum2) = REDUCE i( INIT sum = 0 FOR n = 1 THEN n + 1 WHILE n LE 10 NEXT sum = sum + lt_numbers[ n ] ).


* FOR Loop with WHERE condition with FIELD SYMBOLS
DATA(filter) = VALUE ty_numbers( FOR <fs> IN lt_numbers WHERE ( table_line GT 5 ) ( <fs> ) ).


