set tabstop=4
set termguicolors
set background=dark
colorscheme retrobox

set completeopt=menuone,noselect

filetype on
if v:version < 900 || !has('job') || !has('channel') || !executable('clangd') | finish | endif

let s:job = 0
let s:bufs = {}

function! s:uri(b) abort
  return 'file://' . fnamemodify(bufname(a:b), ':p')
endfunction

function! s:text(b) abort
  return join(getbufline(a:b, 1, '$'), "\n") . "\n"
endfunction

function! s:send(method, params) abort
  call ch_sendexpr(job_getchannel(s:job), {'method': a:method, 'params': a:params})
endfunction

function! s:message(ch, msg) abort
  if get(a:msg, 'method', '') !=# 'textDocument/publishDiagnostics' | return | endif
  let b = get(s:bufs, get(a:msg.params, 'uri', ''), -1)
  if b < 0 | return | endif
  silent! call prop_remove({'type': 'Clangd', 'bufnr': b, 'all': 1})
  let seen = {}
  for d in get(a:msg.params, 'diagnostics', [])
    let l = d.range.start.line + 1
    if has_key(seen, l) | continue | endif
    let seen[l] = 1
    silent! call prop_add(l, 0, {'bufnr': b, 'type': 'Clangd', 'text': '  ' . substitute(get(d, 'message', ''), '\n.*', '', ''), 'text_align': 'after'})
  endfor
endfunction

function! s:open() abort
  let b = bufnr('%')
  let uri = s:uri(b)
  if has_key(s:bufs, uri) | return | endif
  if s:job is# 0
    let s:job = job_start(['clangd', '--header-insertion=never'], {'in_mode': 'lsp', 'out_mode': 'lsp', 'err_io': 'null', 'out_cb': function('<SID>message')})
    if job_status(s:job) ==# 'fail' | let s:job = 0 | return | endif
    call ch_evalexpr(job_getchannel(s:job), {'method': 'initialize', 'params': {'processId': getpid(), 'rootUri': 'file://' . getcwd(), 'capabilities': {'offsetEncoding': ['utf-8'], 'general': {'positionEncodings': ['utf-8']}, 'textDocument': {'completion': {'completionItem': {'snippetSupport': v:false}}}}}})
    call s:send('initialized', {})
  endif
  let s:bufs[uri] = b
  call s:send('textDocument/didOpen', {'textDocument': {'uri': uri, 'languageId': &filetype, 'version': b:changedtick, 'text': s:text(b)}})
endfunction

function! s:complete(buf, tick, col, ch, msg) abort
  if bufnr('%') != a:buf || b:changedtick != a:tick || col('.') != a:col | return | endif
  let r = get(a:msg, 'result', [])
  let items = type(r) == v:t_dict ? get(r, 'items', []) : r
  let words = []
  for x in items
    let w = has_key(x, 'textEdit') ? get(x.textEdit, 'newText', '') : get(x, 'insertText', get(x, 'label', ''))
    if !empty(w) | call add(words, {'word': w, 'abbr': get(x, 'label', w), 'dup': 1}) | endif
  endfor
  let base = matchstr(strpart(getline('.'), 0, col('.') - 1), '\k*$')
  if !empty(words) | call complete(col('.') - strlen(base), words) | endif
endfunction

function! s:changed() abort
  call s:open()
  if s:job is# 0 | return | endif
  let b = bufnr('%')
  let tick = b:changedtick
  call s:send('textDocument/didChange', {'textDocument': {'uri': s:uri(b), 'version': tick}, 'contentChanges': [{'text': s:text(b)}]})
  if mode() !~# '^i' || strpart(getline('.'), 0, col('.') - 1) !~# '[[:alnum:]_.:>]$' | return | endif
  let c = col('.')
  call ch_sendexpr(job_getchannel(s:job), {'method': 'textDocument/completion', 'params': {'textDocument': {'uri': s:uri(b)}, 'position': {'line': line('.') - 1, 'character': c - 1}}}, {'callback': function('<SID>complete', [b, tick, c])})
endfunction

silent! call prop_type_add('Clangd', {'highlight': 'ErrorMsg'})
augroup clangd
  autocmd!
  autocmd FileType c,cpp call <SID>open()
  autocmd TextChanged,TextChangedI *.c,*.cc,*.cpp,*.cxx,*.h,*.hh,*.hpp,*.hxx call <SID>changed()
augroup END
