# ABAP Channels (AMC & APC) — the subscribe that commits your LUW, the 60-second wait that returns instantly, and the SAP page that misspells its own class

Two frameworks, one pair of ideas. **ABAP Messaging Channels (AMC)** are
publish/subscribe between ABAP sessions; **ABAP Push Channels (APC)** are
WebSocket and TCP-socket connections to the outside world. Together they are how a
long-running background job tells a Fiori screen it is 40% done, and how an ABAP
system talks to a browser or a PLC without polling.

> "ABAP Messaging Channels (AMC) are a method of communication between ABAP programs using messages. Using a publish and subscribe mechanism, messages can be exchanged between any AS ABAP programs, which allows communication between different user sessions and AS instances."

Everything that bites here comes from three facts the APIs do not advertise:

1. **Channel traffic is not inside your database LUW.** Subscribing, unsubscribing,
   binding, sending and waiting all trigger a database commit.
2. **A channel is not a queue.** Nothing is stored. A message with no registered
   consumer is simply gone, and the sender is not told.
3. **`WAIT` does not necessarily wait.** The statement that looks like a 60-second
   blocking read returns in microseconds in the one case you will hit first.

## Trap 1: subscribing to a channel commits your database LUW

Same family as [HTTP Client](../HTTP%20Client#readme) and
[Commit Work Events](../Commit%20Work%20Events#readme), but easier to walk into,
because `start_message_delivery` reads like a local registration call -- nothing
about it suggests the database.

> "The methods START_MESSAGE_DELIVERY and STOP_MESSAGE_DELIVERY both cause a database commit."

APC is worse, because there is no single call to point at:

> "Each communication step using ABAP Push Channels, such as sending a message or responding to an event, can trigger the change of the work process and usually triggers a database commit."

> "Each time a message is sent and each time APC processing is exited, a database commit is executed, except during updates."

Binding the two frameworks together commits twice more:

> "The methods BIND_AMC_MESSAGE_CONSUMER and UNBIND_AMC_MESSAGE_CONSUMER both cause a database commit."

And so does the wait itself, whenever it genuinely suspends:

> "If the statement WAIT interrupts the program, the work process is changed, and a database commit is executed, except in updates. For this reason, WAIT must not be used between ABAP SQL statements that open or close a database cursor."

The practical consequences, in order of how often they happen:

- **The progress notification splits the unit of work.** Post the document, send
  a progress message, post the next document: the first posting is already
  committed and a later `ROLLBACK WORK` cannot take it back.
- **Cursors die.** A `WAIT` (or a send, or a subscribe) between `OPEN CURSOR` and
  `FETCH` closes the cursor; the next `FETCH` dumps with `DBSQL_INVALID_CURSOR`.
  See [Mass Data Processing](../Mass%20Data%20Processing#readme) -- and note that
  `OPEN CURSOR WITH HOLD` does **not** protect you here.
- **The same code behaves differently in update processing.** Every quote above
  carves out updates, and AMC carves out more than the commit:

> "It is not possible to receive AMC messages during the update process."

> "It is not possible to associate APC with AMC during updates."

The fix is the same one as for every implicit commit: do the database work, end
the LUW deliberately, and *then* notify. Notification is not part of the
transaction and cannot be made part of it.

## Trap 2: `WAIT FOR MESSAGING CHANNELS` returns instantly, and `sy-subrc = 4` has two meanings

The receive side looks like a blocking read with a timeout:

```abap
WAIT FOR MESSAGING CHANNELS
     UNTIL receiver->message IS NOT INITIAL
     UP TO 60 SECONDS.
```

It is not. If no consumer is registered in the current internal session, the
statement does not wait at all:

> "If the result of log_exp is false and no receiver is registered for AMC messages, the execution of the program is not interrupted, regardless of the result of log_exp, and sy-subrc is set to the value 4."

> "If no receiver is registered for AMC messages, the addition UP TO sec SECONDS is ignored."

So the two easiest mistakes -- forgetting `start_message_delivery`, or calling it
*after* the `WAIT` -- do not produce a hang or a timeout. They produce a `WAIT`
that falls straight through. Wrapped in the usual `DO ... ENDDO` retry loop, that
is a work process spinning at 100% CPU on a statement whose name says it is idle.

The documented return codes:

| `sy-subrc` | Documented meaning |
|---|---|
| 0 | "The logical expression `log_exp` is true." |
| 4 | Condition false **and** either nothing is registered, or every pending `RECEIVE` has already run |
| 8 | "The logical expression `log_exp` is false and when the addition `UP TO` was specified, the maximum time was exceeded." |

`4` is the ambiguous one. The doc gives it for the no-consumer case above *and*
for this one:

> "If the new check on the result of the logical expression is false and the RECEIVE methods of all previously sent messages were executed, sy-subrc is set to 4 and the execution of the program is continued with the statement that follows WAIT."

*Nobody is listening* and *messages arrived but the condition is still false* are
the same return code. Only `8` tells you a timeout really elapsed, and `8` is only
reachable if you wrote `UP TO`. Leave `UP TO` off, keep a consumer registered, and
write a condition that never becomes true: the documented exits are gone. *That* is
the real hang, and it is the opposite of the code people think hangs. (Inference
from the system-field table -- the doc does not state an unbounded case explicitly.)

Two more details on the timeout:

> "The addition UP TO sec SECONDS is ignored with respect to the execution of the RECEIVE methods. Their execution duration can be longer than the time span specified."

`UP TO 10 SECONDS` is therefore a floor on responsiveness, not a ceiling on
runtime -- a slow `RECEIVE` callback overruns it freely. And the type is not what
you would guess:

> "sec expects a data object of the type f that must contain a positive number. The unit of the number in sec is seconds and the time resolution is one millisecond."

A negative value is **not** catchable:

> "Cause: Negative time specified for sec."

`WAIT_ILLEGAL_TIME_LIMIT` is an uncatchable runtime error, so a configured wait
time arriving as `-1` takes the program down past any `TRY ... CATCH`. Validate
before the statement, not around it. (SAP own demo `DEMO_RECEIVE_AMC` passes
`DATA(time) = 60`, which is type `i`, not `f` -- the implicit conversion is fine,
but it means the published example does not demonstrate the documented type.)

## Trap 3: a functional method in the `UNTIL` condition runs again for every message

> "If the logical expression is false, the running program is stopped in its current state. After a RECEIVE method, all data objects that were not changed in the RECEIVE method have the same value as when the logical expression was last evaluated. Any methods called by functions within the logical expression are executed again during the next check."

The first half is reassuring: your state survives. The last sentence is the trap.
A condition like

```abap
WAIT FOR MESSAGING CHANNELS
     UNTIL lo_collector->is_complete( ) = abap_true
     UP TO lv_secs SECONDS.
```

calls `is_complete( )` once per *arriving message*, not once. Anything that method
does -- counters, logging, a database read, a lazy load -- happens N times, where N
is traffic you do not control. Keep the condition a pure comparison against an
attribute the `RECEIVE` callback sets, which is exactly how SAP own examples write it.

## Trap 4: who receives is decided by the channel definition, not by your code

An AMC channel is a repository object (transaction `SAMC`), and two of its
properties silently decide whether your message arrives.

**Scope.**

> "The scope defines who can receive a message sent using this messaging channel."

| Scope | Who can receive |
|---|---|
| *System* | all programs of all user sessions in the current AS ABAP |
| *Client* | only sessions logged on with the same client ID as the sender |
| *User* | only sessions with the same user name **and** the same client ID |

The classic failure: the sender is a background job. A job runs under its own step
user, so on a *User*-scope channel the dialog session watching for progress gets
nothing -- and nothing anywhere reports an error. It works perfectly in the
developer test, where both sides are the same user in the same client.

**Authorized programs.** The access check is on *program names*, listed in the
channel definition:

> "Each program that is authorized to send or receive messages using the messaging channel or a predecessor program in the current"

> "must be specified with the appropriate activity in an include list."

(The sentence is interrupted by a link to *call sequence*; the two halves above are
verbatim. Note that the wording admits two readings -- the program itself, *or* a
predecessor in the call sequence -- and the doc does not disambiguate.) The
activities are *Send*, *Receive*, and *Bind APC WebSocket as consumer*.

Consequences worth internalising:

- This is **not** a `S_*` authorization object and **not** user-based. You cannot
  fix a failure here in PFCG.
- Refactoring the `send` call into a reusable global class moves it to a different
  program, so the include list must be updated or the call starts raising
  `CX_AMC_ERROR`. Working code breaks on a pure refactor.
- The channel name itself has rules: "The name must start with a forward slash
  character (/) and is not case-sensitive."

## Trap 5: send is fire-and-forget, and nothing is persisted

> "The sender of an AMC message implements the publish part of the publish-and-subscribe mechanism in AMC. The sender does not usually know whether receivers are registered for the AMC message."

> "Messages sent using the messaging channel are received only if the program is ready to receive."

A successful `send( )` means the framework accepted the message. It does not mean
anyone got it, and there is no store-and-forward: a consumer that registers one
second later has missed it. AMC is a notification bus, not a queue -- if the
message must survive, use [Update Task](../Update%20Task#readme) or a database
table and treat the channel purely as a nudge.

Point-to-point (7.50+) is the one place you can get a delivery guarantee, and it is
off by default. `CREATE_MESSAGE_PRODUCER_BY_ID` takes a consumer session ID plus:

> "The parameter I_COMMUNICATION_TYPE of the method CREATE_MESSAGE_PRODUCER_BY_ID can be used to configure whether a message is sent synchronously or asynchronously, whereby the latter is the default. When a message is sent synchronously, the sender waits for confirmation that the message was passed to the receiver session and otherwise raises an exception."

So asynchronous (the default) is silent on failure; `co_comm_type_synchronous`
raises an exception when the target session is gone (`CX_AMC_ERROR` is the AMC error
class; the doc says only "raises an exception"). The receiver gets its own ID from
`CL_AMC_CHANNEL_MANAGER=>GET_CONSUMER_SESSION_ID` and has to hand it to the
sender somehow -- which is application work the framework does not do for you.

**Size.** Both frameworks share one ceiling:

> "The sendable messages are currently subject to a standard length restriction of approximately 1 MB."

Character strings are converted to UTF-8 first, so a string of multi-byte
characters hits the limit well before 1 million characters. The limit is a profile
parameter (`rdisp/long_messages/max_length`), i.e. a basis change, not a code
change -- so do not design a channel to carry an ALV export. Send a key and let the
receiver read the data.

## Trap 6: do not copy the identifiers out of the SAP Help Portal prose

This one is unusual enough to be worth documenting, because it will cost you a
syntax error and twenty minutes. Three separate published errors, all still live.

**(a) The class name.** The *Sending AMC Messages* page names the factory class in
prose as:

> "CL_AMC_CLINET_MANAGER=>CREATE_MESSAGE_PRODUCER"

`CLINET` is a typo for `CHANNEL`, and the sample program *on the same page* proves
it -- it calls `cl_amc_channel_manager=>create_message_producer(`. The ABAP keyword
documentation says `CL_AMC_CHANNEL_MANAGER` throughout. Resolved: the code is right,
the prose is wrong. The *Receiving AMC Messages* page carries the identical typo
with `CREATE_MESSAGE_CONSUMER`, so it is systematic, not a one-off.

**(b) The echo parameter.** The same page lists the parameter as:

> "I_SUPRESS_ECHO (optional): Allows the sender object to avoid receiving own messages."

One `P`. Its own code example passes `i_suppress_echo  = no_echo`, and both keyword-doc
pages spell it `I_SUPPRESS_ECHO`. Resolved 3-1 in favour of two `P`s, by the page
contradicting itself. Default is `abap_false`, so by default **you receive your own
messages** -- which matters the moment a session both sends and subscribes, the
normal shape for an APC/AMC bridge.

**(c) The `WAIT` page describes the wrong framework.** The opening bullet of
`WAIT FOR MESSAGING CHANNELS` -- the AMC statement -- reads:

> "If the result of log_exp is false and a receiver is registered for APC messages, the program waits until an ON_MESSAGE method has been executed for a message sent by a sender program and checks the logical expression again"

`APC` and `ON_MESSAGE` belong to the push-channel variant; AMC callbacks are named
`RECEIVE`, as the very next sub-bullet on the same page says. It is a copy-paste
from `WAIT FOR PUSH CHANNELS`, where the identical sentence is correct. Read the
system-field table, not the prose.

## Trap 7: in a stateful APC handler, half the language is illegal

A stateful APC server (or stateful detached client) runs in **non-blocking mode**,
because the session must stay available for inbound messages. The forbidden list is
long and includes things that appear in ordinary utility code:

| Group | Not allowed in non-blocking mode |
|---|---|
| Calls | `SUBMIT`, `CALL TRANSACTION`, `CALL FUNCTION DESTINATION` for sRFC, `CALL DIALOG`, `CALL SCREEN`, `CALL SELECTION-SCREEN`, `SET SCREEN` |
| Exit | `LEAVE LIST-PROCESSING`, `LEAVE PROGRAM`, `LEAVE SCREEN`, `LEAVE TO TRANSACTION`, `LEAVE TO LIST-PROCESSING`, and `CHECK`/`EXIT`/`STOP`/`REJECT` for exiting reporting events |
| Wait | `WAIT UP TO`, `WAIT FOR ...`, `COMMUNICATION` |

> "Using a statement like this in non-blocking mode produces the runtime error APC_ILLEGAL_STATEMENT."

Note what that does to the obvious design: you cannot `SUBMIT` a report from a
stateful handler, and you cannot make a synchronous RFC call. The replacement for
waiting is a timer, not a `WAIT`:

> "The statement WAIT is not allowed in non-blocking mode."

> "ABAP Timers can only be used in non-blocking mode, namely"

(`CL_ABAP_TIMER_MANAGER` / `IF_ABAP_TIMER_HANDLER`; the sentence continues into
links to APC and ABAP daemon sessions.) So the API that replaces `WAIT` inside a
handler is the API you are *not* allowed to use outside one.

The APC **client** handler has the mirror-image restriction, and it collides
head-on with Trap 1:

> "When a method like this is being processed, no database commit can be executed, implicitly or explicitly, since this causes the runtime error APC_ILLEGAL_STATEMENT."

Read those two together: every AMC `start_message_delivery` causes a database
commit, and a database commit inside a client `ON_MESSAGE` is a runtime error --
so subscribing to an AMC channel from inside an APC client message handler should
be expected to dump. The doc does not spell out that combination; it is an
inference from the two statements above, flagged here rather than asserted.

## Smaller things worth knowing

- **Exceptions:** `CX_AMC_ERROR` for AMC, `CX_APC_ERROR` for APC, and
  `CX_AC_MESSAGE_TYPE_PCP_ERROR` for PCP serialization. The AMC one covers
  "violations of rules set by the properties of a messaging channel" -- i.e. the
  include list and the scope -- so a `CX_AMC_ERROR` on `create_message_producer` is
  almost always a channel-definition problem, not a runtime failure.
- **Binding is once-only:** "A push channel can only be linked with a messaging
  channel once." Rebinding raises, and so does unbinding something never bound.
- **No AMC over TCP:** "It is not possible to associate APC with AMC for TCP
  sockets." WebSocket only.
- **WebSockets are same-origin by default.** Other origins must be registered in
  table `APC_CROSS_ORIGIN` (transaction `SAPC_CROSS_ORIGIN`) with authorization
  object `S_APC_ORIG`. A browser page served from a different host fails here, not
  in your ABAP.
- **The APC ICF node is generated but not necessarily active** -- it is visible in
  `SICF` and "can be activated and deactivated in the service editor, but not
  tested directly", so the usual *Test service* reflex does not work.
- **Three message types only:** *TEXT* (string), *BINARY* (xstring), *PCP*. Anything
  structured goes through [JSON Serialization](../JSON%20Serialization#readme) first.

## Minimum working shapes

Sender (publish):

```abap
TRY.
    CAST if_amc_message_producer_text(
      cl_amc_channel_manager=>create_message_producer(
        i_application_id = 'YDJ_AMC'
        i_channel_id     = '/progress'
        i_suppress_echo  = abap_true )   " two P's -- see Trap 6b
      )->send( i_message = |Step { lv_step } of { lv_total }| ).
  CATCH cx_amc_error INTO DATA(lx_amc).
    " channel definition / include list problem, not a network problem
    MESSAGE lx_amc->get_text( ) TYPE 'S' DISPLAY LIKE 'W'.
ENDTRY.
```

Receiver (subscribe, then wait):

```abap
DATA(lo_receiver) = NEW lcl_receiver( ).

cl_amc_channel_manager=>create_message_consumer(
    i_application_id = 'YDJ_AMC'
    i_channel_id     = '/progress'
  )->start_message_delivery( i_receiver = lo_receiver ).  " <-- commits!

DATA lv_secs TYPE f VALUE '30'.
WAIT FOR MESSAGING CHANNELS
     UNTIL lo_receiver->mv_count > 0
     UP TO lv_secs SECONDS.
DATA(lv_subrc) = sy-subrc.   " 0 = condition met, 4 = nothing registered OR
                             " condition still false, 8 = timed out
```

The `lv_subrc` capture on the line after `WAIT` is not decoration: `4` is the
return code you get when the subscribe silently did not take effect, and it is the
only signal you will ever receive about it.

## Quick reference

| Thing | Value |
|---|---|
| Factory class | `CL_AMC_CHANNEL_MANAGER` (**not** `CL_AMC_CLINET_MANAGER`) |
| Send | `CREATE_MESSAGE_PRODUCER` -> cast to `IF_AMC_MESSAGE_PRODUCER_TEXT`/`_BINARY`/`_PCP` -> `SEND` |
| Receive | `CREATE_MESSAGE_CONSUMER` -> `START_MESSAGE_DELIVERY( i_receiver = ... )` |
| Callback interfaces | `IF_AMC_MESSAGE_RECEIVER_TEXT` / `_BINARY` / `_PCP`, method `RECEIVE` |
| Point-to-point | `CREATE_MESSAGE_PRODUCER_BY_ID` + `GET_CONSUMER_SESSION_ID`; async by default |
| Echo suppression | `I_SUPPRESS_ECHO`, default `abap_false` |
| Wait | `WAIT FOR MESSAGING CHANNELS [PUSH CHANNELS] [ASYNCHRONOUS TASKS] UNTIL log_exp [UP TO sec SECONDS]` |
| `sec` type | `f`, positive; negative -> uncatchable `WAIT_ILLEGAL_TIME_LIMIT` |
| Message ceiling | ~1 MB, UTF-8; `rdisp/long_messages/max_length` |
| APC superclasses | `CL_APC_WSP_EXT_STATELESS_BASE` / `..._STATEFUL_BASE` (+ `_PCP_B` variants), `CL_APC_TCP_EXT_*` |
| APC client | `CL_APC_WSP_CLIENT_MANAGER=>CREATE_BY_URL` / `CREATE_BY_DESTINATION`, then `CONNECT` |
| Transactions | `SAMC` (AMC), `SAPC` (APC), `SMAMC` (registered consumers), `SMWS` (open APC connections), `AMC_LOG_ADMIN` |
| Exceptions | `CX_AMC_ERROR`, `CX_APC_ERROR`, `CX_AC_MESSAGE_TYPE_PCP_ERROR` |

## Demo

[`ydj_amc_channel_demo.abap`](ydj_amc_channel_demo.abap) -- one report that can act
as sender or receiver (or both) on a channel you name on the selection screen. It
registers a text consumer, waits with `UP TO`, and prints the three-way
`sy-subrc` interpretation plus the message count, so Trap 2 is visible rather than
described. No database access and no `COMMIT WORK` of its own -- but the subscribe
call commits, which is noted in the program header.

Defaults point at SAP own demo channel (`DEMO_AMC` / `/demo_text`, package
`SABAPDEMOS`). Unless your report is added to that channel include list it will
raise `CX_AMC_ERROR` -- which the demo catches and prints, because that failure *is*
Trap 4 and is worth seeing once. Create your own channel in `SAMC` to run it for real.

## Also in this repo

- [HTTP Client](../HTTP%20Client#readme) -- outbound ICF, the other framework that
  commits your LUW behind your back
- [Commit Work Events](../Commit%20Work%20Events#readme) -- what a commit actually does
- [Mass Data Processing](../Mass%20Data%20Processing#readme) -- why a commit between
  `OPEN CURSOR` and `FETCH` is fatal
- [Update Task](../Update%20Task#readme) -- the transactional alternative to a
  notification
- [Background Jobs](../Background%20Jobs#readme) -- the usual sender of progress messages
- [JSON Serialization](../JSON%20Serialization#readme) -- how structured data gets into
  a text or binary message
- [Program Calls](../Program%20Calls#readme) -- `SUBMIT`, which a stateful APC handler
  may not use

## Sources

- [ABAP Messaging Channels (AMC)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENAMC.html) -- keyword documentation
- [ABAP Push Channels (APC)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENAPC.html) -- keyword documentation
- [WAIT FOR MESSAGING CHANNELS](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/wait-for-messaging-channels?locale=en-US)
- [WAIT FOR PUSH CHANNELS](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/wait-for-push-channels?locale=en-US)
- [APC - Non-Blocking Mode](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/apc-non-blocking-mode?locale=en-US)
- [Sending AMC Messages](https://help.sap.com/docs/ABAP_PLATFORM_NEW/05d041d3df1a4595a3c45f57c15e2325/61f1e154725243dcad9051df9a8e8a94.html?locale=en-US) -- SAP Help Portal (source of the typos in Trap 6)
- [Receiving AMC Messages](https://help.sap.com/docs/ABAP_PLATFORM_NEW/05d041d3df1a4595a3c45f57c15e2325/a577e26a088049c5ae76270b9b04edbf.html?locale=en-US) -- SAP Help Portal
- SAP demo programs `DEMO_SEND_AMC`, `DEMO_RECEIVE_AMC`, `DEMO_APC_PING_PONG` (package `SABAPDEMOS`)
