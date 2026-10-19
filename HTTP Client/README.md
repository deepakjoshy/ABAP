# HTTP Client — the 404 that sets `sy-subrc = 0`, the call that commits your database LUW, and the logon popup nobody can click

Calling out of an ABAP system over HTTP goes through the **Internet Communication
Framework (ICF)**. There are two entirely separate client APIs, and they do not fail
in the same way:

| | Classic | Current |
|---|---|---|
| Factory | `CL_HTTP_CLIENT=>CREATE_BY_URL` / `CREATE_BY_DESTINATION` / `CREATE` | `CL_HTTP_DESTINATION_PROVIDER=>...` then `CL_WEB_HTTP_CLIENT_MANAGER=>CREATE_BY_HTTP_DESTINATION` |
| Client interface | `IF_HTTP_CLIENT` | `IF_WEB_HTTP_CLIENT` |
| Round trip | `send( )`, then `receive( )` | one `execute( i_method )` |
| Error style | classic exceptions, `sy-subrc`, `get_last_error( )` | class-based `CX_WEB_HTTP_CLIENT_ERROR` |
| Status code | `response->get_status( IMPORTING code = ... )` | `response->get_status( )-code` |

Most of the traps below are in the classic API, because that is what the installed
base is full of — and because the published examples for it are themselves wrong in
two places. The last section covers the current API and where it is **not** a
drop-in replacement.

## Trap 1: `sy-subrc` tells you about the network, not about the request

`send( )` and `receive( )` report whether the **conversation** happened. A server
that answers `404`, `403` or `500` has answered, so both methods succeed and
`sy-subrc` stays `0`. The HTTP status code lives in a different place entirely:

```abap
DATA: lv_code   TYPE i,
      lv_reason TYPE string.

lo_client->response->get_status( IMPORTING code = lv_code reason = lv_reason ).
IF lv_code <> 200.
*   The call worked. The request did not.
ENDIF.
```

This is not a subtle inference. The keyword documentation example *ICF - ABAP as
HTTP Client* checks `sy-subrc` after `create`, after `send` and after `receive`, and
then does this:

```abap
FINAL(html) = client->response->get_cdata( ).
out->write_html( html ).
```

No status check anywhere. Point that program at a path that does not exist and it
cheerfully renders the server error page as if it were the payload. Every
copy-paste descendant of it inherits the same hole, which is why "the interface
silently stopped working" so often turns out to be a `401` being parsed as JSON.

The inverted form is just as common in the wild:

```abap
* WRONG - reads the status only in the branch where there is no useful response
lo_client->receive( EXCEPTIONS http_communication_failure = 1 OTHERS = 4 ).
IF sy-subrc <> 0.
  lo_client->response->get_status( IMPORTING code = lv_code reason = lv_reason ).
ENDIF.
```

The two checks are about different things and both are needed: `sy-subrc` for
"did we reach the server", `get_status( )` for "did the server agree".

## Trap 2: the error handling in the SAP sample program can never run

*Example program: Executing an HTTP Request* in the Connectivity documentation sends
the request like this (verbatim, including the comparison operator):

```abap
call method client-send
  exporting  timeout = timeout
  exceptions http_communication_failure  = 1
             http_invalid_state          = 2
             http_processing_failed      = 3
             others                      = 4.
if sy-subrc < 0.
  call method client-get_last_error
...
```

`sy-subrc` is never negative. The classic exception mapping above can only ever set
it to `0`, `1`, `2`, `3` or `4`, so `IF sy-subrc < 0` is dead code and **every send
failure is swallowed**. The program then walks on into `receive( )`, where the same
document correctly writes `if sy-subrc <> 0.` two steps later.

The page carries its own disclaimer — "This program shows a simplified sample code.
It is _not_ meant as a template for real coding." — which is fair warning, but the
typo sits in the half of the code that gets copied without reading. If an outbound
interface reports success and the partner never received anything, grep the sending
report for `< 0`.

## Trap 3: every HTTP call ends your database LUW

ICF communication is in the documented list of **implicit database commits**:

> "HTTP/HTTPS/SMTP communication executed using the Internet Communication Framework
>
> A database commit is executed before each response is sent in an ICF server program
> or ICF client program. An exception to this are updates. This behavior is
> independent of whether the communication is stateless or stateful."

And a database commit is not a quiet event:

> "A database commit closes all opened database cursors. In particular, in `SELECT`
> loops and after the statement `OPEN CURSOR`, database commits should not be
> triggered by mistake in one of the ways listed here."

The `IF_HTTP_CLIENT` method documentation says the same thing from the other
direction, on **both** `SEND` and `RECEIVE` (the typo is in the original):

> "The method cannit [sic] be reused while another database cursor is being used (in
> a loop, for example `SELECT/LOOP/EXEC SQL` or before a `FETCH` order) since they
> can trigger implicit database commits and thereby leads to closing the associated
> database cursor."

Two concrete consequences:

- **A per-row HTTP call inside a `SELECT` loop dumps.** Not at the HTTP call — at the
  next implicit fetch, as `DBSQL_INVALID_CURSOR`. Read the keys into an internal
  table first, then loop over the table and call out. Same shape as the guidance in
  [Mass Data Processing](../Mass%20Data%20Processing#readme).
- **"Insert, notify over HTTP, roll back if the notify fails" is not atomic.** The
  notification itself committed the insert. If the remote call belongs to the
  business transaction, register the work in the
  [update task](../Update%20Task#readme) — which is also the one context the
  documentation excludes from the implicit commit.

## Trap 4: the documented default of `PROPERTYTYPE_ACCEPT_COOKIE` contradicts itself

Two SAP pages describing the same attribute of the same interface disagree.

*Attributes of IF_HTTP_CLIENT* lists:

> "`PROPERTYTYPE_ACCEPT_COOKIE` | Accept cookie fields from the response (default:
> `CO_ENABLED`)"

*Example program: Executing an HTTP Request*, describing the same attribute, says:

> "You can set `PROPERTYTYPE_ACCEPT_COOKIE` to different values. The default value is
> CO_DISABLED, but values CO_ENABLED (always accept cookies), CO_PROMPT ... and
> CO_EVENT ... are also available."

A third page, on consuming REST services, implies the same as the second — it tells
you cookie acceptance is something you have to switch on:

> "If the HTTP client gets re-used for multiple subsequent calls or you are using not
> a basic authentication (e.g. X509 client authentication, SAML, etc.) you have to
> accept cookies returned by the ABAP server by enabling the attribute
> `propertytype_accept_cookie`."

So the documentation is 2-1 for `CO_DISABLED`, and this note does not try to settle
it. The practical rule is the one the documentation itself gives on both the
attribute and constant pages: *"Compare the list of attributes with the current list
in transaction SE24."* **Set the property explicitly** rather than relying on a
default that two SAP pages describe differently:

```abap
lo_client->propertytype_accept_cookie = if_http_client=>co_enabled.
```

It matters because of what it is for: reusing one client object for several calls
against an ABAP server works without re-authenticating each time only because the
logon ticket arrives as a cookie. Accepting cookies is not the same as keeping a
session, and the same page is explicit that it should not be used as one — "Do not
use a session keeping HTTP connection ... because that would contradict the REST
principle of a stateless communication."

## Trap 5: the logon popup is on by default, and a background job has nobody to click it

> "`PROPERTYTYPE_LOGON_POPUP` | Logon screen display (default: `CO_ENABLED`)"

The *Attributes* page lists **all five** property attributes with the default
`CO_ENABLED` — including `PROPERTYTYPE_ACCEPT_COOKIE`, which is the contradiction in
Trap 4. Two of those defaults deserve attention in anything unattended.

**Reading note, flagged as inference.** The documentation does not spell out what a
logon popup does in a batch work process. It does say precisely this about the other
popup the HTTP client can raise, the cookie prompt:

> "CO_PROMPT | Cookie handling: the prompt popup of the HTTP client opens, asking
> whether you want to accept cookies. **Note:** In background operation
> (communication without the SAP GUI) this is not practical; use `CO_EVENT`
> instead."

Treat the logon popup the same way: a credentials problem that produces a popup in
SE38 produces an authentication failure in a job, so the same code "works in
dialog, fails in background". The fix is to supply credentials rather than let the
framework ask for them, and to switch the popup off:

```abap
lo_client->propertytype_logon_popup = if_http_client=>co_disabled.
```

That SAP considers this worth controlling is visible in the current API, which
promoted it from a public attribute to a method: `SET_LOGON_POPUP_POLICY` — "Lets
you define whether a logon popup should be displayed during authentication."

`PROPERTYTYPE_REDIRECT = CO_ENABLED` is the other one: redirects are followed
silently, so a `301` from HTTP to HTTPS, or from one tenant host to another, is
invisible in your code and the status code you read is the one from the final hop.

## Trap 6: the HTTP method is chosen by whether there is a body

Setting the request method is optional, and what you get when you leave it out is
not a constant:

> "Setting the HTTP request method to GET is optional. **Note:** If this field is not
> set, the system uses GET if the HTTP request does not contain a body. Otherwise, it
> uses POST."

So the verb is a function of the payload:

- An intended `POST` whose body turns out empty (a cleared variable, a serializer
  that returned nothing) goes out as a **GET**. The server answers `405` or, worse,
  `200` with a listing — and nothing in the ABAP code looks wrong.
- Attaching a body to a `GET` for debugging purposes silently turns it into a
  **POST**.

Always say it out loud:

```abap
lo_client->request->set_method( if_http_request=>co_request_method_post ).
lo_client->request->set_content_type( content_type = 'application/json' ).
lo_client->request->set_cdata( lv_json_body ).
```

The protocol version is worth being explicit about for the same reason — the sample
program defaults its own parameter to `HTTP/1.0`:

```abap
lo_client->request->set_version( if_http_request=>co_protocol_version_1_1 ).
```

## Trap 7: the URI is not the URL, and `receive( )` is mandatory

`CREATE_BY_URL` takes a base address; the path and query string are set separately,
and not with a plain string assignment:

> "You must set the request URI unless the whole path was specified as a path prefix
> using the Destination (SM59). Here you use method `set_request_uri` of class
> `cl_http_utility`."

```abap
cl_http_utility=>set_request_uri( request = lo_client->request
                                  uri     = '/api/v1/orders?status=open' ).
```

Query **values** still have to be escaped individually. The *Methods* page lists
`ESCAPE_URL` / `UNESCAPE_URL` with the instruction "Use the method from
`IF_HTTP_UTILITY`", or use `APPEND_FIELD_URL`, documented as "Appends the name/value
pair to the query string of the URL". A material number with a `#` or a `+` in it is
otherwise a silently truncated or silently altered request parameter.

`receive( )` is not optional even when you do not care about the answer:

> "`RECEIVE` | Enters the response in the RESPONSE structure. This method must be
> called for every HTTP request, so that the data received can be processed."

And neither is `close( )`:

> "`CLOSE` | Closes the HTTP connection. This method is called when the HTTP
> connection, that is, the control block, is no longer needed."

A report that returns early on an error path without calling `close( )` leaks the
connection for the life of the internal session. The exit paths in the demo all go
through one `close( )`.

## Timeouts

`send( )` takes the timeout **in seconds** and has two named constants:

> "The timeout for the waiting period for the response is communicated to the method
> in the form of seconds. The constants `CO_TIMEOUT_DEFAULT` and
> `CO_TIMEOUT_INFINITE` can also be used here."

`CO_TIMEOUT_DEFAULT` is documented as "Timeout standard value (instance timeout)" —
an instance-level setting rather than a value in your program, so the same report can
block for different lengths of time on different systems.
`CO_TIMEOUT_INFINITE` is "No timeout", which in a dialog step means the work process
is held until something else kills it. Pass a real number.

## Destinations, authorization and proxies

`CREATE_BY_URL` puts the host, the credentials and the TLS configuration in your
code. `CREATE_BY_DESTINATION` puts them in an SM59 destination, and the
documentation has a clear preference:

> "SAP recommends that you use a fixed destination, as this reduces the need for
> configuration of communication parameters."

The exception lists are also different, and one of them is easy to misread:

```abap
cl_http_client=>create_by_destination(
  EXPORTING destination              = lv_dest
  IMPORTING client                   = lo_client
  EXCEPTIONS argument_not_found       = 1
             destination_not_found    = 2
             destination_no_authority = 3
             plugin_not_active        = 4
             internal_error           = 5
             OTHERS                   = 6 ).
```

`destination_no_authority` means **the calling ABAP user may not use this
destination** (`S_ICF`). It is not a remote `401` or `403` — it is raised locally,
before any packet leaves the system, and it arrives as `sy-subrc = 3` **with the
mapping written above** rather than as a status code — the numbers in a classic
exception mapping are assigned by the caller, and the SAP page numbers the same
six exceptions differently. A handler that only logs "HTTP create failed" turns an
authorization problem into an unexplained one. See
[Authorization Checks](../Authorization%20Checks#readme).

Proxies: `PROPERTYTYPE_APPLY_SPROXY` is documented as "Evaluate system proxy
configuration (default: `CO_ENABLED`)", and the `CREATE` factory accepting
`proxy_host` / `proxy_service` "overrides any configuration that was made in
Transaction SICF". The keyword-doc example for the HTTP client closes with a hint
that is, in practice, the first thing to check on a developer system that cannot
reach the internet: "For the example to work, the proxy setting for the HTTP client
must be configured correctly in transaction `SICF`."

## The current API, and where it is not a drop-in

The ABAP Cloud / released API replaces the client with two objects — a
**destination** and a **client** — and collapses the round trip into one call:

```abap
DATA(lo_dest) = cl_http_destination_provider=>create_by_url( i_url = lv_url ).
DATA(lo_http) = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).

lo_http->get_http_request( )->set_text( lv_body ).

DATA(lo_resp)   = lo_http->execute( if_web_http_client=>post ).
DATA(ls_status) = lo_resp->get_status( ).
IF ls_status-code <> 200.
*   ...
ENDIF.
lo_http->close( ).
```

Differences that break a mechanical port:

- **No `sy-subrc` anywhere.** `execute( )` raises `CX_WEB_HTTP_CLIENT_ERROR`, and the
  destination factories raise `CX_HTTP_DEST_PROVIDER_ERROR`. Classic exception
  handling translated line by line produces code that catches nothing, and a
  `TRY ... CATCH` wrapped around only the factory call misses the execute.
- **Reading the status code can itself fail.** `get_status( )` returns a structure
  and raises `CX_WEB_MESSAGE_ERROR`; so do `get_text( )`, `get_binary( )` and every
  header getter on `IF_WEB_HTTP_RESPONSE`. The classic `get_status( IMPORTING ... )`
  had no exceptions at all.
- **The method is an integer constant, not a string.** `if_web_http_client=>get`,
  `post`, `put`, `delete`, `head`, `options`, `patch`, `trace`, `connect` are all
  `TYPE I`. There is no "whatever is in this variable" verb.
- **`SET_CSRF_TOKEN` performs a real HTTP round trip** — a `HEAD` request — and
  raises `CX_WEB_HTTP_CLIENT_ERROR`. It is a network call, not a setter, so it is
  also an implicit database commit.
- **`RETRY_EXECUTE` exists**, with the status codes that trigger a retry and an
  idempotency flag as parameters. A hand-rolled retry loop is no longer the answer,
  and each retry is another commit.
- **Destinations come from four places**, not two: `create_by_url`,
  `create_by_destination` (typed `RFCDEST`, i.e. SM59), `create_by_cloud_destination`
  (BTP destination service) and `create_by_comm_arrangement` (a communication
  scenario). In ABAP Cloud the last two are usually the only correct ones.
- **The request object gained the things people hand-rolled.**
  `set_authorization_basic( )` / `set_authorization_bearer( )` replace the classic
  `authenticate( )` and the manual `Authorization` header; `set_uri_path( )` and
  `set_query( )` replace `cl_http_utility=>set_request_uri`; `set_form_field( )`
  replaces hand-built form bodies. All of them raise `CX_WEB_MESSAGE_ERROR` and
  return the request, so they chain.

**Availability (source: abapedia release snapshots, not an SAP statement).**
`IF_WEB_HTTP_CLIENT`, `CL_WEB_HTTP_CLIENT_MANAGER` and
`CL_HTTP_DESTINATION_PROVIDER` are all marked as not present on 7.54, 7.50 or 7.02,
while `IF_WEB_HTTP_REQUEST` and `IF_WEB_HTTP_RESPONSE` are both marked present on
7.54. That asymmetry is consistent with the message interfaces shipping first for
the HTTP **service** (inbound) side, with the client arriving later — but that
reading is an inference here, not documented. Check `CL_WEB_HTTP_CLIENT_MANAGER`
in SE24 on your own release before planning a migration, and see
[ABAP Language Versions](../ABAP%20Language%20Versions#readme) for why the classic
`CL_HTTP_CLIENT` is unusable in ABAP Cloud regardless of whether it exists.

## Checklist

1. `sy-subrc` after `create` / `send` / `receive` — and `<> 0`, never `< 0`.
2. `get_status( )` after `receive( )`, always, before touching the body.
3. No HTTP call inside a `SELECT` loop or between `OPEN CURSOR` and `FETCH`.
4. Set the method and the content type explicitly.
5. Set the URI with `cl_http_utility=>set_request_uri`, escape the query values.
6. `propertytype_logon_popup = co_disabled` for anything unattended.
7. A numeric timeout on `send( )`.
8. One `close( )` that every exit path reaches.

See also: [RFC Calls](../RFC%20Calls#readme) (the other outbound protocol, with the
same commit behaviour), [JSON & XML Serialization](../JSON%20Serialization#readme)
(what to do with the body),
[Byte Strings & Code Pages](../Byte%20Strings#readme) (`get_cdata` vs `get_data`),
[Exception Flow](../Exception%20Flow#readme),
[Background Jobs](../Background%20Jobs#readme).

**Transcription note.** Quotes are verbatim, with these deliberate deviations: SAP
inline hyperlink markup inside quoted sentences is dropped; table rows from the
*Attributes*, *Constants* and *Methods* pages of `IF_HTTP_CLIENT` are quoted as
`NAME | description` because the original is a two-column table; the *Note:* label
inside the `CO_PROMPT` and request-method quotes is SAP structure rendered inline;
**bold emphasis inside quotes is added here**; and `[sic]` marks SAP typos kept
verbatim (`cannit`, and the ungrammatical "thereby leads to"). The sample-program
snippet in Trap 2 is reproduced in the original lowercase with its own broken
`client-send` rendering of `client->send`, which is how that page renders arrow
operators throughout.

**Verification note.** Every quoted fragment above was checked by exact substring
match against the retrieved page text, not from memory: 41 of 41 matched. The
*Attributes* and *Constants* pages of `IF_HTTP_CLIENT` are short enough that they
were only available in full in two separate retrievals, which returned identical
text — so the three `(default: CO_ENABLED)` rows and the `CO_PROMPT` note rest on
that, rather than on the same byte-level check as the rest. The documented
`PROPERTYTYPE_ACCEPT_COOKIE` default is left unresolved on purpose (Trap 4). There
is no ABAP compiler here, so the demo report was checked by structural counting
(2/2 `CLASS`, 4/4 `METHOD`, 4 declared == 4 implemented, 6/6 `IF`, 1/1 `CASE`) and
a manual read, not a build.

---

**References**

- [ABAP keyword docs — ICF, ABAP as HTTP Client (example)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENICF_CLIENT_ABEXA.html)
- [ABAP keyword docs — Database Commit (implicit commits)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDB_COMMIT.html)
- [Connectivity — Example program: Executing an HTTP Request](https://help.sap.com/doc/saphelp_em92/9.2/en-US/48/c7c53bda5e31ebe10000000a42189b/content.htm)
- [Connectivity — Interface IF_HTTP_CLIENT](https://help.sap.com/doc/saphelp_em92/9.2/en-US/48/d4087c1904154ee10000000a421937/content.htm)
- [Connectivity — IF_HTTP_CLIENT Attributes](https://help.sap.com/doc/saphelp_em92/9.2/en-US/48/c7c468da5e31ebe10000000a42189b/content.htm)
- [Connectivity — IF_HTTP_CLIENT Constants](https://help.sap.com/doc/saphelp_em92/9.2/en-US/48/d5d667982b424be10000000a421937/content.htm)
- [Connectivity — IF_HTTP_CLIENT Methods](https://help.sap.com/doc/saphelp_em92/9.2/en-US/48/d649c6553b3e49e10000000a421937/content.htm)
- [SAP NetWeaver 7.4 — Creating the HTTP Client (REST consumption)](https://help.sap.com/docs/SAP_NETWEAVER_740/753088fc00704d0a80e7fbd6803c8adb/b286b4512ea4414fb36f17b0568a86ac.html)
- [ABAP Integration and Connectivity — HTTP Client Methods](https://help.sap.com/docs/abap-cloud/abap-integration-connectivity/http-client-methods)
- [abapedia — CL_WEB_HTTP_CLIENT_MANAGER](https://abapedia.org/steampunk-2111-api/cl_web_http_client_manager.clas.html)
- [abapedia — IF_WEB_HTTP_CLIENT](https://abapedia.org/steampunk-2111-api/if_web_http_client.intf.html)
- [abapedia — IF_WEB_HTTP_REQUEST](https://abapedia.org/steampunk-2111-api/if_web_http_request.intf.html)
- [abapedia — IF_WEB_HTTP_RESPONSE](https://abapedia.org/steampunk-2111-api/if_web_http_response.intf.html)
- [abapedia — CL_HTTP_DESTINATION_PROVIDER](https://abapedia.org/steampunk-2111-api/cl_http_destination_provider.clas.html)
